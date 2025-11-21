# QUICK FIX - Message Interceptor Not Working

## The Problem
Environment variables not set → Interceptor defaults to wrong URL → Nothing happens

## The Fix (5 minutes)

### On Your AWS Server:

**1. Create/Edit .env file**
```bash
cd /path/to/chatwoot
nano .env
```

**2. Add these 4 lines (or update if they exist):**
```bash
MESSAGE_INTERCEPTOR_URL=http://localhost:3003/interceptor/translate
MESSAGE_INTERCEPTOR_API_KEY=dc45ef45b90e18bc4f80e77bf2cef19bc966350e96bdc69662586a6137045276
MESSAGE_INTERCEPTOR_TIMEOUT=10
FRONTEND_URL=https://chatwoot.casenavi.com
```
Save (Ctrl+X, Y, Enter)

**3. Restart BOTH processes in tmux**

```bash
# In tmux - go to Puma window (Ctrl+B, then window number)
Ctrl+C  # Stop puma
bundle exec puma -C config/puma.rb  # Restart

# In tmux - go to Sidekiq window
Ctrl+C  # Stop sidekiq
bundle exec sidekiq -C config/sidekiq.yml  # Restart
```

**4. Verify it worked**
```bash
# Check env var is loaded
RAILS_ENV=production bundle exec rails runner "puts ENV['MESSAGE_INTERCEPTOR_URL']"
# Should show: http://localhost:3003/interceptor/translate
```

**5. Test**
- Send a message from widget
- Watch logs: `tail -f log/production.log | grep MessageInterceptor`
- Should see "MessageInterceptor: Intercepting message..."

## That's It!

If you see logs showing the interceptor is working, translation should start happening automatically.

## Still Not Working?

Check:
1. Is Sidekiq actually running? `ps aux | grep sidekiq`
2. Is RAG server running? `ps aux | grep node | grep 3003`
3. Can Chatwoot reach RAG server? `curl http://localhost:3003/health`

For detailed troubleshooting, see: **INTERCEPTOR_TMUX_SETUP.md**
