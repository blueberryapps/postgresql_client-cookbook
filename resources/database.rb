#
# Cookbook:: postgresql
# Resource:: database
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

property :template, String, default: 'template1'
property :encoding, String
property :locale,   String
property :owner,    String

# Connection prefernces
property :database, String, name_property: true
property :conn,     Hash, default: {}

action :create do
  createdb =  conn_cli 'createdb'
  createdb << " -U #{new_resource.conn[:user] || 'postgres'}"
  createdb << " -p #{new_resource.conn[:port] || 5432}"
  createdb << " -E #{new_resource.encoding}" if new_resource.encoding
  createdb << " -l #{new_resource.locale}" if new_resource.locale
  createdb << " -T #{new_resource.template}" unless new_resource.template.empty?
  createdb << " -O #{new_resource.owner}" if new_resource.owner
  createdb << " #{new_resource.database}"

  execute "Create Database #{new_resource.database}" do
    user 'postgres' if sys_user_exists?('postgres')
    command createdb
    sensitive use_pass
    not_if { slave? }
    not_if { database_exists?(new_resource) }
  end
end

action :drop do
  converge_by "Drop PostgreSQL Database #{new_resource.database}" do
    dropdb =  conn_cli 'dropdb'
    dropdb << " -U #{new_resource.conn[:user] || 'postgres'}"
    dropdb << " -p #{new_resource.conn[:port] || 5432}"
    dropdb << " #{new_resource.database}"

    execute "drop postgresql database #{new_resource.database})" do
      user 'postgres' if sys_user_exists?('postgres')
      command dropdb
      sensitive use_pass
      not_if { slave? }
      only_if { database_exists?(new_resource) }
    end
  end
end

action_class do
  include PostgresqlClientCookbook::Helpers
end
