#!/bin/bash
# Run this on the DNS VM (Ubuntu/Debian minimal)
# VM specs: 1 vCPU, 512MB RAM, 10GB disk
#
# Before running, fill in the IP addresses below for your environment.

set -e

# --- Configuration (fill these in) ---
API_VIP="<API_VIP>"
INGRESS_VIP="<INGRESS_VIP>"
MASTER0_IP="<MASTER0_IP>"
MASTER1_IP="<MASTER1_IP>"
MASTER2_IP="<MASTER2_IP>"

echo "=== Installing dnsmasq ==="
sudo apt-get update && sudo apt-get install -y dnsmasq

echo "=== Configuring dnsmasq ==="
cat <<EOF | sudo tee /etc/dnsmasq.conf
# Listen on all interfaces
listen-address=0.0.0.0
bind-interfaces

# Upstream DNS
server=8.8.8.8
server=8.8.4.4

# OpenShift cluster records
address=/api.ocp.local/${API_VIP}
address=/api-int.ocp.local/${API_VIP}
address=/apps.ocp.local/${INGRESS_VIP}

# Node records
host-record=master0.ocp.local,${MASTER0_IP}
host-record=master1.ocp.local,${MASTER1_IP}
host-record=master2.ocp.local,${MASTER2_IP}
EOF

echo "=== Disabling systemd-resolved ==="
sudo systemctl stop systemd-resolved 2>/dev/null || true
sudo systemctl disable systemd-resolved 2>/dev/null || true

echo "=== Setting resolv.conf ==="
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

echo "=== Enabling and starting dnsmasq ==="
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq

echo "=== Verifying ==="
getent hosts api.ocp.local
getent hosts console-openshift-console.apps.ocp.local

echo ""
echo "DNS VM is ready."
echo "api.ocp.local        -> ${API_VIP}"
echo "*.apps.ocp.local     -> ${INGRESS_VIP}"
echo "master0-2.ocp.local  -> ${MASTER0_IP}, ${MASTER1_IP}, ${MASTER2_IP}"
