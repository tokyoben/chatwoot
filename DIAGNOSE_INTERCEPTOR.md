# Diagnosing Why Interceptor Isn't Working

## Step 1: Check if code changes are deployed

On AWS, run:
```bash
cd /path/to/chatwoot

# Check if the Message model has the new code
grep -A 5 "Message#send_to_interceptor called" app/models/message.rb

# Should show:
#   Rails.logger.info("Message#send_to_interceptor called for message #{id}")
```

**If nothing shows up:** Code not deployed. Need to `git pull` or copy files.

## Step 2: Verify processes are running with new code

```bash
# Check Puma is running in development
ps aux | grep puma | grep chatwoot

# Check Sidekiq is running in development
ps aux | grep sidekiq | grep chatwoot

# Check when processes started (should be recent)
ps aux | grep -E "puma|sidekiq" | grep chatwoot
```

**If processes show old timestamps:** Need to restart them.

## Step 3: Check environment variables are loaded

```bash
cd /path/to/chatwoot

# Check if Rails can see the env var
RAILS_ENV=development bundle exec rails runner "puts ENV['MESSAGE_INTERCEPTOR_URL']"

# Should show: https://ragwtwhk6453.jp.ngrok.io/interceptor/translate
# NOT: http://localhost:3001/translate
```

**If shows wrong URL or nothing:** .env file not loaded or processes not restarted.

## Step 4: Check if send_to_interceptor is even being called

```bash
# Watch ALL logs, not just MessageInterceptor
tail -f log/development.log

# Then send a message and look for ANY of these:
# - "Message#send_to_interceptor called"
# - "MessageInterceptor: Checking message"
# - Any errors mentioning interceptor
```

**If you see NOTHING:** The method isn't being called at all.

## Step 5: Check database directly

```bash
RAILS_ENV=development bundle exec rails console

# In console:
> m = Message.last
> puts m.id
> puts m.content
> puts m.message_type
> puts m.private?
> puts m.activity?

# Check if the method exists
> m.respond_to?(:send_to_interceptor)
# Should return: true

# Try calling it manually
> m.send_to_interceptor
# Should see logs or error
```

## Step 6: Test the service directly

```bash
RAILS_ENV=development bundle exec rails console

# Get last message
> m = Message.last
> service = MessageInterceptorService.new(m)
> service.should_intercept?
# Should return true or false

# If true, try to send
> service.send_to_interceptor
# Watch logs
```

## Quick Diagnostic Script

Run this on AWS:
```bash
cd /path/to/chatwoot
RAILS_ENV=development bundle exec ruby test_interceptor.rb
```

This will tell you exactly what's wrong.

## Most Likely Issues

### Issue 1: Code not on AWS server
```bash
# Pull latest code
git pull origin main

# Restart everything
pkill -f "puma.*chatwoot"
pkill -f "sidekiq.*chatwoot"
RAILS_ENV=development bundle exec puma -C config/puma.rb  # tmux window 1
RAILS_ENV=development bundle exec sidekiq -C config/sidekiq.yml  # tmux window 2
```

### Issue 2: Sidekiq not running
```bash
ps aux | grep sidekiq
# If nothing, start it:
RAILS_ENV=development bundle exec sidekiq -C config/sidekiq.yml
```

### Issue 3: Wrong RAILS_ENV
If you started puma/sidekiq without `RAILS_ENV=development`, they might be running in production mode without assets.

### Issue 4: Message type doesn't match
The interceptor only processes:
- `incoming` messages (from user to agent)
- `outgoing` messages (from agent to user)

NOT:
- `activity` messages
- `private` messages (notes)

Try sending a regular message from the widget, not a private note.
