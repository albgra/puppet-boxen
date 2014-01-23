# A Boxen-focused project setup helper
#
# Options:
#
#     dir =>
#       The directory to clone the project to.
#       Defaults to "${boxen::config::srcdir}/${name}".
#
#     dotenv =>
#       If true, creates "${dir}/.env" from
#       "puppet:///modules/projects/${name}/dotenv".
#
#     elasticsearch =>
#       If true, ensures elasticsearch is installed.
#
#     memcached =>
#       If true, ensures memcached is installed.
#
#     mongodb =>
#       If true, ensures mongodb is installed.
#
#     cassandra =>
#       If true, ensures cassandra is installed.
#
#     zookeeper =>
#       If true, ensures zookeeper is installed.
#
#     beanstalk =>
#       If true, ensures beanstalk is installed.
#
#     nsq =>
#       If true, ensures nsq is installed.
#
#     zeromq =>
#       If true, ensures zeromq is installed.
#
#     mysql =>
#       If set to true, ensures mysql is installed and creates databases named
#       "${name}_development" and "${name}_test".
#       If set to any string or array value, creates those databases instead.
#
#     nginx =>
#       If true, ensures nginx is installed and uses standard template at
#       modules/projects/templates/shared/nginx.conf.erb.
#       If given a string, uses that template instead.
#
#     postgresql =>
#       If set to true, ensures postgresql is installed and creates databases
#       named "${name}_development" and "${name}_test".
#       If set to any string or array value, creates those databases instead.
#
#     redis =>
#       If true, ensures redis is installed.
#
#     ruby =>
#       If given a string, ensures that ruby version is installed.
#       Also creates "${dir}/.ruby-version" with content being this value.
#
#     phantomjs =>
#       If given a string, ensures that phantomjs version is installed.
#       Also creates "${dir}/.phantom-version" with content being this value.
#
#     source =>
#       Repo to clone project from. REQUIRED. Supports shorthand <user>/<repo>.
#

define boxen::project(
  $source,
  $dir           = undef,
  $dotenv        = undef,
  $elasticsearch = undef,
  $memcached     = undef,
  $mongodb       = undef,
  $cassandra     = undef,
  $zookeeper     = undef,
  $beanstalk     = undef,
  $nsq           = undef,
  $zeromq        = undef,
  $mysql         = undef,
  $nginx         = undef,
  $nodejs        = undef,
  $postgresql    = undef,
  $redis         = undef,
  $ruby          = undef,
  $phantomjs     = undef,
  $server_name   = "${name}.dev",
  $django        = undef,
  $custom_virtualenv_postactivate_template        = undef,
  $custom_uwsgi_template        = undef,
) {
  include boxen::config

  $repo_dir = $dir ? {
    undef   => "${boxen::config::srcdir}/${name}",
    default => $dir
  }

  repository { $repo_dir:
    source => $source
  }

  if $dotenv {
    file { "${repo_dir}/.env":
      source  => "puppet:///modules/projects/${name}/dotenv",
      require => Repository[$repo_dir],
    }
  }

  if $elasticsearch {
    include elasticsearch
  }

  if $memcached {
    include memcached
  }

  if $mongodb {
    include mongodb
  }

  if $cassandra {
    include cassandra
  }

  if $zookeeper {
    include zookeeper
  }

  if $beanstalk {
    include beanstalk
  }

  if $nsq {
    include nsq
  }

  if $zeromq {
    include zeromq
  }

  if $mysql {
    require mysql

    $mysql_dbs = $mysql ? {
      true    => ["${name}_development", "${name}_test"],
      default => $mysql,
    }

    mysql::db { $mysql_dbs: }
  }

  if $nginx {
    include nginx::config
    include nginx

    $nginx_shared_templ = $django ? {
      true    => 'projects/shared/django-nginx.conf.erb',
      default => 'projects/shared/nginx.conf.erb',
    }

    $nginx_templ = $nginx ? {
      true    => $nginx_shared_templ,
      default => $nginx,
    }

    file { "${nginx::config::sitesdir}/${name}.conf":
      content => template($nginx_templ),
      require => File[$nginx::config::sitesdir],
      notify  => Service['dev.nginx'],
    }
  }

  if $nodejs {
    nodejs::local { $repo_dir:
      version => $nodejs,
      require => Repository[$repo_dir],
    }
  }

  if $postgresql {
    $psql_dbs = $postgresql ? {
      true    => ["${name}_development", "${name}_test"],
      default => $postgresql,
    }

    postgresql::db { $psql_dbs: }
  }

  if $redis {
    include redis
  }

  if $ruby {
    ruby::local { $repo_dir:
      version => $ruby,
      require => Repository[$repo_dir]
    }
  }

  if $phantomjs {
    phantomjs::local { $repo_dir:
      version => $phantomjs,
      require => Repository[$repo_dir]
    }
  }

  if $django {
    include karumi::environment

    # Setup nodejs modules that are needed for the build
    nodejs::module { "yuglify for ${karumi::environment::node_global}":
      module       => 'yuglify',
        ensure       => '0.1.4',
        node_version => $karumi::environment::node_global,
    }

    nodejs::module { "coffee-script for ${karumi::environment::node_global}":
      module       => 'coffee-script',
        ensure       => '1.6.3',
        node_version => $karumi::environment::node_global,
    }

    ruby::gem { "sass for ${karumi::environment::ruby_global}":
      gem     => 'sass',
      ruby    => $karumi::environment::ruby_global,
      ensure    => 'present',
      version   => '3.2.12',
    }

    $virtualenv_postactivate_template = $custom_virtualenv_postactivate_template ? {
      undef      => 'projects/shared/virtualenv_postactivate.sh.erb',
      default    => $custom_virtualenv_postactivate_template,
    }

    # Setup the virtualenv for this project
    python::mkvirtualenv{ $name:
      ensure      => present,
      systempkgs  => false,
      distribute  => true,
      project_dir => "${boxen::config::srcdir}",
      post_activate => template($virtualenv_postactivate_template),
    }

    # Install project requirements
    python::requirements { "${name}-requirements":
      requirements => "${boxen::config::srcdir}/${name}/requirements.txt",
      virtualenv   => $name,
      require      => [Python::Mkvirtualenv[$name], Repository[$repo_dir]],
    }

    # Copy uwsgi config so we can run the service
    include python::config

    $uwsgi_template = $custom_uwsgi_template ? {
      undef       => 'projects/shared/uwsgi.ini.erb',
      default     => "projects/${name}/uwsgi.ini.erb",
    }

    file { "uwsgi-${name}":
      path    => "${boxen::config::configdir}/${name}_uwsgi.ini",
      ensure => present,
      mode    => '0644',
      content => template($uwsgi_template),
    }
  }
}
