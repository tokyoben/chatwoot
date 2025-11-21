# Starting Chatwoot in Development Mode with Interceptor

## Quick Start

**On your AWS server, in tmux:**

### Window 1: Puma (Rails Server)
```bash
cd /path/to/chatwoot
RAILS_ENV=development bundle exec puma -C config/puma.rb
```

### Window 2: Webpack Dev Server
```bash
cd /path/to/chatwoot
./bin/webpack-dev-server
```

### Window 3: Sidekiq (Background Jobs)
```bash
cd /path/to/chatwoot
RAILS_ENV=development bundle exec sidekiq -C config/sidekiq.yml
```

### Window 4: Watch Interceptor Logs
```bash
cd /path/to/chatwoot
tail -f log/development.log | grep MessageInterceptor
```

## Verify Environment Variables

Make sure these are in your `.env` file:
```bash
MESSAGE_INTERCEPTOR_URL=https://ragwtwhk6453.jp.ngrok.io/interceptor/translate
MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276
MESSAGE_INTERCEPTOR_TIMEOUT=5
```

## Test the Interceptor

1. **Send a message** from the widget or dashboard
2. **Watch Window 4** - you should see:

```
Message#send_to_interceptor called for message 123
MessageInterceptor: Checking message 123 (type: incoming, content: 'こんにちは')
MessageInterceptor: Intercepting message 123, will send to https://ragwtwhk6453.jp.ngrok.io/interceptor/translate
MessageInterceptorJob: Sending message 123 to https://ragwtwhk6453.jp.ngrok.io/interceptor/translate
MessageInterceptorJob: Successfully sent message 123 to interceptor
```

3. **Check RAG server** - should receive the request
4. **Check the UI** - message should be translated

## Tmux Navigation

- **Switch windows:** `Ctrl+B` then `0`, `1`, `2`, `3`
- **Detach:** `Ctrl+B` then `D`
- **Reattach:** `tmux attach`
- **List sessions:** `tmux ls`

## Stopping Everything

In each tmux window:
```bash
Ctrl+C  # Stop the process
```

## Common Issues

### "Webpack dev server already running"
```bash
# Kill existing webpack
pkill -f webpack-dev-server
# Start again
./bin/webpack-dev-server
```

### "Port already in use"
```bash
# Kill puma
pkill -f "puma.*chatwoot"
# Start again
RAILS_ENV=development bundle exec puma -C config/puma.rb
```

### "No interceptor logs appearing"
Check:
1. Is Sidekiq running? `ps aux | grep sidekiq`
2. Are env vars set? `rails runner "puts ENV['MESSAGE_INTERCEPTOR_URL']"`
3. Is RAG server running and accessible?

## Quick Restart

```bash
# Kill all processes
pkill -f "puma.*chatwoot"
pkill -f "sidekiq.*chatwoot"
pkill -f webpack-dev-server

# Start again (in tmux windows)
# Window 1:
RAILS_ENV=development bundle exec puma -C config/puma.rb

# Window 2:
./bin/webpack-dev-server

# Window 3:
RAILS_ENV=development bundle exec sidekiq -C config/sidekiq.yml
```

## Success Indicators

✅ Puma started without errors
✅ Webpack dev server compiling assets
✅ Sidekiq processing jobs
✅ Website loads correctly
✅ Logs show "MessageInterceptor" entries when sending messages
✅ RAG server receives translation requests
✅ Messages are translated in UI
