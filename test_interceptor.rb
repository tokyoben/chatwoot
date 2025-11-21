#!/usr/bin/env ruby
# Quick test script for Message Interceptor
# Run with: RAILS_ENV=production bundle exec ruby test_interceptor.rb

require_relative 'config/environment'

puts "=" * 80
puts "MESSAGE INTERCEPTOR TEST"
puts "=" * 80
puts

# Check environment variables
puts "1. Checking environment variables..."
url = ENV['MESSAGE_INTERCEPTOR_URL']
api_key = ENV['MESSAGE_INTERCEPTOR_API_KEY']
timeout = ENV['MESSAGE_INTERCEPTOR_TIMEOUT']

puts "   MESSAGE_INTERCEPTOR_URL: #{url || '❌ NOT SET'}"
puts "   MESSAGE_INTERCEPTOR_API_KEY: #{api_key ? "✓ SET (#{api_key[0..20]}...)" : '❌ NOT SET'}"
puts "   MESSAGE_INTERCEPTOR_TIMEOUT: #{timeout || '5 (default)'}"
puts

# Check service constants
puts "2. Checking service can read environment..."
puts "   INTERCEPTOR_BACKEND_URL: #{MessageInterceptorService::INTERCEPTOR_BACKEND_URL}"
puts "   INTERCEPTOR_TIMEOUT: #{MessageInterceptorService::INTERCEPTOR_TIMEOUT}"
puts

# Find a recent message
puts "3. Finding a recent message to test with..."
message = Message.where.not(content: nil).where.not(content: '').last
if message
  puts "   ✓ Found message #{message.id}"
  puts "   - Content: #{message.content.truncate(50)}"
  puts "   - Type: #{message.message_type}"
  puts "   - Private: #{message.private?}"
  puts "   - Activity: #{message.activity?}"
else
  puts "   ❌ No messages found in database"
  exit 1
end
puts

# Test should_intercept?
puts "4. Testing should_intercept? logic..."
service = MessageInterceptorService.new(message)
should_intercept = service.should_intercept?
puts "   should_intercept? = #{should_intercept}"
if !should_intercept
  puts "   ⚠️  Message would be skipped!"
  puts "   Reasons:"
  puts "     - content blank? #{message.content.blank?}"
  puts "     - activity? #{message.activity?}"
  puts "     - private? #{message.private?}"
  puts "     - being_replaced? #{message.being_replaced?}"
  puts "     - incoming? #{message.incoming?}"
  puts "     - outgoing? #{message.outgoing?}"
end
puts

# Test job creation (don't actually send)
puts "5. Testing job enqueue..."
begin
  # Don't actually perform, just test the job can be created
  job = MessageInterceptorJob.new
  puts "   ✓ Job class exists and can be instantiated"

  # Check if Sidekiq is available
  if defined?(Sidekiq)
    queue_size = Sidekiq::Queue.new('default').size
    puts "   ✓ Sidekiq available, default queue size: #{queue_size}"
  else
    puts "   ⚠️  Sidekiq not loaded"
  end
rescue => e
  puts "   ❌ Job test failed: #{e.message}"
end
puts

# Test actual HTTP call (if user wants)
puts "6. Test actual HTTP call to RAG server?"
puts "   This will attempt to send a test message to: #{url}"
print "   Continue? (y/N): "
response = gets.chomp.downcase

if response == 'y'
  puts
  puts "   Sending test request..."
  begin
    require 'httparty'

    test_payload = {
      message_id: message.id,
      conversation_id: message.conversation_id,
      content: message.content,
      message_type: message.message_type,
      callback_url: "#{ENV['FRONTEND_URL']}/api/v1/internal/messages/#{message.id}/interceptor_callback"
    }

    response = HTTParty.post(
      url,
      body: test_payload.to_json,
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{api_key}"
      },
      timeout: 10
    )

    puts "   ✓ Response code: #{response.code}"
    puts "   ✓ Response body: #{response.body}"

    if response.success?
      puts "   ✓✓ RAG server is accessible and responding!"
    else
      puts "   ⚠️  RAG server returned non-success code"
    end
  rescue => e
    puts "   ❌ HTTP request failed: #{e.message}"
    puts "   #{e.backtrace.first(3).join("\n   ")}"
  end
else
  puts "   Skipped HTTP test"
end
puts

# Summary
puts "=" * 80
puts "SUMMARY"
puts "=" * 80
if url && url != 'http://localhost:3001/translate' && should_intercept
  puts "✓ Configuration looks good!"
  puts
  puts "Next steps:"
  puts "1. Make sure you've deployed these code changes to AWS"
  puts "2. Restart puma: bundle exec puma -C config/puma.rb"
  puts "3. Restart sidekiq: bundle exec sidekiq -C config/sidekiq.yml"
  puts "4. Send a test message"
  puts "5. Watch logs: tail -f log/production.log | grep MessageInterceptor"
elsif !url || url == 'http://localhost:3001/translate'
  puts "❌ Environment variables not configured properly"
  puts
  puts "Set MESSAGE_INTERCEPTOR_URL in .env file"
elsif !should_intercept
  puts "⚠️  Test message would not be intercepted"
  puts
  puts "Try testing with a different message type"
end
puts "=" * 80
