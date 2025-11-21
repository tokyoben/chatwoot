# Deploying Interceptor Fixes to AWS

## The Issue

Your environment variables ARE configured correctly:
```
MESSAGE_INTERCEPTOR_URL=https://ragwtwhk6453.jp.ngrok.io/interceptor/translate
MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276
```

But the interceptor code changes are only on your **local machine**, not on your **AWS server**.

## What Was Changed

### Files Modified:
1. `app/models/message.rb` - Added logging to track if method is called
2. `app/services/message_interceptor_service.rb` - Fixed infinite loop + added logging
3. `app/jobs/message_interceptor_job.rb` - Added logging

### Files Created:
1. `test_interceptor.rb` - Diagnostic script
2. Various documentation files

## Deployment Steps

### On Your Local Machine:

**1. Verify changes are saved:**
```bash
cd /Users/timewise/chatwoot
git status
```

You should see:
- `app/models/message.rb`
- `app/services/message_interceptor_service.rb`
- `app/jobs/message_interceptor_job.rb`
- Other files

**2. Commit the changes:**
```bash
git add app/models/message.rb
git add app/services/message_interceptor_service.rb
git add app/jobs/message_interceptor_job.rb
git add test_interceptor.rb
git add DEPLOY_INTERCEPTOR_FIXES.md
git add TRANSLATION_FIXES.md

git commit -m "Fix message interceptor: add logging and fix infinite loop

- Add comprehensive logging to track message interception
- Fix infinite loop by removing reload and consolidating update_columns
- Fix being_replaced flag being lost
- Add test script for diagnostics"
```

**3. Push to your remote repository:**
```bash
git push origin main
# Or whatever branch you're using
```

### On Your AWS Server:

**1. SSH into AWS:**
```bash
ssh your-aws-server
```

**2. Navigate to Chatwoot directory:**
```bash
cd /path/to/chatwoot
```

**3. Pull the latest changes:**
```bash
git pull origin main
# Or whatever branch you're using
```

**4. Check what was updated:**
```bash
git log -1 --stat
```

Should show the message.rb, service, and job files.

**5. Restart Puma (in tmux):**
```bash
# Attach to tmux session
tmux attach -t chatwoot  # or whatever your session name is

# Go to Puma window (Ctrl+B, then window number)
Ctrl+C  # Stop puma
bundle exec puma -C config/puma.rb  # Restart puma
```

**6. Restart Sidekiq (in tmux):**
```bash
# Go to Sidekiq window (Ctrl+B, then window number)
Ctrl+C  # Stop sidekiq
bundle exec sidekiq -C config/sidekiq.yml  # Restart sidekiq
```

**7. Run the test script:**
```bash
RAILS_ENV=production bundle exec ruby test_interceptor.rb
```

This will:
- Verify environment variables are loaded
- Test if a message would be intercepted
- Optionally test HTTP connectivity to RAG server

**8. Watch the logs:**
```bash
# In a new tmux window or detach with Ctrl+B, D
tail -f log/production.log | grep MessageInterceptor
```

**9. Send a test message:**

- Send a message from the widget or dashboard
- Watch the logs - you should immediately see:

```
Message#send_to_interceptor called for message 123
Message#send_to_interceptor: Calling service for message 123
MessageInterceptor: Checking message 123 (type: incoming, content: 'こんにちは')
MessageInterceptor: Intercepting message 123, will send to https://ragwtwhk6453.jp.ngrok.io/interceptor/translate
MessageInterceptorJob: Sending message 123 to https://ragwtwhk6453.jp.ngrok.io/interceptor/translate
```

## If Still Not Working

### Check 1: Are you on the right branch?
```bash
git branch
git log -1
```

### Check 2: Did puma/sidekiq actually restart?
```bash
ps aux | grep puma | grep chatwoot
ps aux | grep sidekiq | grep chatwoot
```

### Check 3: Are there any errors?
```bash
tail -50 log/production.log
tail -50 log/sidekiq.log
```

### Check 4: Is the code actually loaded?
```bash
RAILS_ENV=production bundle exec rails console

# In console:
> m = Message.last
> m.respond_to?(:send_to_interceptor)  # Should be true
> m.method(:send_to_interceptor).source_location
# Should show message.rb with correct line number
```

### Check 5: Run test script
```bash
RAILS_ENV=production bundle exec ruby test_interceptor.rb
```

## Common Issues

### "Git pull shows Already up to date"

You haven't pushed from local, or you're on the wrong branch:
```bash
# Local machine:
git push origin main

# AWS server:
git fetch
git pull origin main
```

### "Changes pulled but still not working"

Puma needs restart to load new code:
```bash
# MUST restart puma - code changes don't reload automatically
pkill -f "puma.*chatwoot"
bundle exec puma -C config/puma.rb
```

### "Logs still silent"

Either:
1. Messages are being skipped (check test_interceptor.rb output)
2. `send_to_interceptor` isn't being called (check message creation flow)
3. Code not actually updated (check git log)

### "Job enqueued but not executing"

Sidekiq not running or crashed:
```bash
ps aux | grep sidekiq
# If not running:
bundle exec sidekiq -C config/sidekiq.yml
```

## RAG Server Considerations

Your RAG server URL is using ngrok:
```
https://ragwtwhk6453.jp.ngrok.io
```

**Important:**
- Ngrok URLs change on restart unless you have a paid plan
- Make sure the ngrok tunnel is active
- Update MESSAGE_INTERCEPTOR_URL if ngrok URL changes

Test connectivity:
```bash
curl -X POST https://ragwtwhk6453.jp.ngrok.io/interceptor/translate \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276" \
  -d '{
    "message_id": 999,
    "content": "test",
    "callback_url": "https://chatwoot.casenavi.com/api/v1/internal/messages/999/interceptor_callback"
  }'

# Should return: {"received":true,"message_id":999}
```

## Quick Deployment Checklist

- [ ] Local: Commit changes
- [ ] Local: Push to remote
- [ ] AWS: Pull latest code
- [ ] AWS: Verify files updated (git log)
- [ ] AWS: Restart puma (Ctrl+C, restart in tmux)
- [ ] AWS: Restart sidekiq (Ctrl+C, restart in tmux)
- [ ] AWS: Run test_interceptor.rb
- [ ] AWS: Send test message
- [ ] AWS: Watch logs for "Message#send_to_interceptor called"
- [ ] AWS: Verify RAG server receives request
- [ ] AWS: Verify translation appears

## Summary

The code fixes are ready but need to be **deployed to AWS** and **puma/sidekiq restarted** to take effect.

After deployment, the extensive logging will show you exactly what's happening at each step.
