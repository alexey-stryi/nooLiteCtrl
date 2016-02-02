require 'sinatra'
require 'sinatra/cross_origin'
require 'json'
require 'redis'
require './app/nooLite'

set :allow_methods, [:get, :post, :put, :delete, :options, :link, :unlink]
set :allow_headers, ['*', 'X-Requested-With', 'X-HTTP-Method-Override', 'Content-Type', 'Cache-Control', 'Accept', 'AUTHORIZATION']
set :allow_credentials, true

@db_host = '127.0.0.1'
@db_port = 6379
@db_name = 'bulbs'

MAX_CHANNEL_COUNT = 32

redis = Redis.new(:host => @db_host, :port => @db_port, :db => 1)

###############################################################################
###############################################################################
###############################################################################

configure do
  mime_type :jsonp, 'application/javascript'
  enable :cross_origin
end

###############################################################################

helpers do
  def get_id(r)
    return r.incr('bulb_id')
  end

###############################################################################

  def get_available_channel(r)
    list     = Array.new(MAX_CHANNEL_COUNT)
    channels = r.hvals(@db_name).map{|h| d = JSON.parse(h); d['channel'] }

    channels.each{|ch| list[ch] = 1 unless ch.nil?}

    return list.index{|ch| ch.nil?}    # get index of first nil item
  end

###############################################################################

  def with_bulb(data, &block)
    return {:success => false, :reason => :not_found}.to_json if data.nil?

    begin
      bulb = JSON.parse(data)

      block.call(bulb)

      return {:success => true, :data => [bulb]}.to_json
    rescue => e
      return [422, {:success => false, :reason => :error, :message => e.message}.to_json]
    end
  end

###############################################################################

  def h(text)
    Rack::Utils.escape_html(text)
  end

###############################################################################
end

before do
  if !params['data'].nil?
    begin
      data = JSON.parse(params['data'])
      data.each{ |key, value|
        params[key] = value if params[key].nil?
      }
    end
  end
end

###############################################################################
###############################################################################
###############################################################################

options "*" do
  200
end

###############################################################################

get '/locations/' do
  content_type :json

  begin
    index = {}
    data = []

    redis.hvals(@db_name).each{|json|
      bulb     = JSON.parse(json)
      location = bulb['location']

      if index[location].nil?
        index[location] = data.length
        data <<  { :name => location, :bulbs_list_url => "/location/#{location}/bulbs", :bulbs => [bulb]}
      else
        item = data[index[location]]
        item[:bulbs] << bulb
      end
    }

    {:data => data}.to_json
  end
end

###############################################################################

get '/location/:location/bulbs' do
  content_type :json

  begin
    data = []

    redis.hvals(@db_name).each{|value|
      bulb = JSON.parse(value)

      data << bulb if bulb['location'] == params['location']
    }
  end

  {:data => data}.to_json
end

###############################################################################

get '/bulbs' do
  content_type :json

  data = []

  redis.hvals(@db_name).each{|json|
      data << JSON.parse(json)
  }

  {:success => true, :data => data}.to_json
end

###############################################################################

post '/bulbs' do
  content_type :json

  bulb_id = get_id(redis)
  channel = get_available_channel(redis)

  return  {:success => false, :reason => :no_channel_available}.to_json if channel.nil?

  bulb    = {
    :id         => bulb_id,
    :channel    => channel,
    :name       => params['name'],
    :location   => params['location'],
    :type       => params['type'],
    :binded     => 0,
    :state      => 'off',
    :color      => 'FFFFFF',
    :brightness => 100
  }

  begin
    redis.hset(@db_name, bulb_id, bulb.to_json)
  rescue => e
    return {:success => false, :reason => :error, :message => e.message}.to_json
  end

  {:success => true, :data => [bulb]}.to_json
end

###############################################################################

get '/bulbs/:id' do
  content_type :json

  bulb = JSON.parse(redis.hget(@db_name, params['id']))

  if bulb
    {:success => true, :data => [bulb]}.to_json
  else
    {:success => false, :reason => :not_found}.to_json
  end
end

###############################################################################

put '/bulbs/:id' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    bulb['name']     = params['name']     unless params['name'].nil?
    bulb['type']     = params['type']     unless params['type'].nil?
    bulb['location'] = params['location'] unless params['location'].nil?

    redis.hset(@db_name, bulb['id'], bulb.to_json)
  end
end

###############################################################################

put '/bulbs/:id/state/:state' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    bulb['state'] = params['state'] if ['on', 'off'].include?(params['state'])

    case bulb['state']
      when 'on'  then NooLite.switch_on(bulb['channel'])
      when 'off' then NooLite.switch_off(bulb['channel'])
    end

    redis.hset(@db_name, bulb['id'], bulb.to_json)
  end
end

###############################################################################

put '/bulbs/:id/toggle' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    bulb['state'] =  bulb['state'] === 'on' ? 'off' : 'on'

    NooLite.toggle(bulb['channel'])
    redis.hset(@db_name, bulb['id'], bulb.to_json)
  end
end

###############################################################################

put '/bulbs/:id/brightness/:brightness' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    brightness = params['brightness'].to_i

    if (0..100).include?(brightness)
      bulb['brightness'] = brightness

      redis.hset(@db_name, bulb['id'], bulb.to_json)

      NooLite.set_brightness(bulb['channel'], bulb['brightness'])
    end
  end
end

###############################################################################

put '/bulbs/:id/color/:color' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    color = params['color']

    if color =~ /\h{6}/   # a valid HEX color value
      bulb['color'] = color

      redis.hset(@db_name, bulb['id'], bulb.to_json)

      NooLite.set_color(bulb['channel'], bulb['color'])
    end
  end
end

###############################################################################

put '/bulbs/:id/command/:command' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    case params['command']
      when 'roll'         then NooLite.start_smooth_color_roll(bulb['channel'])
      when 'stop'         then NooLite.stop_smooth_roll(bulb['channel'])
      when 'switch_color' then NooLite.switch_color(bulb['channel'])
      when 'switch_mode'  then NooLite.switch_mode(bulb['channel'])
      when 'switch_speed' then NooLite.switch_speed(bulb['channel'])
    end
  end
end

###############################################################################

link '/bulbs/:id/' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    bulb['binded'] = 1

    NooLite.bind(bulb['channel'])
    redis.hset(@db_name, bulb['id'], bulb.to_json)
  end
end

###############################################################################

unlink '/bulbs/:id/' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    bulb['binded'] = 0

    NooLite.unbind(bulb['channel'])
    redis.hset(@db_name, bulb['id'], bulb.to_json)
  end
end

###############################################################################

delete '/bulbs/all' do
  content_type :json

  if redis.del(@db_name)
    redis.del('bulb_id')
    {:success => true}.to_json
  else
    {:success => false, :reason => :not_found}.to_json
  end
end

###############################################################################

delete '/bulbs/:id' do
  content_type :json

  if redis.hdel(@db_name, params['id'])
    {:success => true}.to_json
  else
    {:success => false, :reason => :not_found}.to_json
  end
end
