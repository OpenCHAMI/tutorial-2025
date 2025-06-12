# Phase I — Platform Setup

1. **Instance Preparation**
   - Host packages, kernel modules, cgroups, bridge setup, storage directories setup
   - Deploy MinIO, nginx, and registry
   - Checkpoints:
     - `systemctl status minio`
     - `systemctl status registry`
2. **OpenCHAMI & Core Services**
   - Install OpenCHAMI RPMs
   - Deploy internal Certificate Authority and import signing certificate
   - Checkpoints:
     - `ochami bss status`
     - `systemctl list-dependencies openchami.target`

---

## Contents

- [Phase I — Platform Setup](#phase-i--platform-setup)
  - [Contents](#contents)
  - [Set Up Storage Directories](#set-up-storage-directories)
  - [Set Up Internal Network and Hostnames](#set-up-internal-network-and-hostnames)
    - [Create and Start Internal Network](#create-and-start-internal-network)
    - [Update `/etc/hosts`](#update-etchosts)
  - [Enable Non-OpenCHAMI Services](#enable-non-openchami-services)
    - [Minio](#minio)
    - [Container Registry](#container-registry)
    - [Reload Systemd](#reload-systemd)
  - [Checkpoint](#checkpoint)
  - [Install OpenCHAMI](#install-openchami)
  - [Initialize/Trust the OpenCHAMI Certificate Auhority](#initializetrust-the-openchami-certificate-auhority)
  - [Start OpenCHAMI](#start-openchami)
    - [Service Configuration](#service-configuration)
  - [Install and Configure OpenCHAMI Client](#install-and-configure-openchami-client)
    - [Installation](#installation)
    - [Configuration](#configuration)
  - [Generating Authentication Token](#generating-authentication-token)
  - [Checkpoint](#checkpoint-1)

---

## Set Up Storage Directories

Our tutorial uses S3 to serve the system images (in SquashFS format) for the diskless VMs. A container registry is also used to store system images (in OCI format) for reuse in other image layers (we'll go over this later).
They all need separate directories.

Create a local directory for storing the container images:

```bash
sudo mkdir -p /data/oci
sudo chown -R rocky: /data/oci
```

Create a local directory for S3 access to images:

```bash
sudo mkdir -p /data/s3
sudo chown -R rocky: /data/s3
```

SELinux treats home directories specially. To avoid cgroups conflicting with SELinux enforcement, we set up a working directory outside our home directory:

```bash
sudo mkdir -p /opt/workdir
sudo chown -R rocky: /opt/workdir
cd /opt/workdir
```

## Set Up Internal Network and Hostnames

The containers expect that an internal network be set up with a domain name for our OpenCHAMI services.

### Create and Start Internal Network

```bash
sudo sysctl -w net.ipv4.ip_forward=1
cat <<EOF > openchami-net.xml
<network>
  <name>openchami-net</name>
  <bridge name="virbr-openchami" />
  <forward mode='route'/>
   <ip address="172.16.0.254" netmask="255.255.255.0">
   </ip>
</network>
EOF

sudo virsh net-define openchami-net.xml
sudo virsh net-start openchami-net
sudo virsh net-autostart openchami-net
```

### Update `/etc/hosts`

**Add the demo domain to `/etc/hosts` so that all the certs and URLs work**
   ```bash
   echo "172.16.0.254 demo.openchami.cluster" | sudo tee -a /etc/hosts > /dev/null
   ```


## Enable Non-OpenCHAMI Services

### Minio

For our S3 gateway, we use [Minio](https://github.com/minio/minio) which we'll define as a quadlet and start.

Like all the OpenCHAMI services, we create a container definition in `/etc/containers/systemd/`.

```yaml
# minio.container
[Unit]
Description=Minio S3
After=local-fs.target network-online.target
Wants=local-fs.target network-online.target

[Container]
ContainerName=minio-server
Image=docker.io/minio/minio:latest
# Volumes
Volume=/data/s3:/data:Z

# Ports
PublishPort=9000:9000
PublishPort=9091:9001

# Environemnt Variables
Environment=MINIO_ROOT_USER=admin
Environment=MINIO_ROOT_PASSWORD=admin123

# Command to run in container
Exec=server /data --console-address :9001

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
```

### Container Registry

For our OCI container registry, we use the standard docker registry.  Once again, deployed as a quadlet.

```yaml
# registry.container
[Unit]
Description=Image OCI Registry
After=network-online.target
Requires=network-online.target

[Container]
ContainerName=registry
HostName=registry
Image=docker.io/library/registry:latest
Volume=/data/oci:/var/lib/registry:Z
PublishPort=5000:5000

[Service]
TimeoutStartSec=0
Restart=always

[Install]
WantedBy=multi-user.target
```

### Reload Systemd

Reload Systemd to update it with our new changes and then start the services:

```bash
sudo systemctl daemon-reload
sudo systemctl start minio.service
sudo systemctl start registry.service
```

## Checkpoint

```bash
systemctl status minio
systemctl status registry
```

---

## Install OpenCHAMI

Install the signed RPM from the [openchami/release](https://github.com/openchami/release) repository with verification using a [Public Gist](https://gist.github.com/alexlovelltroy/96bfc8bb6f59c0845617a0dc659871de).

1. Identifies the latest release rpm
1. Downloads the public signing key for OpenCHAMI
1. Downloads the rpm
1. Verifies the signature
1. Installs the RPM

Run the commands below **in the `/opt/workdir` directory.**

```bash
API_URL="https://api.github.com/repos/${OWNER}/${REPO}/releases/latest"
release_json=$(curl -s "$API_URL")
rpm_url=$(echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .browser_download_url' | head -n 1)
rpm_name=$(echo "$release_json" | jq -r '.assets[] | select(.name | endswith(".rpm")) | .name' | head -n 1)
curl -L -o "$rpm_name" "$rpm_url"
sudo rpm -Uvh "$rpm_name"
```

## Initialize/Trust the OpenCHAMI Certificate Auhority

OpenCHAMI includes a minimal open source certificate authority from [smallstep](https://smallstep.com/).  The included automation initialized the CA on first startup.  We can immediately download a certificate into the system trust bundle on the host for trusting all subsequent OpenCHAMI certificates.  Notably, the certificate authority features ACME for automatic certificate rotation.

Start the certificate authority:

```bash
sudo systemctl start step-ca
systemctl status step-ca
```

Import the root certificate into the system trust bundle:

```bash
sudo podman run --rm --network openchami-cert-internal docker.io/curlimages/curl -sk https://step-ca:9000/roots.pem | sudo tee /etc/pki/ca-trust/source/anchors/ochami.pem
sudo update-ca-trust
```

## Start OpenCHAMI

Even OpenCHAMI runs as a collection of containers. Podman's integration with Systemd allows us to start, stop, and trace OpenCHAMI as a set of dependent services through the `openchami.target` unit.

```bash
sudo systemctl start openchami.target
systemctl list-dependencies openchami.target
```

> [!TIP]
> If the `openchami.target` fails because of a dependency issue, try looking at the logs with `journalctl -xe` or `journalctl -eu $container_name` for more information.

### Service Configuration

The OpenCHAMI release RPM is created with sensible default configurations for this tutorial and all configuration files are included in the `/etc/openchami` directory.  To understand each one in detail, review the [service_configuration](service_configuration.md) instructions

## Install and Configure OpenCHAMI Client

The [`ochami` CLI](https://github.com/OpenCHAMI/ochami) provides us an easy way to interact with the OpenCHAMI services.

### Installation

We can install the latest RPM with the following:

```bash
latest_release_url=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.rpm")) | .browser_download_url')
curl -L "${latest_release_url}" -o ochami.rpm
sudo dnf install -y ./ochami.rpm
```

As a sanity check, check the version to make sure it is installed properly:

```bash
ochami version
```

The output should look something like:

```
Version:    0.3.3
Tag:        v0.3.3
Branch:     HEAD
Commit:     c625344859b3dcfcdc8e43f74b4eafeae66d4fd8
Git State:  clean
Date:       2025-04-28T18:34:49Z
Go:         go1.24.2
Compiler:   gc
Build Host: fv-az1618-941
Build User: runner
```

### Configuration

To configure `ochami` to be able to communicate with our cluster, we need to create a config file. We can create one in one fell swoop with:

```bash
ochami config cluster set --user --default demo cluster.uri https://demo.openchami.cluster:8443
```

This will create a config file at `~/.config/ochami/config.yaml`. We can check that `ochami` is reading it properly with:

```bash
ochami config show
```

We should see:

```yaml
clusters:
    - cluster:
        uri: https://demo.openchami.cluster:8443
      name: demo
default-cluster: demo
log:
    format: rfc3339
    level: warning
```

Now we should be able to communicate with our cluster. Let's make sure by checking the status of one of the services:

```bash
ochami bss status
```

We should get:

```json
{"bss-status":"running"}
```

Voilà!

> [!TIP]
> If you receive an error related to TLS when runing `ochami bss status`, then try re-running `acme-deploy` and restarting the `haproxy` service.
>
> ```bash
> systemctl restart acme-deploy
> systemctl restart haproxy
> ```


## Generating Authentication Token

In order to interact with protected endpoints, we will need to generate a JSON Web Token (JWT, pronounced _jot_). `ochami` reads an environment variable named `<CLUSTER_NAME>_ACCESS_TOKEN` where `<CLUSTER_NAME>` is the configured name of the cluster in all capitals, `DEMO` in our case.

Since we aren't using an external identity provider, we will use OpenCHAMI's internal one to generate a token. The RPM we installed comes with some shell functions that allow us to do this.

```bash
export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
```

Note that `sudo` is needed because the containers are running as root and so if `sudo` is omitted, the containers will not be found.

OpenCHAMI tokens last for an hour by default. Whenever one needs to be regenerated, run the above command.

## Checkpoint

```bash
systemctl list-dependencies openchami.target
ochami bss status
ochami smd status
```
should yield:
```bash
openchami.target
● ├─bss.service
● ├─cloud-init-server.service
● ├─coresmd.service
● ├─haproxy.service
● ├─hydra.service
● ├─opaal-idp.service
● ├─opaal.service
● ├─postgres.service
● ├─smd.service
● └─step-ca.service
{"bss-status":"running"}{"code":0,"message":"HSM is healthy"}
```
