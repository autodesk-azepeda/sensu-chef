#
# Cookbook Name:: sensu
# Recipe:: rabbitmq
#
# Copyright 2014, Sonian Inc.
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

group "rabbitmq"

if node.sensu.use_ssl
  node.override.rabbitmq.ssl = true
  node.override.rabbitmq.ssl_port = node.sensu.rabbitmq.port
  node.override.rabbitmq.ssl_verify = "verify_peer"
  node.override.rabbitmq.ssl_fail_if_no_peer_cert = true

  ssl_directory = "/etc/rabbitmq/ssl"

  directory ssl_directory do
    recursive true
  end

  ssl = Sensu::Helpers.data_bag_item(node['sensu']['ssl_data_bag_key'], false ,node['sensu']['data_bag_name'])

  %w[
    cacert
    cert
    key
  ].each do |item|
    path = File.join(ssl_directory, "#{item}.pem")
    file path do
      content ssl["server"][item]
      group "rabbitmq"
      mode 0640
    end
    node.override.rabbitmq["ssl_#{item}"] = path
  end

  directory File.join(ssl_directory, "client")

  %w[
    cert
    key
  ].each do |item|
    path = File.join(ssl_directory, "client", "#{item}.pem")
    file path do
      content ssl["client"][item]
      group "rabbitmq"
      mode 0640
    end
  end
end

# The packaged erlang in 12.04 (and below) is vulnerable to
# the poodle exploit which stops rabbitmq starting its SSL listener
if node.platform == "ubuntu" && node.platform_version <= "12.04"
  node.override.erlang.install_method = "esl"
end

include_recipe "rabbitmq"
include_recipe "rabbitmq::mgmt_console"

service "restart #{node.rabbitmq.service_name}" do
  service_name node.rabbitmq.service_name
  action :nothing
  subscribes :restart, resources("template[#{node.rabbitmq.config_root}/rabbitmq.config]"), :immediately
end

rabbitmq = node.sensu.rabbitmq.to_hash

sensu_config = Sensu::Helpers.data_bag_item(node['sensu']["config_data_bag_key"], true, node['sensu']['data_bag_name'])

if sensu_config && sensu_config["rabbitmq"].is_a?(Hash)
  rabbitmq = Chef::Mixin::DeepMerge.merge(rabbitmq, sensu_config["rabbitmq"])
end

rabbitmq_credentials "general" do
  vhost rabbitmq["vhost"]
  user rabbitmq["user"]
  password rabbitmq["password"]
  permissions rabbitmq["permissions"]
end

%w[
  client
  api
  server
].each do |service|
  service_config = Sensu::Helpers.data_bag_item(node['sensu']["#{service}_data_bag_key"], true, node['sensu']['data_bag_name'])

  next unless service_config && service_config["rabbitmq"].is_a?(Hash)

  service_rabbitmq = Chef::Mixin::DeepMerge.merge(rabbitmq, service_config["rabbitmq"])

  rabbitmq_credentials service do
    vhost service_rabbitmq["vhost"]
    user service_rabbitmq["user"]
    password service_rabbitmq["password"]
    permissions service_rabbitmq["permissions"]
  end
end
