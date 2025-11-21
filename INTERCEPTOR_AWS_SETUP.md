# Setting Up Message Interceptor on AWS

## The Problem

The interceptor isn't being called because the environment variable `MESSAGE_INTERCEPTOR_URL` is not set on your AWS server. It's currently defaulting to `http://localhost:3001/translate` which is incorrect.

## Required Environment Variables

You need to set these on your **AWS Chatwoot server**:

```bash
MESSAGE_INTERCEPTOR_URL=<URL_TO_YOUR_RAG_SERVER>
MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276
MESSAGE_INTERCEPTOR_TIMEOUT=10
FRONTEND_URL=https://chatwoot.casenavi.com
```

## Determining the RAG Server URL

**Option 1: RAG server is on the SAME AWS instance**
```bash
MESSAGE_INTERCEPTOR_URL=http://localhost:3003/interceptor/translate
```

**Option 2: RAG server is on a DIFFERENT machine**
```bash
MESSAGE_INTERCEPTOR_URL=http://<RAG_SERVER_IP>:3003/interceptor/translate
# OR if you have a domain:
MESSAGE_INTERCEPTOR_URL=https://rag.casenavi.com/interceptor/translate
```

## How to Set Environment Variables

### Method 1: Using .env file (if using dotenv)

SSH into your AWS server and:

```bash
cd /path/to/chatwoot

# Create or edit .env file
nano .env

# Add these lines:
MESSAGE_INTERCEPTOR_URL=http://localhost:3003/interceptor/translate
MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276
MESSAGE_INTERCEPTOR_TIMEOUT=10
FRONTEND_URL=https://chatwoot.casenavi.com

# Save and exit (Ctrl+X, Y, Enter)

# Restart Chatwoot
sudo systemctl restart chatwoot
# OR
sudo systemctl restart chatwoot-web
sudo systemctl restart chatwoot-worker
```

### Method 2: Using systemd environment files

If Chatwoot is running as a systemd service:

```bash
# Edit the service file
sudo nano /etc/systemd/system/chatwoot.service

# Add environment variables in the [Service] section:
[Service]
Environment="MESSAGE_INTERCEPTOR_URL=http://localhost:3003/interceptor/translate"
Environment="MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276"
Environment="MESSAGE_INTERCEPTOR_TIMEOUT=10"
Environment="FRONTEND_URL=https://chatwoot.casenavi.com"

# Save and reload
sudo systemctl daemon-reload
sudo systemctl restart chatwoot
```

### Method 3: Using /etc/environment (system-wide)

```bash
# Edit system environment
sudo nano /etc/environment

# Add at the end:
MESSAGE_INTERCEPTOR_URL="http://localhost:3003/interceptor/translate"
MESSAGE_INTERCEPTOR_API_KEY="dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276"
MESSAGE_INTERCEPTOR_TIMEOUT="10"
FRONTEND_URL="https://chatwoot.casenavi.com"

# Reboot or restart Chatwoot
sudo systemctl restart chatwoot
```

## Verification Steps

### Step 1: Check if environment variables are loaded

SSH into AWS and run:

```bash
# If using systemd:
sudo systemctl show chatwoot | grep MESSAGE_INTERCEPTOR_URL

# Or check from Rails console:
cd /path/to/chatwoot
RAILS_ENV=production bundle exec rails console
> ENV['MESSAGE_INTERCEPTOR_URL']
# Should output: http://localhost:3003/interceptor/translate (or your URL)
> exit
```

### Step 2: Check Chatwoot logs

After sending a test message, check the logs:

```bash
# Check production log
tail -f /path/to/chatwoot/log/production.log | grep MessageInterceptor

# You should see lines like:
# MessageInterceptor: Checking message 123 (type: incoming, content: 'Hello')
# MessageInterceptor: Intercepting message 123, will send to http://localhost:3003/interceptor/translate
# MessageInterceptorJob: Sending message 123 to http://localhost:3003/interceptor/translate
```

### Step 3: Check Sidekiq logs

```bash
# Check Sidekiq log
tail -f /path/to/chatwoot/log/sidekiq.log | grep MessageInterceptor
```

### Step 4: Test RAG server is accessible

From your AWS Chatwoot server:

```bash
# Test connectivity to RAG server
curl -X POST http://localhost:3003/interceptor/translate \
  -H "Content-Type: application/json" \
  -d '{
    "message_id": 999,
    "content": "Test message",
    "message_type": "incoming",
    "callback_url": "https://chatwoot.casenavi.com/api/v1/internal/messages/999/interceptor_callback"
  }'

# Should return: {"received":true,"message_id":999}
```

## Troubleshooting

### Issue: "Nothing in logs about MessageInterceptor"

**Cause:** Environment variables not loaded, or Sidekiq not restarted

**Solution:**
```bash
# Restart ALL Chatwoot processes
sudo systemctl restart chatwoot-web
sudo systemctl restart chatwoot-worker  # This is important for Sidekiq
```

### Issue: "MessageInterceptor: Skipping message (should_intercept=false)"

**Possible causes:**
- Message is a private note (`private=true`)
- Message is an activity message (`activity=true`)
- Message content is blank

**Solution:** Only regular incoming/outgoing messages are intercepted. This is normal.

### Issue: "MessageInterceptorJob: Failed... Connection refused"

**Cause:** RAG server not running or URL is wrong

**Check:**
1. Is RAG server running? `ps aux | grep node | grep 3003`
2. Can Chatwoot reach it? Use the curl test above
3. Is the URL correct in environment variable?

### Issue: "Logs show URL is http://localhost:3001/translate"

**Cause:** Environment variable not set, using default

**Solution:** Set `MESSAGE_INTERCEPTOR_URL` and restart Chatwoot processes

## Quick Diagnostic Commands

Run these on your AWS server:

```bash
# 1. Check if env var is set
cd /path/to/chatwoot
RAILS_ENV=production bundle exec rails runner "puts ENV['MESSAGE_INTERCEPTOR_URL']"

# 2. Check if interceptor service can access it
RAILS_ENV=production bundle exec rails runner "puts MessageInterceptorService::INTERCEPTOR_BACKEND_URL"

# 3. Check last 50 messages for interception attempts
tail -50 log/production.log | grep MessageInterceptor

# 4. Check if Sidekiq is running
ps aux | grep sidekiq

# 5. Check if RAG server is running
curl http://localhost:3003/health
```

## After Configuration

Once environment variables are set and Chatwoot is restarted:

1. **Send a test message** from the widget
2. **Check Chatwoot logs** for "MessageInterceptor: Intercepting message"
3. **Check RAG server logs** for "Interceptor received message"
4. **Check widget** - should show translated content

## Important Notes

- **Sidekiq must be restarted** for job changes to take effect
- **Both web and worker processes** need the environment variables
- **RAG server must be accessible** from the Chatwoot server
- **Port 3003** must be open if RAG server is on a different machine
- **HTTPS/SSL** may be required if using a domain name

## Next Steps

1. Set environment variables using one of the methods above
2. Restart Chatwoot (web + worker/sidekiq)
3. Send test message
4. Check logs for "MessageInterceptor" entries
5. If issues persist, run diagnostic commands and share output
