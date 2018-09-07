#
# Cookbook:: postgresql
# Resource:: extension
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

property :extension,        String, name_property: true
property :old_version,      String
property :source_directory, String
property :version,          String, default: '--1.0'

# Connection prefernces
property :database, String, required: true
property :conn,     Hash, default: {}

action :create do
  # load extension from source
  if new_resource.source_directory
    extension_path = ::File.join(new_resource.source_directory, "#{new_resource.extension}#{new_resource.version}.sql")
    cmd = %(#{conn_cli 'psql'} -f "#{extension_path}" -d test_1 -U postgres --port 5432)

    execute "Load extension #{new_resource.name}" do
      user 'postgres'
      command cmd
      sensitive use_pass
      action :run
      not_if { slave? }
      not_if { extension_installed?(new_resource) }
    end

    control_file_path = ::File.join(new_resource.source_directory, "#{new_resource.extension}.control")

    link control_file_path do
      to "/usr/pgsql-#{node.run_state['postgresql']['version']}/share/extension/#{new_resource.extension}.control"
    end
  end

  execute "CREATE EXTENSION #{new_resource.name}" do
    user 'postgres'
    command create_extension_sql(new_resource)
    sensitive use_pass
    action :run
    not_if { slave? }
    not_if { extension_installed?(new_resource) }
  end
end

action :drop do
  execute "DROP EXTENSION #{new_resource.name}" do
    user 'postgres'
    command psql_command_string(new_resource, "DROP EXTENSION IF EXISTS \"#{new_resource.extension}\"")
    sensitive use_pass
    action :run
    not_if { slave? }
    only_if { extension_installed?(new_resource) }
  end
end

action_class do
  include PostgresqlCookbook::Helpers
end
