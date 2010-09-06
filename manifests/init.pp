class xen {

  package { xen-tools: }

  # should be created by xen system
  file { ["/etc/xen/auto", "/etc/xen"]:
    ensure => directory,
    require => Package[xen-tools]
  }

  define domain($ip, $domain = '', $size = "1G", $memory = "256M", $swap = "128M", $role = "puppet") {
    include xen

    $hostname = $domain ? {
      '' => $name,
      default => "$name.$domain"
    }

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

class xen::munin::plugins {
  include xen::munin::plugin::cpu
}

class xen::munin::plugin::cpu {
  include munin

  file { "/usr/local/share/munin/plugins/xen-cpu":
    source => "puppet:///xen/munin/xen-cpu",
    mode => 755,
    require => Package[xen-tools]
  }
  munin::plugin { xen-cpu:
    script_path => "/usr/local/share/munin/plugins",
    config => "user root",
    require => File["/usr/local/share/munin/plugins/xen-cpu"]
  }

}
