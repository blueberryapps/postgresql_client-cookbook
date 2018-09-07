# frozen_string_literal: true
#
# Cookbook:: postgresql
# Resource:: server_conf
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

include PostgresqlCookbook::Helpers

property :version,              String, default: '9.6'
property :data_directory,       String, default: lazy { data_dir }
property :hba_file,             String, default: lazy { "#{conf_dir}/pg_hba.conf" }
property :ident_file,           String, default: lazy { "#{conf_dir}/pg_ident.conf" }
property :external_pid_file,    String, default: lazy { "/var/run/postgresql/#{version}-main.pid" }
property :stats_temp_directory, String, default: lazy { "/var/run/postgresql/#{version}-main.pg_stat_tmp" }
property :additional_config,    Hash,   default: {}
property :cookbook,             String, default: 'postgresql'

# to check for restarts
property :database,             String
property :conn,                 Hash, default: {}

action :modify do
  vars = {
    data_directory: new_resource.data_directory,
    hba_file: new_resource.hba_file,
    ident_file: new_resource.ident_file,
    external_pid_file: new_resource.external_pid_file,
    stats_temp_directory: new_resource.stats_temp_directory,
    port: new_resource.conn[:port] || 5432,
  }

  custom = {}

  # override from additional config
  new_resource.additional_config.each do |key, value|
    k = key.to_sym
    if vars.key?(k)
      vars[k] = value # override
    else
      custom[k] = value # store as extra
    end
  end

  # define service and start it if it's not running yet
  service 'postgresql' do
    service_name platform_service_name
    supports restart: true, status: true, reload: true
    action [:enable, :start]
  end

  template "#{conf_dir}/postgresql.conf" do
    cookbook new_resource.cookbook
    source 'postgresql.conf.erb'
    owner 'postgres'
    group 'postgres'
    mode '0600'
    variables(
      data_directory: vars[:data_directory],
      hba_file: vars[:hba_file],
      ident_file: vars[:ident_file],
      external_pid_file: vars[:external_pid_file],
      stats_temp_directory: vars[:stats_temp_directory],
      port: vars[:port],
      additional_config: custom
    )
    notifies :reload, 'service[postgresql]', :immediately
  end

  # restart the service if restart is needed
  service 'postgresql' do
    action :restart
  end if needs_restart
end

action_class do
  include PostgresqlCookbook::Helpers
end
