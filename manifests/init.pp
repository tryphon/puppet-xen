class xen {

  if $debian::lenny {
    package { "xen-utils-3.2-1": }
    package { "xen-linux-system-2.6.26-2-xen-amd64":
      alias => "xen-linux-system"
    }
  } else {
    package { "xen-utils-4.0": }
    package { "xen-linux-system-2.6-xen-amd64":
      alias => "xen-linux-system"
    }

    exec { "xen-grub-fix-priority":
      command => "mv /etc/grub.d/10_linux /etc/grub.d/50_linux && update-grub2",
      creates => "/etc/grub.d/50_linux",
      require => Package["xen-linux-system"]
    }
  }

  package { xen-utils-common:
    # provides /etc/xen/scripts
  }

  package { xen-tools: }

  exec { "check-xen-kernel":
    command => 'uname -r | grep xen',
    require => Package["xen-linux-system"]
  }

  service { "xend":
    ensure => running,
    require => Exec["check-xen-kernel"]
  }

  file { "/usr/local/sbin/xen-image-disk":
    source => ["puppet:///files/xen/xen-tools.conf.$fqdn", "puppet:///xen/xen-image-disk"],
    mode => 755
  }

  file { "/etc/xen-tools/xen-tools.conf":
    source => "puppet:///files/xen/xen-tools.conf.$fqdn",
    require => Package[xen-tools]
  }

  file { "/etc/xen-tools/role.d/puppet":
    source => "puppet:///files/xen/role.d/puppet",
    mode => 755,
    require => Package[xen-tools]
  }

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

  define volume($size, $domain, $base_domain) {
    lvm::logical_volume { $name: size => $size }
    exec { "xen-image-disk-add-$name":
      command => "xen-image-disk add /etc/xen/$domain.$base_domain.cfg /dev/vg/$name",
      unless => "xen-image-disk check /etc/xen/$domain.$base_domain.cfg /dev/vg/$name",
      require => [File["/usr/local/sbin/xen-image-disk"], Lvm::Logical_volume[$name], Xen::Domain[$domain]]
    }
  }
}

class xen::puppetmaster {
  file { "/usr/local/bin/xen-generate-mac":
    source => "puppet:///xen/xen-generate-mac",
    mode => 755
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

class xen::network::bridged {
  exec { "xen-network-script":
    command => "sed -i \"/^(network-script/ s/network-script \\(.*\\))$/network-script network-bridge)/\" /etc/xen/xend-config.sxp",
    unless => "grep '^(network-script network-bridge)' /etc/xen/xend-config.sxp",
    notify => Service["xend"],
    require => Package["xen-linux-system"]
  }
}

class xen::network::dmzloc {
  $xend_config = "/etc/xen/xend-config.sxp"
  exec { "xend-disable-vif-bridge":
    command => "sed -i 's/^(vif-script vif-bridge)/#(vif-script vif-bridge)/' $xend_config",
    onlyif => "grep '^(vif-script vif-bridge)' $xend_config",
    require => Package["xen-utils-common"]
  }

  exec { "ifup-dummy0":
    command => "ifup dummy0",
    unless => "/sbin/ifconfig | grep ^dummy0",
    require => File["/etc/network/interfaces"]
  }

  line { "xend-enable-network-custom":
    file => $xend_config,
    line => '(network-script network-custom)',
    require => [Exec["xend-disable-vif-bridge"], Exec["ifup-dummy0"], File["/etc/xen/scripts/network-custom"]],
    notify => Service["xend"]
  }
  line { "xend-enable-vif-custom":
    file => $xend_config,
    line => '(vif-script vif-custom)',
    require => [Exec["xend-disable-vif-bridge"], Exec["ifup-dummy0"], File["/etc/xen/scripts/vif-custom"]],
    notify => Service["xend"]
  }

  file { "/etc/xen/scripts/network-custom":
    content => '#!/bin/sh
dir=/etc/xen/scripts
logger -t "network-custom" -i "Configure route for eth0"
$dir/network-route "$@" netdev=eth0
logger -t "network-custom" -i "Configure bridge for dummy0"
$dir/network-bridge "$@" netdev=dummy0
',
    mode => 755,
    require => Package["xen-utils-common"]
  }

  file { "/etc/xen/scripts/vif-custom":
    content => '#!/bin/sh
dir=/etc/xen/scripts
IFNUM=$(echo ${vif} | cut -d. -f2)
logger -t "vif-custom" -i "vif=$vif, ifnum=$IFNUM $@"
if [ "$IFNUM" = "0" ]; then
 logger -t "vif-custom" -i "use bridge for $vif"
 $dir/vif-bridge "$@"
else
 logger -t "vif-custom" -i "use route for $vif"
 $dir/vif-route "$@"
fi
',
    mode => 755,
    require => [Package["xen-utils-common"], Package[bridge-utils]]

  }
}
