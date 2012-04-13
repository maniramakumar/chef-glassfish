#
# Copyright Peter Donald
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

def mq_config_settings(resource)
  configs = {}
  configs["imq.log.timezone"] = node["tz"] || "GMT"
  configs["imq.log.file.output"] = "ERROR|WARNING"

  configs.merge!(resource.config)

  bridges = []
  services = []

  configs["imq.portmapper.port"] = resource.port

  if resource.admin_port
    services << "admin"
    configs["imq.admin.tcp.port"] = resource.admin_port
  end

  if resource.jms_port
    services << "jms"
    configs["imq.jms.tcp.port"] = resource.jms_port
  end

  if resource.stomp_port
    bridges << "stomp"
    configs["imq.bridge.stomp.tcp.enabled"] = "true"
    configs["imq.bridge.stomp.tcp.port"] = resource.stomp_port
  end

  if services.size > 0
    configs["imq.service.activelist"] = services.join(',')
  end

  configs["imq.bridge.admin.user"] = resource.admin_user
  user = resource.users[resource.admin_user]
  raise "Missing user details for admin user '#{resource.admin_user}'" unless user
  configs["imq.bridge.admin.password"] = user[:password]
  configs["imq.imqcmd.password"] = user[:password]

  if bridges.size > 0
    configs["imq.bridge.enabled"] = "true"
    configs["imq.bridge.activelist"] = bridges.join(',')
  end

  configs
end

action :create do
  requires_authbind = false
  requires_authbind ||= new_resource.port < 1024
  requires_authbind ||= new_resource.admin_port < 1024
  requires_authbind ||= new_resource.jms_port < 1024
  requires_authbind ||= new_resource.jmx_port < 1024
  requires_authbind ||= new_resource.stomp_port < 1024

  instance_dir = "#{new_resource.var_home}/instances/#{new_resource.instance}"

  directory new_resource.var_home do
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    mode 0700
  end

  directory "#{new_resource.var_home}/instances" do
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    mode "0700"
  end

  directory instance_dir do
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    mode "0700"
  end

  directory "#{instance_dir}/etc" do
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    mode "0700"
  end

  directory "#{instance_dir}/log" do
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    mode "0700"
  end

  # Not sure why this is required... but something runs service as root which created this file as root owned
  file "#{instance_dir}/log/log.txt" do
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    mode "0700"
    action :touch
  end

  directory "#{instance_dir}/props" do
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    mode "0700"
  end

  vm_args = []
  vm_args << "-Xmx#{new_resource.max_memory}m"
  vm_args << "-Xss#{new_resource.max_stack_size}k"
  vm_args << "-Djava.util.logging.config.file=#{instance_dir}/etc/logging.properties"
  if new_resource.jmx_port
    vm_args << "-Dcom.sun.management.jmxremote"
    vm_args << "-Dcom.sun.management.jmxremote.port=#{new_resource.jmx_port}"
    vm_args << "-Dcom.sun.management.jmxremote.access.file=#{instance_dir}/etc/jmxremote.access"
    vm_args << "-Dcom.sun.management.jmxremote.password.file=#{instance_dir}/etc/jmxremote.password"
    vm_args << "-Dcom.sun.management.jmxremote.ssl=false"
  end

  template "/etc/init/omq-#{new_resource.instance}.conf" do
    source "omq-upstart.conf.erb"
    mode "0644"
    cookbook 'glassfish'

    listen_ports = [new_resource.port]
    listen_ports << new_resource.jmx_port if new_resource.jmx_port
    listen_ports << new_resource.admin_port if new_resource.admin_port
    listen_ports << new_resource.jms_port if new_resource.jms_port
    listen_ports << new_resource.stomp_port if new_resource.stomp_port

    variables(:resource => new_resource,
              :authbind => requires_authbind,
              :listen_ports => listen_ports,
              :vmargs => vm_args.join(" "))
  end

  if new_resource.port < 1024
    authbind_port "AuthBind GlassFish OpenMQ Port #{new_resource.port}" do
      port new_resource.port
      user node[:glassfish][:user]
    end
  end

  if new_resource.jmx_port && new_resource.jmx_port < 1024
    authbind_port "AuthBind GlassFish OpenMQ JMX Port #{new_resource.jmx_port}" do
      port new_resource.jmx_port
      user node[:glassfish][:user]
    end
  end

  if new_resource.admin_port && new_resource.admin_port < 1024
    authbind_port "AuthBind GlassFish OpenMQ Admin Port #{new_resource.admin_port}" do
      port new_resource.admin_port
      user node[:glassfish][:user]
    end
  end

  if new_resource.jms_port && new_resource.jms_port < 1024
    authbind_port "AuthBind GlassFish OpenMQ JMS Port #{new_resource.jms_port}" do
      port new_resource.jms_port
      user node[:glassfish][:user]
    end
  end

  if new_resource.stomp_port && new_resource.stomp_port < 1024
    authbind_port "AuthBind GlassFish OpenMQ Stomp Port #{new_resource.stomp_port}" do
      port new_resource.stomp_port
      user node[:glassfish][:user]
    end
  end

  service "omq-#{new_resource.instance}" do
    provider Chef::Provider::Service::Upstart
    supports :start => true, :restart => true, :stop => true, :status => true
    action [:enable, :start]
  end

  if new_resource.jmx_port
    admins = {}
    search(:users, "groups:#{new_resource.admin_group} AND jmx_password:*") do |u|
      admins[u['id']] = u['jmx_password']
    end
    monitors = {}
    search(:users, "groups:#{new_resource.monitor_group} AND jmx_password:*") do |u|
      monitors[u['id']] = u['jmx_password']
    end

    file "#{instance_dir}/etc/jmxremote.access" do
      owner node[:glassfish][:user]
      group node[:glassfish][:group]
      mode "0400"
      action :create
      content (admins.keys.sort.collect { |username| "#{username}=readwrite\n" } + monitors.keys.sort.collect { |username| "#{username}=readonly\n" }).join("")
      notifies :restart, resources(:service => "omq-#{new_resource.instance}"), :delayed
    end

    file "#{instance_dir}/etc/jmxremote.password" do
      owner node[:glassfish][:user]
      group node[:glassfish][:group]
      mode "0400"
      action :create
      content (admins.sort.collect { |username, password| "#{username}=#{password}\n" } + monitors.sort.collect { |username, password| "#{username}=#{password}\n" }).join("")
      notifies :restart, resources(:service => "omq-#{new_resource.instance}"), :delayed
    end
  end

  template "#{instance_dir}/props/config.properties" do
    not_if do
      properties = {}
      IO.foreach("#{instance_dir}/props/config.properties") do |line|
        properties[$1.strip] = $2 if line =~ /([^=]*)=(.*)\/\/(.*)/ || line =~ /([^=]*)=(.*)/
      end

      regenerate = false
      mq_config_settings(new_resource).each do |k,v|
        regenerate ||= properties[k] != v
      end
      regenerate
    end
    source "config.properties.erb"
    mode "0600"
    cookbook 'glassfish'
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    variables(:config => mq_config_settings(new_resource))
    notifies :restart, resources(:service => "omq-#{new_resource.instance}"), :delayed
  end

  template "#{instance_dir}/etc/logging.properties" do
    source "logging.properties.erb"
    mode "0400"
    cookbook 'glassfish'
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    variables(:resource => new_resource)
    notifies :restart, resources(:service => "omq-#{new_resource.instance}"), :delayed
  end

  template "#{instance_dir}/etc/passwd" do
    source "passwd.erb"
    mode "0400"
    cookbook 'glassfish'
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    variables(:users => new_resource.users)
  end

  template "#{instance_dir}/etc/accesscontrol.properties" do
    source "accesscontrol.properties.erb"
    mode "0400"
    cookbook 'glassfish'
    owner node[:glassfish][:user]
    group node[:glassfish][:group]
    variables(:rules => new_resource.access_control_rules)
  end

  destinations = {}
  destinations.merge!(new_resource.queues)
  destinations.merge!(new_resource.topics)

  destinations.each_pair do |key, config|
    glassfish_mq_destination key do
      queue new_resource.queues.keys.include?(key)
      processed_config = {}
      config.each_pair do |k, v|
        if k.to_s == 'schema'
          processed_config['validateXMLSchemaEnabled'] = 'true'
          processed_config['XMLSchemaURIList'] = v
        else
          processed_config[k] = v
        end
      end
      config processed_config
      host 'localhost'
      port new_resource.port
      username new_resource.admin_user
      passfile "#{instance_dir}/props/config.properties"
    end
  end
end

action :destroy do
  service "omq-#{new_resource.instance}" do
    action [:stop]
  end

  file "/etc/init/omq-#{new_resource.instance}.conf" do
    action :delete
  end
end
