# frozen_string_literal: true
name              'postgresql_client'
maintainer        'Adam Zahumensky'
maintainer_email  'azahumensky@blueberry.io'
license           'Apache-2.0'
description       'Client interface for postgresql'
long_description  IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version           '7.1.0'
source_url        'https://github.com/blueberryapps/postgresql_client-cookbook'
issues_url        'https://github.com/blueberryapps/postgresql_client-cookbook/issues'
chef_version      '>= 13.8'
depends           'postgresql', '> 7.0' # postgresql_client_install

%w(ubuntu debian fedora amazon redhat centos scientific oracle).each do |os|
  supports os
end
