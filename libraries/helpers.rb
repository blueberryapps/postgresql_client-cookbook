#
# Cookbook:: postgresql
# Library:: helpers
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

include Chef::Mixin::ShellOut # wrapping this inside the module breaks MiniTests which use shell_out

module PostgresqlClientCookbook
  module Helpers
    require 'securerandom'

    def psql_command_string(new_resource, query, grep_for = nil, concise: false)
      cmd = conn_cli '/usr/bin/psql'
      cmd << " -At" if concise
      cmd << " -c \"#{query}\""
      cmd << " -U #{new_resource.conn[:user] || 'postgres'}"
      cmd << " -p #{new_resource.conn[:port] || 5432}"
      cmd << " -d #{new_resource.database}" if new_resource.database
      cmd << " | grep #{grep_for}"          if grep_for
      cmd
    end

    def execute_sql(new_resource, query)
      # If we don't pass in a user to the resource
      # default to the postgres user
      user = new_resource.conn[:user] || 'postgres'

      # Query could be a String or an Array of Strings
      statement = query.is_a?(String) ? query : query.join("\n")
      cmd = sys_user_exists?(user) ? shell_out(statement, user: user) : shell_out(statement)

      # Pass back cmd so we can decide what to do with it in the calling method.
      cmd
    end

    def database_exists?(new_resource)
      sql = %(SELECT datname from pg_database WHERE datname='#{new_resource.database}')

      # Set some values to nil so we can use the generic psql_command_string method.
      # res = {
      #   user: new_resource.conn[:password],
      #   port: new_resource.conn[:port],
      #   database: nil,
      #   host: nil,
      # }

      exists = psql_command_string(new_resource, sql, new_resource.database)

      cmd = execute_sql(new_resource, exists)
      cmd.exitstatus == 0
    end

    def user_exists?(new_resource)
      sql = %(SELECT rolname FROM pg_roles WHERE rolname='#{new_resource.create_user}';)

      exists = psql_command_string(new_resource, sql, new_resource.create_user)

      cmd = execute_sql(new_resource, exists)
      cmd.exitstatus == 0
    end

    def create_extension_sql(new_resource)
      sql = "CREATE EXTENSION IF NOT EXISTS #{new_resource.extension}"
      sql << " FROM \"#{new_resource.old_version}\"" if new_resource.old_version

      psql_command_string(new_resource, sql)
    end

    def role_sql(new_resource)
      sql = %(#{new_resource.create_user} WITH )

      %w(superuser createdb createrole inherit replication login).each do |perm|
        sql << "#{'NO' unless new_resource.send(perm)}#{perm.upcase} "
      end

      sql << if new_resource.encrypted_password
               "ENCRYPTED PASSWORD '#{new_resource.encrypted_password}'"
             elsif new_resource.password
               "PASSWORD '#{new_resource.password}'"
             else
               ''
             end

      sql << if new_resource.valid_until
               " VALID UNTIL '#{new_resource.valid_until}'"
             else
               ''
             end
    end

    def create_user_sql(new_resource)
      sql = %(CREATE ROLE #{role_sql(new_resource)})
      psql_command_string(new_resource, sql)
    end

    def update_user_sql(new_resource)
      sql = %(ALTER ROLE #{role_sql(new_resource)})
      psql_command_string(new_resource, sql)
    end

    def update_user_with_attributes_sql(new_resource, value)
      sql = %(ALTER ROLE '#{new_resource.create_user}' SET #{attr} = #{value})
      psql_command_string(new_resource, sql)
    end

    def drop_user_sql(new_resource)
      sql = %(DROP ROLE IF EXISTS '#{new_resource.create_user}')
      psql_command_string(new_resource, sql)
    end

    def data_dir(version = node.run_state['postgresql']['version'])
      case node['platform_family']
      when 'rhel', 'fedora'
        "/var/lib/pgsql/#{version}/data"
      when 'amazon'
        if node['virtualization']['system'] == 'docker'
          "/var/lib/pgsql#{version.delete('.')}/data"
        else
          "/var/lib/pgsql/#{version}/data"
        end
      when 'debian'
        "/var/lib/postgresql/#{version}/main"
      end
    end

    # Host is local and it is not slave
    def slave?
      is_local? && ::File.exist?("#{data_dir}/recovery.conf")
    end

    def secure_random
      r = SecureRandom.hex
      Chef::Log.debug "Generated password: #{r}"
      r
    end

    # Generate a password if the value is set to generate.
    def postgres_password(new_resource)
      new_resource.conn[:password_generate] ? secure_random : new_resource.conn[:password]
    end

    # Grants a user access to database
    def grant_user_db_sql(new_resource)
      sql = "GRANT #{new_resource.privileges.join(', ')} ON DATABASE \\\"#{new_resource.database}\\\" TO \\\"#{new_resource.create_user}\\\";"
      psql_command_string(new_resource, sql)
    end

    def is_local?
      [nil, 'localhost', '127.0.0.1'].include?(new_resource.conn[:host])
    end

    # Return true if connection via TCP should be used - either host must be remote or user must be different from postgres
    def use_tcp
      return false if new_resource.conn[:peer] # flag peer authentication immediately

      not is_local? && [nil, 'postgres'].include?(new_resource.conn[:user])
    end

    # True if postgresql password will be used
    def use_pass
      new_resource.conn.key?(:password) && use_tcp
    end

    # Add connection params to postgresql cli command
    def conn_cli(executable)
      return executable unless use_tcp
      cmd = use_pass ? "PGPASSWORD=#{new_resource.conn[:password]} " : ''
      cmd << executable
      cmd << " -h #{new_resource.conn[:host] || 'localhost'}"
      cmd
    end

    # True if provided system user exists on the node
    def sys_user_exists?(user)
      node['etc']['passwd'].key?(user.to_sym)
    end
  end
end
