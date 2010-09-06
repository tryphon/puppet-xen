class xen {

  package { xen-tools: }

  # should be created by xen system
  file { ["/etc/xen/auto", "/etc/xen"]:
    ensure => directory
  }

  define domain($domain, $ip, $size = '1G', $memory = '256M', $swap = '128M', $role = '') {
    $hostname = "$name.$domain"

    exec { "create-xen-$name":
      command => "xen-create-image --size $size --swap $swap --memory $memory --hostname $hostname --ip $ip --role=$role",
      creates => "/etc/xen/$hostname.cfg",
      timeout => 600,
      require => Package["xen-tools"]
    }

    file { "/etc/xen/auto/$hostname.cfg":
      ensure => "/etc/xen/$hostname.cfg",
      require => [File["/etc/xen/auto"],Exec["create-xen-$name"]]
    }

  }

}

class xen::munin::plugin::cpu {
  include munin

  munin::plugin { xen-cpu:
    source => "puppet:///xen/munin/xen-cpu",
    config => "user root"
  }
}

class xen::munin::plugin::memory {
  include munin

  munin::plugin { xen-memory:
    source => "puppet:///xen/munin/xen-memory",
    config => "user root"
  }
}
