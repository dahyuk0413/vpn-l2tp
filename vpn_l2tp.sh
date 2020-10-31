#!/bin/bash

sysctl_content="""vm.swappiness = 0
net.ipv4.neigh.default.gc_stale_time=120
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.all.arp_announce=2
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_synack_retries = 2
net.ipv4.conf.lo.arp_announce=2
net.ipv4.ip_forward = 1
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.default.accept_source_route = 0"""

l2tp_psk_content="""conn L2TP-PSK-NAT
     rightsubnet=vhost:%%priv
     also=L2TP-PSK-noNAT
conn L2TP-PSK-noNAT
     authby=secret
     pfs=no
     auto=add
     keyingtries=3
     dpddelay=30
     dpdtimeout=120
     dpdaction=clear
     rekey=no
     ikelifetime=8h
     keylife=1h
     type=transport
     left=$(hostname -I)
     leftprotoport=17/1701
     right=%%any
     rightprotoport=17/%%any"""

xl2tpd_content="""[global]
listen-addr = $(hostname -I)
ipsec saref = yes
[lns default]
ip range = 192.168.100.128-192.168.100.254
local ip = 192.168.100.99
require chap = yes
refuse pap = yes
require authentication = yes
name = LinuxVPNserver
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes"""

xl2tpd_option_content="""ipcp-accept-local
ipcp-accept-remote
ms-dns  8.8.8.8
ms-dns  8.8.4.4
noccp
noauth
crtscts
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
lock
proxyarp
connect-delay 5000"""

# Install xl2tpd
yum install epel-release -y
yum install xl2tpd libreswan -y

printf "$sysctl_content" >> /etc/sysctl.conf
sysctl -p

printf "$l2tp_psk_content" >> /etc/ipsec.d/l2tp_psk.conf

read -p "Please Input pre-shared key(PSK): " shared_key
echo "$(hostname -I) %any: PSK \"$shared_key\"" >> /etc/ipsec.secrets

# Turn of IPSec
ipsec setup start
ipsec verify
systemctl enable ipsec

# Configure xl2tpd
mv /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf.old
mv /etc/ppp/options.xl2tpd /etc/ppp/options.xl2tpd.old
printf "$xl2tpd_content" > /etc/xl2tpd/xl2tpd.conf
printf "$xl2tpd_option_content" > /etc/ppp/options.xl2tpd

read -p "Please Input Username: " username
read -p "Please Input Password: " password
echo -e "$username * $password *\n" >> /etc/ppp/chap-secrets

# Start xl2tpd
systemctl start xl2tpd
systemctl enable xl2tpd
systemctl status xl2tpd

# Set firewall
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p gre -j ACCEPT
firewall-cmd --permanent --zone=public --add-masquerade
firewall-cmd --permanent --add-rich-rule='rule protocol value="esp" accept'
firewall-cmd --permanent --add-rich-rule='rule protocol value="ah" accept'
firewall-cmd --permanent --add-port=1701/udp
firewall-cmd --permanent --add-port=500/udp 
firewall-cmd --permanent --add-port=4500/udp 
firewall-cmd --permanent --add-service="ipsec"
firewall-cmd --reload

# Set iptable
interface_d=`ip route get 8.8.8.8 | sed -nr 's/.*dev ([^\ ]+).*/\1/p'`
iptables -A INPUT -p gre -j ACCEPT
iptables -A OUTPUT -p gre -j ACCEPT
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -s 192.168.100.0/24 -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o $interface_d -j MASQUERADE
iptables-save > /etc/sysconfig/iptables

setsebool -P daemons_use_tty 1
