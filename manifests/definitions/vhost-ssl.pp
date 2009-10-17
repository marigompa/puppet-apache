define apache::vhost-ssl (
  $ensure=present,
  $config_file=false,
  $config_content=false,
  $htdocs=false,
  $conf=false,
  $readme=false,
  $user="$wwwuser",
  $admin="$admin",
  $group="root",
  $mode=2570,
  $aliases=[],
  $ip_address="*",
  $cert=false,
  $certkey=false,
  $cacert=false,
  $certchain=false,
  $days="3650",
  $publish_csr=false,
  $sslonly=false
) {

  case $operatingsystem {
    redhat : {
      $wwwuser =  $user ? {
        "" => "apache",
        default => $user,
      }
      $wwwroot = "/var/www/vhosts"
      $wwwconf = "/etc/httpd"
    }
    debian : {
      $wwwuser =  $user ? {
        "" => "www-data",
        default => $user,
      }
      $wwwroot = "/var/www"
      $wwwconf = "/etc/apache2"
    }
    default : { fail "Unsupported operatingsystem ${operatingsystem}" }
  }    

  # define variable names used in vhost-ssl.erb template
  $certfile      = "$wwwroot/$name/ssl/$name.crt"
  $certkeyfile   = "$wwwroot/$name/ssl/$name.key"
  $csrfile       = "$wwwroot/$name/ssl/$name.csr"

  if $cacert != false {
    $cacertfile = "$wwwroot/$name/ssl/cacert.crt"
  } else {
    $cacertfile = $operatingsystem ? {
      RedHat => "/etc/pki/tls/certs/ca-bundle.crt",
      Debian => "/etc/ssl/certs/ca-certificates.crt",
    }
  }

  if $certchain != false {
    $certchainfile = "$wwwroot/$name/ssl/certchain.crt"
  }


  apache::vhost {$name:
    ensure         => $ensure,
    config_file    => $config_file,
    config_content => $config_content ? {
      false => $sslonly ? {
        true => template("apache/vhost-ssl.erb"),
        default => template("apache/vhost.erb", "apache/vhost-ssl.erb"),
      },
      default      => $config_content,
    },
    aliases        => $aliases,
    htdocs         => $htdocs,
    conf           => $conf,
    readme         => $readme,
    user           => $user,
    admin          => $admin,
    group          => $group,
    mode           => $mode,
    aliases        => $aliases,
    enable_default => $sslonly ? {
      true => false,
      default => true,
    }
  }

  if $sslonly {
    exec { "disable default site":
      command => $operatingsystem ? {
        Debian => "/usr/sbin/a2dissite default",
        RedHat => "/usr/local/sbin/a2dissite default",
      },
      onlyif => "/usr/bin/test -L ${wwwconf}/sites-enabled/000-default",
      notify => Exec["apache-graceful"],
    }
  }

  if $ensure == "present" {
    file { "${wwwroot}/${name}/ssl":
      ensure => directory,
      owner  => "root",
      group  => "root",
      mode   => 700,
      seltype => "cert_t",
      require => [File["${wwwroot}/${name}"]],
    }

    exec { "generate-ssl-cert-$name":
      command => "/usr/local/sbin/generate-ssl-cert.sh $name /etc/ssl/ssleay.cnf ${wwwroot}/${name}/ssl/ $days",
      creates => [$certfile, $certkeyfile, $csrfile],
      notify  => Exec["apache-graceful"],
      require => [
        File["${wwwroot}/${name}/ssl"],
        File["/usr/local/sbin/generate-ssl-cert.sh"],
        File["/etc/ssl/ssleay.cnf"]
      ],
    }

    # The virtualhost's certificate.
    # Manage content only if $cert is set, else use the certificate generated
    # by generate-ssl-cert.sh
    file { $certfile:
      owner => "root",
      group => "root",
      mode  => 640,
      source  => $cert ? {
        false   => undef,
        default => $cert,
      },
      seltype => "cert_t",
      notify  => Exec["apache-graceful"],
      require => [File["${wwwroot}/${name}/ssl"], Exec["generate-ssl-cert-$name"]],
    }

    # The virtualhost's private key.
    # Manage content only if $certkey is set, else use the key generated by
    # generate-ssl-cert.sh
    file { $certkeyfile:
      owner => "root",
      group => "root",
      mode  => 600,
      source  => $certkey ? {
        false   => undef,
        default => $certkey,
      },
      seltype => "cert_t",
      notify  => Exec["apache-graceful"],
      require => [File["${wwwroot}/${name}/ssl"], Exec["generate-ssl-cert-$name"]],
    }

    # The certificate from your certification authority. Defaults to the
    # certificate bundle shipped with your distribution.
    file { $cacertfile:
      owner => "root",
      group => "root",
      mode  => 640,
      source  => $cacert ? {
        false   => undef,
        default => $cacert,
      },
      seltype => "cert_t",
      notify  => Exec["apache-graceful"],
      require => File["${wwwroot}/${name}/ssl"],
    }


    if $certchain != false {

      # The certificate chain file from your certification authority's. They
      # should inform you if you need one.
      file { $certchainfile:
        owner => "root",
        group => "root",
        mode  => 640,
        source  => $certchain,
        seltype => "cert_t",
        notify  => Exec["apache-graceful"],
        require => File["${wwwroot}/${name}/ssl"],
      }
    }

    # put a copy of the CSR in htdocs, or another location if $publish_csr
    # specifies so.
    file { "public CSR file":
      ensure  => $publish_csr ? {
        false   => "absent",
        default => "present",
      },
      path    => $publish_csr ? {
        true    => "${wwwroot}/${name}/htdocs/$name.csr",
        false   => "${wwwroot}/${name}/htdocs/$name.csr",
        default => $publish_csr,
      },
      source  => "file://$csrfile",
      mode    => 640,
      seltype => "httpd_sys_content_t",
      require => Exec["generate-ssl-cert-$name"],
    }

  }
}
