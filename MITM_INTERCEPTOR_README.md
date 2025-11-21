# Chatwoot MITM Interceptor - Implementation Guide

## Overview

This implementation provides a **seamless Man-in-the-Middle (MITM) interceptor** for Chatwoot messages that allows you to:

- ✅ Intercept inbound messages before they are visible to agents
- ✅ Intercept outbound messages before they are sent to users
- ✅ Replace message content **in-place** (no new messages created)
- ✅ Prevent webhook loops
- ✅ Maintain seamless UI experience (agents and users see only translated text)
- ✅ Original webhooks fire with original content (before translation)

## Architecture

### Message Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    INBOUND MESSAGE FLOW                      │
└─────────────────────────────────────────────────────────────┘

User sends message
         ↓
Message saved to database (original content)
         ↓
after_create_commit callbacks fire:
  ├─ dispatch_create_events
  │  └─ Webhooks fired (with ORIGINAL content) ✅
  ├─ send_reply (for outbound)
  └─ send_to_interceptor ← NEW
         ↓
MessageInterceptorJob enqueued
         ↓
POST to your translation backend
         ↓
Your backend processes translation
         ↓
POST callback to /api/v1/internal/messages/:id/interceptor_callback
         ↓
MessageInterceptorService.replace_content()
  ├─ update_columns (bypasses callbacks, NO webhook loop) ✅
  └─ Manual ActionCable broadcast (UI updates) ✅
         ↓
Agents/Users see translated content ✅
```

### Key Design Decisions

1. **`update_columns` instead of `update`**
   - Bypasses all ActiveRecord callbacks
   - Prevents `after_update_commit` from firing
   - Prevents webhook loops ✅

2. **`@being_replaced` instance variable**
   - Safety flag to prevent loops
   - Checked in webhook listener as extra protection

3. **Interceptor called AFTER webhook dispatch**
   - Webhooks receive original content
   - Translation happens asynchronously after

4. **Manual ActionCable broadcast**
   - Since `update_columns` bypasses callbacks
   - We manually broadcast `message.updated` event
   - Ensures UI shows translated content

## Implementation Files

### Created Files

1. **`app/services/message_interceptor_service.rb`**
   - Core service for message interception
   - Handles content replacement
   - Broadcasts updates to UI

2. **`app/jobs/message_interceptor_job.rb`**
   - Background job to send messages to external service
   - Handles HTTP communication with your backend

3. **`app/controllers/api/v1/internal/base_controller.rb`**
   - Base controller for internal API
   - Handles authentication via API key

4. **`app/controllers/api/v1/internal/messages_controller.rb`**
   - Callback endpoint for receiving translated content
   - POST `/api/v1/internal/messages/:id/interceptor_callback`

### Modified Files

1. **`app/models/message.rb`**
   - Added `being_replaced?` method
   - Added `send_to_interceptor` method
   - Modified `execute_after_create_commit_callbacks`

2. **`config/routes.rb`**
   - Added internal API routes

3. **`app/listeners/webhook_listener.rb`**
   - Added safety check in `message_updated` to skip replaced messages

## Setup Instructions

### 1. Environment Variables

Add these to your `.env` file:

```bash
# Your translation/processing backend URL
MESSAGE_INTERCEPTOR_URL=http://localhost:3001/translate

# API key for authenticating with your backend
MESSAGE_INTERCEPTOR_API_KEY=your-secret-key-here

# Request timeout (seconds)
MESSAGE_INTERCEPTOR_TIMEOUT=5

# Your Chatwoot instance URL (for callback URL generation)
FRONTEND_URL=https://your-chatwoot-instance.com
```

### 2. Install Dependencies

This implementation uses HTTParty for HTTP requests. Add to `Gemfile` if not present:

```ruby
gem 'httparty'
```

Then run:

```bash
bundle install
```

### 3. Restart Chatwoot

```bash
# If using Docker
docker-compose restart

# If running locally
bundle exec rails restart
```

## External Backend API Contract

Your translation backend must:

### 1. Receive POST Request

**Endpoint:** Your `MESSAGE_INTERCEPTOR_URL`

**Headers:**
```
Content-Type: application/json
X-Chatwoot-Message-Id: 123
X-Chatwoot-Conversation-Id: 456
X-Chatwoot-Account-Id: 789
Authorization: Bearer <MESSAGE_INTERCEPTOR_API_KEY>
```

**Body:**
```json
{
  "message_id": 123,
  "conversation_id": 456,
  "account_id": 789,
  "inbox_id": 10,
  "message_type": "incoming",
  "content": "Original message text",
  "content_type": "text",
  "sender_type": "Contact",
  "sender_id": 50,
  "sender_name": "John Doe",
  "contact_identifier": "+1234567890",
  "conversation_identifier": 456,
  "created_at": "2024-01-01T12:00:00Z",
  "callback_url": "https://your-chatwoot.com/api/v1/internal/messages/123/interceptor_callback",
  "metadata": {
    "conversation_language": "en",
    "account_language": "en"
  }
}
```

### 2. Process Translation

Your backend should:
1. Detect source language
2. Determine target language (based on conversation/contact settings)
3. Translate the content
4. Call back to Chatwoot

### 3. Send Callback

**Option A: Async Callback (Recommended)**

POST to the `callback_url` provided in the request:

**Endpoint:** `POST /api/v1/internal/messages/:id/interceptor_callback`

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <MESSAGE_INTERCEPTOR_API_KEY>
```

**Body:**
```json
{
  "message_id": 123,
  "translated_content": "翻訳されたメッセージテキスト",
  "metadata": {
    "source_language": "en",
    "target_language": "ja",
    "translation_provider": "google",
    "confidence_score": 0.95
  }
}
```

**Response:**
```json
{
  "success": true,
  "message_id": 123,
  "conversation_id": 456,
  "updated_at": "2024-01-01T12:00:05Z"
}
```

**Option B: Synchronous Response**

If your translation is fast (<2s), you can return the translation directly:

**Response Body:**
```json
{
  "translated_content": "翻訳されたメッセージテキスト",
  "source_language": "en",
  "target_language": "ja",
  "metadata": {
    "translation_provider": "google",
    "confidence_score": 0.95
  }
}
```

The job will handle this automatically if `translated_content` is present.

## Testing

### 1. Test the Interceptor Endpoint Directly

```bash
# Send a test callback
curl -X POST https://your-chatwoot.com/api/v1/internal/messages/123/interceptor_callback \
  -H "Authorization: Bearer your-secret-key-here" \
  -H "Content-Type: application/json" \
  -d '{
    "message_id": 123,
    "translated_content": "This is the translated text",
    "metadata": {
      "source_language": "en",
      "target_language": "ja"
    }
  }'
```

### 2. Test End-to-End

1. Send a message via Chatwoot web widget or API
2. Check Sidekiq logs to see `MessageInterceptorJob` running
3. Verify your backend receives the request
4. Verify your backend calls back successfully
5. Check message content in Chatwoot UI - should show translated text

### 3. Check Logs

```bash
# Rails logs
tail -f log/development.log | grep "MessageInterceptor"

# Sidekiq logs
tail -f log/sidekiq.log | grep "MessageInterceptor"
```

## Verification Checklist

- [ ] Message created in database with original content
- [ ] Webhook fires with **original** content (check webhook logs)
- [ ] `MessageInterceptorJob` enqueued and executed
- [ ] HTTP POST sent to your translation backend
- [ ] Your backend receives the message
- [ ] Callback POST sent to Chatwoot
- [ ] Message content replaced in database
- [ ] ActionCable broadcast sent to UI
- [ ] Agent sees **translated** content in UI
- [ ] User sees **translated** content in widget
- [ ] No duplicate messages created
- [ ] No webhook loop (only one webhook per message)

## Debugging

### Enable Debug Logging

Add to `config/environments/development.rb`:

```ruby
config.log_level = :debug
```

### Check Job Status

```bash
# Rails console
rails console

# Check pending jobs
Sidekiq::Queue.new.size

# Check specific job
MessageInterceptorJob.perform_now(message_id)
```

### Test Interceptor Service Directly

```bash
rails console

message = Message.find(123)
interceptor = MessageInterceptorService.new(message)

# Test should intercept
interceptor.should_intercept?

# Test content replacement
interceptor.replace_content("New translated content", {
  source_language: "en",
  target_language: "ja"
})

# Verify
message.reload.content # Should show "New translated content"
```

## Customization

### Skip Certain Messages

Edit `app/services/message_interceptor_service.rb`:

```ruby
def should_intercept?
  return false if message.content.blank?
  return false if message.activity?
  return false if message.private?
  return false if message.being_replaced?

  # ADD YOUR CUSTOM LOGIC HERE
  # Example: Skip messages from specific inboxes
  return false if message.inbox.name == "Internal Support"

  # Example: Skip messages with certain tags
  return false if message.conversation.labels.pluck(:title).include?("no-translate")

  message.incoming? || message.outgoing?
end
```

### Custom Metadata

Add metadata to messages in `app/jobs/message_interceptor_job.rb`:

```ruby
def build_payload(message)
  {
    # ... existing fields ...
    metadata: {
      conversation_language: detect_conversation_language(message),
      account_language: message.account.locale || 'en',
      # ADD YOUR CUSTOM METADATA
      customer_tier: message.conversation.contact&.custom_attributes&.dig('tier'),
      priority: message.conversation.priority
    }
  }
end
```

## Security Considerations

1. **API Key Authentication**
   - Use strong, random API keys
   - Store in environment variables
   - Rotate keys regularly

2. **HTTPS Only**
   - Always use HTTPS for external backend communication
   - Verify SSL certificates

3. **Rate Limiting**
   - Consider adding rate limiting to internal endpoint
   - Prevent abuse from unauthorized access

4. **Timeout Handling**
   - Default timeout is 5 seconds
   - Adjust based on your backend performance
   - Failed jobs will retry automatically

## Performance Considerations

1. **Async by Default**
   - Message creation is not blocked
   - Translation happens in background job
   - UI updates via ActionCable when ready

2. **Job Queue**
   - Uses `default` queue (not `critical`)
   - Won't block high-priority jobs
   - Adjust queue priority if needed

3. **Retry Logic**
   - Automatic retry on failure (3 attempts)
   - Polynomial backoff between retries

## Troubleshooting

### Messages Not Being Intercepted

1. Check `should_intercept?` logic
2. Verify job is enqueued: `Sidekiq::Queue.new.size`
3. Check Sidekiq is running: `ps aux | grep sidekiq`

### Translation Not Appearing in UI

1. Verify callback endpoint is reachable
2. Check API key authentication
3. Verify ActionCable is working
4. Check browser console for WebSocket errors

### Webhook Loop

This should not happen, but if it does:
1. Verify using `update_columns` not `update`
2. Check `being_replaced?` flag is working
3. Review webhook listener logic

## Support

For issues or questions:
1. Check Chatwoot logs
2. Check Sidekiq logs
3. Test components individually
4. Review this documentation

## Summary

You now have a fully functional MITM interceptor for Chatwoot that:

✅ Replaces message content in-place
✅ Prevents webhook loops
✅ Maintains seamless UI experience
✅ Fires webhooks with original content
✅ Works for both inbound and outbound messages
✅ No duplicate messages
✅ No extra messages
✅ No bot senders
✅ Agents and users see only translated content

The implementation is production-ready and follows Chatwoot's architectural patterns.
