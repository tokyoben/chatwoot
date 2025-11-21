# Message Interceptor Setup for Tmux/Manual Deployment

## Your Current Setup

You're running:
- **Puma:** `bundle exec puma -C config/puma.rb` (in one tmux window)
- **Sidekiq:** `bundle exec sidekiq -C config/sidekiq.yml` (in another tmux window)

## The Problem

Environment variables must be set BEFORE starting puma and sidekiq. They won't pick up changes if you set them after the processes are already running.

## Solution: Use .env File

### Step 1: Create .env file in Chatwoot directory

SSH to your AWS server and:

```bash
cd /path/to/chatwoot

# Create .env file if it doesn't exist
nano .env
```

### Step 2: Add these lines to .env

```bash
# Message Interceptor Configuration
MESSAGE_INTERCEPTOR_URL=http://localhost:3003/interceptor/translate
MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276
MESSAGE_INTERCEPTOR_TIMEOUT=10
FRONTEND_URL=https://chatwoot.casenavi.com

# (Keep your other existing .env variables below)
```

**Save and exit** (Ctrl+X, Y, Enter)

### Step 3: Install dotenv gem (if not already installed)

Check if you have dotenv:

```bash
bundle list | grep dotenv
```

If not installed, add to Gemfile:

```ruby
gem 'dotenv-rails', groups: [:development, :production]
```

Then:
```bash
bundle install
```

### Step 4: Restart Puma and Sidekiq

You need to **restart BOTH** processes to load the new environment variables.

#### Stop Current Processes

In your tmux:

```bash
# In Puma window (Ctrl+B, then window number)
Ctrl+C  # Stop puma

# In Sidekiq window
Ctrl+C  # Stop sidekiq
```

#### Start With Environment Variables

**Option A: If dotenv is installed (recommended)**

The .env file will be automatically loaded:

```bash
# Start Puma (in one tmux window)
cd /path/to/chatwoot
bundle exec puma -C config/puma.rb

# Start Sidekiq (in another tmux window)
cd /path/to/chatwoot
bundle exec sidekiq -C config/sidekiq.yml
```

**Option B: Manually export variables (if no dotenv)**

```bash
# Export variables first
export MESSAGE_INTERCEPTOR_URL=http://localhost:3003/interceptor/translate
export MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276
export MESSAGE_INTERCEPTOR_TIMEOUT=10
export FRONTEND_URL=https://chatwoot.casenavi.com

# Then start processes
bundle exec puma -C config/puma.rb  # in one window
bundle exec sidekiq -C config/sidekiq.yml  # in another window
```

**Option C: Use dotenv-rails explicitly**

```bash
# Start with explicit env loading
bundle exec dotenv -f .env puma -C config/puma.rb
bundle exec dotenv -f .env sidekiq -C config/sidekiq.yml
```

### Step 5: Verify Environment Variables

After restarting, verify the variables are loaded:

```bash
cd /path/to/chatwoot

# Check if Rails can see the variable
RAILS_ENV=production bundle exec rails runner "puts ENV['MESSAGE_INTERCEPTOR_URL']"

# Should output: http://localhost:3003/interceptor/translate
# NOT: http://localhost:3001/translate (that's the default)
```

### Step 6: Check Processes are Running

```bash
# Check Puma
ps aux | grep puma | grep chatwoot

# Check Sidekiq (important!)
ps aux | grep sidekiq | grep chatwoot
```

### Step 7: Send Test Message

1. Send a message from the widget or dashboard
2. Watch the logs in real-time:

```bash
# In a new tmux window
cd /path/to/chatwoot
tail -f log/production.log | grep MessageInterceptor
```

You should see:
```
MessageInterceptor: Checking message 123 (type: incoming, content: 'こんにちは')
MessageInterceptor: Intercepting message 123, will send to http://localhost:3003/interceptor/translate
MessageInterceptorJob: Sending message 123 to http://localhost:3003/interceptor/translate
MessageInterceptorJob: Successfully sent message 123 to interceptor
```

## Tmux Best Practices

### Create a Startup Script

To make this easier, create a startup script:

```bash
cd /path/to/chatwoot
nano start_chatwoot.sh
```

Add:
```bash
#!/bin/bash
cd /path/to/chatwoot

# Load environment variables
export MESSAGE_INTERCEPTOR_URL=http://localhost:3003/interceptor/translate
export MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276
export MESSAGE_INTERCEPTOR_TIMEOUT=10
export FRONTEND_URL=https://chatwoot.casenavi.com

# Check which process to start
if [ "$1" == "web" ]; then
  echo "Starting Puma..."
  bundle exec puma -C config/puma.rb
elif [ "$1" == "worker" ]; then
  echo "Starting Sidekiq..."
  bundle exec sidekiq -C config/sidekiq.yml
else
  echo "Usage: ./start_chatwoot.sh [web|worker]"
fi
```

Make it executable:
```bash
chmod +x start_chatwoot.sh
```

Then in tmux:
```bash
# Window 1
./start_chatwoot.sh web

# Window 2
./start_chatwoot.sh worker
```

### Tmux Session Script

Create an automated tmux setup:

```bash
nano setup_tmux.sh
```

Add:
```bash
#!/bin/bash
SESSION="chatwoot"

# Create new tmux session
tmux new-session -d -s $SESSION

# Window 0: Puma
tmux rename-window -t $SESSION:0 'puma'
tmux send-keys -t $SESSION:0 'cd /path/to/chatwoot' C-m
tmux send-keys -t $SESSION:0 './start_chatwoot.sh web' C-m

# Window 1: Sidekiq
tmux new-window -t $SESSION:1 -n 'sidekiq'
tmux send-keys -t $SESSION:1 'cd /path/to/chatwoot' C-m
tmux send-keys -t $SESSION:1 './start_chatwoot.sh worker' C-m

# Window 2: Logs
tmux new-window -t $SESSION:2 -n 'logs'
tmux send-keys -t $SESSION:2 'cd /path/to/chatwoot' C-m
tmux send-keys -t $SESSION:2 'tail -f log/production.log' C-m

# Attach to session
tmux attach-session -t $SESSION
```

Make it executable:
```bash
chmod +x setup_tmux.sh
```

Use it:
```bash
./setup_tmux.sh
```

## Troubleshooting

### Issue: "Still seeing default URL http://localhost:3001/translate"

**Cause:** Environment variables not loaded when processes started

**Solution:**
1. Stop puma and sidekiq completely
2. Verify .env file exists and has correct values
3. Start processes again with explicit env loading

### Issue: "Variables set but still not working"

**Cause:** Processes not restarted after setting variables

**Solution:**
```bash
# Kill all chatwoot processes
pkill -f "puma.*chatwoot"
pkill -f "sidekiq.*chatwoot"

# Start again
./start_chatwoot.sh web    # in tmux window 1
./start_chatwoot.sh worker # in tmux window 2
```

### Issue: "Sidekiq not picking up jobs"

**Cause:** Sidekiq not running or crashed

**Check:**
```bash
ps aux | grep sidekiq | grep chatwoot
```

If not running:
```bash
# Check sidekiq log for errors
tail -50 log/sidekiq.log

# Restart
bundle exec sidekiq -C config/sidekiq.yml
```

### Issue: "RAG server not accessible"

**Test connectivity:**
```bash
curl -X POST http://localhost:3003/interceptor/translate \
  -H "Content-Type: application/json" \
  -d '{"message_id":999,"content":"test","callback_url":"http://test"}'

# Should return: {"received":true,"message_id":999}
```

If fails:
- Is RAG server running? `ps aux | grep node | grep 3003`
- Check RAG server logs
- Try: `netstat -tlnp | grep 3003`

## Quick Commands Reference

```bash
# Check if env var is loaded
RAILS_ENV=production bundle exec rails runner "puts ENV['MESSAGE_INTERCEPTOR_URL']"

# Watch logs
tail -f log/production.log | grep MessageInterceptor
tail -f log/sidekiq.log

# List tmux sessions
tmux ls

# Attach to session
tmux attach -t chatwoot

# Navigate tmux
Ctrl+B then 0/1/2  # Switch windows
Ctrl+B then d      # Detach
Ctrl+B then [      # Scroll mode (q to exit)

# Check processes
ps aux | grep -E "puma|sidekiq" | grep chatwoot

# Kill processes
pkill -f "puma.*chatwoot"
pkill -f "sidekiq.*chatwoot"
```

## Summary Checklist

- [ ] Create .env file with MESSAGE_INTERCEPTOR_URL and other variables
- [ ] Stop both Puma and Sidekiq (Ctrl+C in tmux windows)
- [ ] Start Puma with environment variables loaded
- [ ] Start Sidekiq with environment variables loaded
- [ ] Verify env vars: `rails runner "puts ENV['MESSAGE_INTERCEPTOR_URL']"`
- [ ] Send test message
- [ ] Check logs: `tail -f log/production.log | grep MessageInterceptor`
- [ ] Verify RAG server receives request
- [ ] Check translation appears correctly

## Important Notes

- **Both** Puma AND Sidekiq need the environment variables
- **Sidekiq is critical** - it's what executes the MessageInterceptorJob
- **Restart required** - changing .env requires restart of both processes
- **Tmux detach** - Ctrl+B then D to detach without stopping processes
