require 'goliath'
require 'redis'
require 'json'

module Options
  def self.redis
    options = {driver: :synchrony}
    if ENV['REDISTOGO_URL']
      uri = URI.parse(ENV['REDISTOGO_URL'])
      options.merge!({host: uri.host, port: uri.port, password: uri.password})
    end
    options
  end
end

class Subscribe < Goliath::API
  def response(env)
    EM.synchrony do
      @redis = Redis.new(Options::redis)
      channel = env["REQUEST_PATH"].sub(/^\/subscribe\//, '')
      @redis.subscribe(channel) do |on|
        on.message do |channel, message|
          @message = message
          p payload
          env.stream_send(payload)
        end
      end
    end
    EventMachine.add_periodic_timer(30) do
      env.stream_send("\r\n\n")
    end
    streaming_response(200, { 'Content-Type' => "text/event-stream" })
  end

  def on_close(env)
    @redis.disconnect
  end

  def payload
    "id: #{Time.now}\n" +
    "data: #{@message}" +
    "\r\n\n"
  end
end

class Receive < Goliath::API
  @@redis = Redis.new(Options::redis)

  def response(env)
    channel = env["REQUEST_PATH"][1..-1]
    @@redis.publish(channel, params.to_json)
    [ 200, { }, [ ] ]
  end
end

class Server < Goliath::API
  map "/" do
    run Rack::File.new(File.join(File.dirname(__FILE__), 'public', 'index.html'))
  end

  map /^\/subscribe.*/ do
    run Subscribe.new
  end

  map /.*/ do
    run Receive.new
  end
end
