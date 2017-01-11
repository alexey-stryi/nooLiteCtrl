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

Encoding.default_external = "utf-8"

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

  def get_available_channel(r, ignore = nil)
    list     = Array.new(MAX_CHANNEL_COUNT)
    channels = r.hvals(@db_name).map{|h| d = JSON.parse(h); (d['channels'] or d['channel'])}.flatten!

    channels.each{|ch| list[ch] = 1 unless ch.nil?} unless channels.nil?

    list[ignore] = 1 unless ignore.nil?

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

  def with_bulbs(data, &block)
    return {:success => false, :reason => :not_found}.to_json if data.nil?

    begin
      result = []

      data.each{|d|
        bulb = JSON.parse(d)

        block.call(bulb)

        result << bulb
      }

      return {:success => true, :data => result}.to_json
    rescue => e
      return [422, {:success => false, :reason => :error, :message => e.message}.to_json]
    end
  end

###############################################################################

  def h(text)
    Rack::Utils.escape_html(text)
  end

###############################################################################

  def to_json(obj)
    return params['indent'].nil? ? obj.to_json : JSON.pretty_generate(obj, {:indent => ' ' * params['indent'].to_i})
  end

end

before do
  # fixing missing POST and PUT params
  if (request.request_method == "POST" or request.request_method == "PUT") and request.content_type=="application/json"
    body_parameters = request.body.read

    parsed = body_parameters && body_parameters.length >= 2 ? JSON.parse(body_parameters) : {}
    params.merge!(parsed)
  end


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

get '/locations' do
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

    data.sort!{|a, b| a[:name] <=> b[:name] }

    to_json({:success => true, :data => data})
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

  to_json({:success => true, :data => data})
end

###############################################################################

put '/location/:location/state/off' do
  content_type :json

  data = []
  begin
    redis.hvals(@db_name).each{|value|
      bulb = JSON.parse(value)
      data << value if bulb['location'] == params['location']
    }
  end

  with_bulbs(data) do |bulb|
    bulb['state'] = 'off'
    NooLite.switch_off(bulb['channel'], false)
    redis.hset(@db_name, bulb['id'], bulb.to_json)
  end
end

###############################################################################

get '/bulbs' do
  content_type :json

  data = []

  redis.hvals(@db_name).each{|json|
      data << JSON.parse(json)
  }

  to_json({:success => true, :data => data})
end

###############################################################################

post '/bulbs' do
  content_type :json

  bulb_id = get_id(redis)
  channel = get_available_channel(redis)

  return  {:success => false, :reason => :no_channel_available}.to_json if channel.nil?

  bulb = {
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

  bulb_data = redis.hget(@db_name, params['id'])
  bulb = JSON.parse(bulb_data) if bulb_data

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

    channel = bulb['channel']
    smooth  = !params['smooth'].nil? && params['smooth'] == 'true'

    case bulb['state']
      when 'on'  then NooLite.switch_on(channel, smooth)
      when 'off' then NooLite.switch_off(channel, smooth)
    end

    redis.hset(@db_name, bulb['id'], bulb.to_json)
  end
end

###############################################################################

put '/bulbs/:id/toggle' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    bulb['state'] =  bulb['state'] === 'on' ? 'off' : 'on'

    channel = bulb['channel']
    smooth  = !params['smooth'].nil? && params['smooth'] == 'true'

    NooLite.toggle(channel, smooth)
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

      NooLite.set_brightness(bulb['channel'], brightness)
    end
  end
end

###############################################################################

put '/bulbs/:id/color/:color' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    color   = params['color']

    if color =~ /\h{6}/   # a valid HEX color value
      bulb['color'] = color

      redis.hset(@db_name, bulb['id'], bulb.to_json)

      NooLite.set_color(bulb['channel'], color)
    end
  end
end

###############################################################################

put '/bulbs/:id/command/:command' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    channel = bulb['channel']

    case params['command']
      when 'start_color_play'     then NooLite.start_color_play(channel)
      when 'stop_color_play'      then NooLite.stop_color_play(channel)
      when 'switch_to_next_color' then NooLite.switch_to_next_color(channel)
      when 'change_switch_mode'   then NooLite.change_switch_mode(channel)
      when 'change_switch_speed'  then NooLite.change_switch_speed(channel)
    end
  end
end

###############################################################################
###    BIND    ###
put '/bulbs/:id/bind/:channel' do
  content_type :json

  with_bulb(redis.hget(@db_name, params['id'])) do |bulb|
    bulb['binded'] = 1
    NooLite.bind(bulb['channel'])

    redis.hset(@db_name, bulb['id'], bulb.to_json)
  end
end

###############################################################################
###    UNBIND    ###
put '/bulbs/:id/unbind/:channel' do
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

