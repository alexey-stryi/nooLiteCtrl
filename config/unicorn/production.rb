require "redis"

# Nginx setup with subdirectories
#ENV['RAILS_RELATIVE_URL_ROOT'] = '/trek'

# Set your full path to application.
app_path = "/home/admin/webapps/nooLiteCtrl/current"

worker_processes 1
preload_app true
timeout 180
listen "#{app_path}/tmp/sockets/unicorn.trek.sock"

# User to run unicorm
user 'admin', 'admin' 

# Fill path to your app
working_directory app_path

# Should be 'production' by default, otherwise use other env 
# rails_env = ENV['RAILS_ENV'] || 'production'

# Log everything to one file
stderr_path "#{app_path}/log/unicorn.log"
stdout_path "#{app_path}/log/unicorn.log"

# Set master PID location
pid "#{app_path}/tmp/pids/unicorn.pid"


after_fork do |server, worker|
  Redis.current.disconnect!
end