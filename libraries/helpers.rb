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

module PostgresqlCookbook
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
      cmd = shell_out(statement, user: user)

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

    def extension_installed?(new_resource)
      query = %(SELECT 'installed' FROM pg_extension WHERE extname='#{new_resource.extension}';)
      !(execute_sql(new_resource, query) =~ /^installed$/).nil?
    end

    def alter_role_sql(new_resource)
      sql = %(ALTER ROLE postgres ENCRYPTED PASSWORD '#{postgres_password(new_resource)}';)
      psql_command_string(new_resource, sql)
    end

    def create_extension_sql(new_resource)
      sql = "CREATE EXTENSION IF NOT EXISTS #{new_resource.extension}"
      sql << " FROM \"#{new_resource.old_version}\"" if new_resource.old_version

      psql_command_string(new_resource, sql)
    end

    def user_has_password?(new_resource)
      sql = %(SELECT rolpassword from pg_authid WHERE rolname='postgres' AND rolpassword IS NOT NULL;)
      cmd = psql_command_string(new_resource, sql)

      res = execute_sql(new_resource, cmd)
      res.stdout =~ /1 row/ ? true : false
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

    def conf_dir(version = node.run_state['postgresql']['version'])
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
        "/etc/postgresql/#{version}/main"
      end
    end

    # determine the platform specific service name
    def platform_service_name(version = node.run_state['postgresql']['version'])
      case node['platform_family']
      when 'rhel', 'fedora'
        "postgresql-#{version}"
      when 'amazon'
        if node['virtualization']['system'] == 'docker'
          "postgresql#{version.delete('.')}"
        else
          "postgresql-#{version}"
        end
      else
        'postgresql'
      end
    end

    def slave?
      ::File.exist? "#{data_dir}/recovery.conf"
    end

    def initialized?
      return true if ::File.exist?("#{conf_dir}/PG_VERSION")
      false
    end

    def secure_random
      r = SecureRandom.hex
      Chef::Log.debug "Generated password: #{r}"
      r
    end

    # determine the platform specific server package name
    def server_pkg_name
      platform_family?('debian') ? "postgresql-#{new_resource.version}" : "postgresql#{new_resource.version.delete('.')}-server"
    end

    # determine the appropriate DB init command to run based on RHEL/Fedora/Amazon release
    # initdb defaults to the execution environment.
    # https://www.postgresql.org/docs/9.5/static/locale.html
    def rhel_init_db_command(new_resource)
      cmd = if platform_family?('amazon')
              '/usr/bin/initdb'
            else
              "/usr/pgsql-#{new_resource.version}/bin/initdb"
            end
      cmd << " --locale '#{new_resource.initdb_locale}'" if new_resource.initdb_locale
      cmd << " -D '#{data_dir(new_resource.version)}'"
    end

    # Given the base URL build the complete URL string for a yum repo
    def yum_repo_url(base_url)
      "#{base_url}/#{new_resource.version}/#{yum_repo_platform_family_string}/#{yum_repo_platform_string}"
    end

    # The postgresql yum repos URLs are organized into redhat and fedora directories.s
    # route things to the right place based on platform_family
    def yum_repo_platform_family_string
      platform_family?('fedora') ? 'fedora' : 'redhat'
    end

    # Build the platform string that makes up the final component of the yum repo URL
    def yum_repo_platform_string
      platform = platform?('fedora') ? 'fedora' : 'rhel'
      release = platform?('amazon') ? '6' : '$releasever'
      "#{platform}-#{release}-$basearch"
    end

    # On Amazon use the RHEL 6 packages. Otherwise use the releasever yum variable
    def yum_releasever
      platform?('amazon') ? '6' : '$releasever'
    end

    # Generate a password if the value is set to generate.
    def postgres_password(new_resource)
      new_resource.conn[:password_generate] ? secure_random : new_resource.conn[:password]
    end

    # Checks if a config value needs restart
    def needs_restart
      sql = "SELECT COUNT(*) FROM pg_settings WHERE pending_restart='t';"
      cmd = psql_command_string(new_resource, sql, concise: true)
      cmd = execute_sql(new_resource, cmd)

      cmd.exitstatus != 0 || cmd.stdout.strip.to_i > 0
    end

    # Grants a user access to database
    def grant_user_db_sql(new_resource)
      sql = "GRANT #{new_resource.privileges.join(', ')} ON DATABASE \\\"#{new_resource.database}\\\" TO \\\"#{new_resource.create_user}\\\";"
      psql_command_string(new_resource, sql)
    end

    # Return true if connection via TCP should be used - either host must be remote or user must be different from postgres
    def use_tcp
      return false if new_resource.conn[:peer] # flag peer authentication immediately

      not [nil, 'localhost', '127.0.0.1'].include?(new_resource.conn[:host]) && [nil, 'postgres'].include?(new_resource.conn[:user])
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
  end
end
