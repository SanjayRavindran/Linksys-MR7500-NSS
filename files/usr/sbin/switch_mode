#!/bin/sh
# Switch MR7500 between 'router' mode (NAT + WAN DHCP + LAN DHCP server)
# and 'ap' mode (Dumb AP / Unified 5-port Switch + Tri-Band AP)
#
# Usage:
#   /rom/bin/sh switch_mode.sh [ap|router] [MGMT_IP]

MODE="$1"
MGMT_IP="${2:-192.168.1.91}"

if [ "$MODE" = "ap" ]; then
    echo "=== SWITCHING TO SWITCH + AP MODE ==="
    
    # Bridge all 5 ports
    uci -q del_list network.@device[0].ports='wan'
    uci add_list network.@device[0].ports='wan'

    # Configure static IP on main LAN
    uci set network.lan.device='br-lan'
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$MGMT_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.gateway='192.168.1.1'
    uci -q delete network.lan.dns
    uci add_list network.lan.dns='192.168.1.1'
    uci add_list network.lan.dns='1.1.1.1'
    uci -q delete network.lan.broadcast
    uci -q delete network.lan.ip6assign

    # Add fallback static IP for safety
    uci set network.lan_backup=interface
    uci set network.lan_backup.device='br-lan'
    uci set network.lan_backup.proto='static'
    uci set network.lan_backup.ipaddr='10.143.1.1'
    uci set network.lan_backup.netmask='255.255.255.0'

    uci -q delete network.wan
    uci -q delete network.wan6
    uci commit network

    # Disable local DHCP & RA
    uci set dhcp.lan.ignore='1'
    uci set dhcp.lan.dhcpv4='disabled'
    uci set dhcp.lan.dhcpv6='disabled'
    uci set dhcp.lan.ra='disabled'
    uci -q delete dhcp.lan.dhcp_option
    uci -q delete dhcp.lan.ra_flags
    uci -q delete dhcp.lan.ra_slaac
    uci -q delete dhcp.lan.ra_default
    uci -q delete dhcp.wan
    uci commit dhcp

    # Firewall all accept
    uci set firewall.@defaults[0].input='ACCEPT'
    uci set firewall.@defaults[0].output='ACCEPT'
    uci set firewall.@defaults[0].forward='ACCEPT'
    uci set firewall.@zone[0].input='ACCEPT'
    uci set firewall.@zone[0].output='ACCEPT'
    uci set firewall.@zone[0].forward='ACCEPT'
    uci -q delete firewall.wan
    uci -q delete firewall.@zone[1]
    uci -q delete firewall.@forwarding[0]
    uci commit firewall

    /etc/init.d/odhcpd stop 2>/dev/null || true
    /etc/init.d/odhcpd disable 2>/dev/null || true
    /etc/init.d/network restart
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart
    echo "[+] Switched to Switch + AP Mode (IP: $MGMT_IP, fallback: 10.143.1.1)"

elif [ "$MODE" = "router" ]; then
    echo "=== SWITCHING TO ROUTER MODE ==="
    
    # Remove wan from bridge
    uci -q del_list network.@device[0].ports='wan'

    # Configure LAN subnet 10.143.1.1/24
    uci set network.lan.device='br-lan'
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr='10.143.1.1'
    uci set network.lan.netmask='255.255.255.0'
    uci -q delete network.lan.gateway
    uci -q delete network.lan.dns
    uci set network.lan.ip6assign='60'
    uci -q delete network.lan_backup

    # Configure WAN
    uci set network.wan=interface
    uci set network.wan.device='wan'
    uci set network.wan.proto='dhcp'

    uci set network.wan6=interface
    uci set network.wan6.device='wan'
    uci set network.wan6.proto='dhcpv6'
    uci commit network

    # Enable local DHCP & RA
    uci set dhcp.lan.ignore='0'
    uci set dhcp.lan.dhcpv4='server'
    uci set dhcp.lan.dhcpv6='server'
    uci set dhcp.lan.ra='server'
    uci set dhcp.lan.start='100'
    uci set dhcp.lan.limit='150'
    uci set dhcp.lan.leasetime='12h'
    uci add_list dhcp.lan.dhcp_option='3,10.143.1.1'
    uci add_list dhcp.lan.dhcp_option='6,10.143.1.1'
    uci add_list dhcp.lan.ra_flags='other-config'
    uci set dhcp.lan.ra_slaac='1'
    uci set dhcp.lan.ra_default='1'

    uci set dhcp.wan=dhcp
    uci set dhcp.wan.interface='wan'
    uci set dhcp.wan.ignore='1'
    uci commit dhcp

    # Firewall NAT
    uci set firewall.@defaults[0].input='REJECT'
    uci set firewall.@defaults[0].output='ACCEPT'
    uci set firewall.@defaults[0].forward='REJECT'
    uci set firewall.@zone[0].input='ACCEPT'
    uci set firewall.@zone[0].output='ACCEPT'
    uci set firewall.@zone[0].forward='ACCEPT'

    uci set firewall.wan=zone
    uci set firewall.wan.name='wan'
    uci add_list firewall.wan.network='wan'
    uci add_list firewall.wan.network='wan6'
    uci set firewall.wan.input='REJECT'
    uci set firewall.wan.output='ACCEPT'
    uci set firewall.wan.forward='DROP'
    uci set firewall.wan.masq='1'
    uci set firewall.wan.mtu_fix='1'
    uci set firewall.wan.masq6='1'

    uci set firewall.fwd_lan_wan=forwarding
    uci set firewall.fwd_lan_wan.src='lan'
    uci set firewall.fwd_lan_wan.dest='wan'
    uci commit firewall

    /etc/init.d/odhcpd enable 2>/dev/null || true
    /etc/init.d/odhcpd start 2>/dev/null || true
    /etc/init.d/network restart
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart
    echo "[+] Switched to Router Mode (LAN: 10.143.1.1/24 with NAT on WAN)"

else
    echo "Usage: $0 [ap|router] [MGMT_IP]"
    exit 1
fi
