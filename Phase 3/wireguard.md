# Using Wireguard with CLoud-Init

The OpenCHAMI cloud-init metadata server includes a feature to enable a wireguard tunnel **before** running cloud-init.  


## Create a systemd override file for cloud-init

```ini
[Service]
PassEnvironment=ochami_wg_ip
ExecStartPre=/usr/local/bin/ochami-wg-cloud-init-setup.sh
ExecPostStop=/bin/bash -c "ip link delete wg0"
```

## Create a script to activate wireguard

```bash
#!/bin/sh
set -e -o pipefail

# As configured in systemd, we expect to inherit the "ochami_wg_url" cmdline
# parameter as an env var. Exit if this is not the case.
if [ -z "${ochami_wg_ip}" ];
then
    echo "ERROR: Failed to find the 'ochami_wg_url' environment variable."
    echo "It should be specified on the kernel cmdline, and will be inherited from there."
    if [ -f "/etc/cloud/cloud.cfg.d/ochami.cfg" ];
    then
        echo "Removing ochami-specific cloud-config; cloud-init will use other defaults"
        rm /etc/cloud/cloud.cfg.d/ochami.cfg
    else
        echo "Not writing ochami-specific cloud-config; cloud-init will use other defaults"
    fi
    exit 0
fi
echo "Found OpenCHAMI cloud-init URL '${ochami_wg_ip}'"
echo "!!!!Starting pre cloud-init config!!!!"

echo "Loading wireguard kernel mod"
modprobe wireguard

echo "Generating Wireguard keys"
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key

echo "Making Request to configure wireguard tunnel"
PUBLIC_KEY=$(cat /etc/wireguard/public.key)
PAYLOAD="{ \"public_key\": \"${PUBLIC_KEY}\" }"
WG_PAYLOAD=$(curl -s -X POST -d "${PAYLOAD}" http://${ochami_wg_ip}:27777/cloud-init/wg-init)

echo $WG_PAYLOAD | jq

CLIENT_IP=$(echo $WG_PAYLOAD | jq -r '."client-vpn-ip"')
SERVER_IP=$(echo $WG_PAYLOAD | jq -r '."server-ip"' | awk -F'/' '{print $1}')
SERVER_PORT=$(echo $WG_PAYLOAD | jq -r '."server-port"')
SERVER_KEY=$(echo $WG_PAYLOAD | jq -r '."server-public-key"')

echo "Setting up local wireguard interface"
echo "Adding wg0 link"
ip link add dev wg0 type wireguard
echo "Adding ip address ${CLIENT_IP}/32"
ip address add dev wg0 ${CLIENT_IP}/32
echo "Setting the private key"
wg set wg0 private-key /etc/wireguard/private.key
echo "Bringing up the wg0 link"
ip link set wg0 up
echo "Setting up the peer with the server"
wg set wg0 peer ${SERVER_KEY} allowed-ips ${SERVER_IP}/32 endpoint ${ochami_wg_ip}:$SERVER_PORT
rm /etc/wireguard/private.key
rm /etc/wireguard/public.key
```

## Add the scripts to your image

```yaml
copyfiles:
  - src: '/opt/workdir/images/files/cloud-init-override.conf'
    dest: '/etc/systemd/system/cloud-init.service.d/override.conf'
  - src: '/opt/workdir/images/files/ochami-ci-setup.sh'
    dest: '/usr/local/bin/ochami-ci-setup.sh'

```

## Restart cloud-init-server with wireguard