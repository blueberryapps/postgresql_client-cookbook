#
# Cookbook:: postgresql
# Resource:: user
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

property :create_user,        String, name_property: true
property :superuser,          [true, false], default: false
property :createdb,           [true, false], default: false
property :createrole,         [true, false], default: false
property :inherit,            [true, false], default: true
property :replication,        [true, false], default: false
property :login,              [true, false], default: true
property :password,           String
property :encrypted_password, String
property :valid_until,        String
property :attributes,         Hash, default: {}
property :database,           String
property :privileges,         Array

# Connection prefernces
property :database, String
property :conn,     Hash, default: {}

action :create do
  Chef::Log.warn('You cannot use "attributes" property with create action.') unless new_resource.attributes.empty?

  execute "create postgresql user #{new_resource.create_user}" do # ~FC009
    user 'postgres' if sys_user_exists?('postgres')
    command create_user_sql(new_resource)
    sensitive true
    not_if { slave? }
    not_if { user_exists?(new_resource) }
  end
end

action :update do
  if new_resource.attributes.empty?
    execute "update postgresql user #{new_resource.create_user}" do
      user 'postgres' if sys_user_exists?('postgres')
      command update_user_sql(new_resource)
      sensitive true
      not_if { slave? }
      only_if { user_exists?(new_resource) }
    end
  else
    new_resource.attributes.each do |attr, value|
      v = if value.is_a?(TrueClass) || value.is_a?(FalseClass)
            value.to_s
          else
            "'#{value}'"
          end

      execute "Update postgresql user #{new_resource.create_user} to set #{attr}" do
        user 'postgres' if sys_user_exists?('postgres')
        command update_user_with_attributes_sql(new_resource, v)
        sensitive true
        not_if { slave? }
        only_if { user_exists?(new_resource) }
      end
    end
  end
end

action :drop do
  execute "drop postgresql user #{new_resource.create_user}" do
    user 'postgres' if sys_user_exists?('postgres')
    command drop_user_sql(new_resource)
    sensitive use_pass
    not_if { slave? }
    only_if { user_exists?(new_resource) }
  end
end

action :grant do
  if new_resource.database && new_resource.privileges
    execute "grant #{new_resource.create_user} access to #{new_resource.database}" do
      user 'postgres' if sys_user_exists?('postgres')
      command grant_user_db_sql(new_resource)
      sensitive use_pass
      not_if { slave? }
      only_if { user_exists?(new_resource) && database_exists?(new_resource) }
    end
  end
end

action_class do
  include PostgresqlCookbook::Helpers
end
