class xen {

  package { xen-tools: }

  # should be created by xen system
  file { ["/etc/xen/auto", "/etc/xen"]:
    ensure => directory,
    require => Package[xen-tools]
  }

  define domain($ip, $domain = '', $size = "1G", $memory = "256M", $swap = "128M", $role = "puppet", $vifname = false, $mac = false) {
    include xen

    $hostname = $domain ? {
      '' => $name,
      default => "$name.$domain"
    }

    $vifname_option = $vifname ? {
      false => '',
      default => "--vifname=$vifname"
    }
    $mac_option = $mac ? {
      false => '',
      default => "--mac=$mac"
    }

    exec { "create-xen-$name":
      command => "xen-create-image --size $size --swap $swap --memory $memory --hostname $hostname --ip $ip --role=$role $vifname_option $mac_option",
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

class xen::munin::plugins {
  include xen::munin::plugin::cpu
  include xen::munin::plugin::memory
  include xen::munin::plugin::traffic-all
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

class xen::munin::plugin::traffic-all {
  include munin

  munin::plugin { xen-traffic-all:
    source => "puppet:///xen/munin/xen-traffic-all",
    config => "user root"
  }
}
