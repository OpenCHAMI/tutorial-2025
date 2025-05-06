# Instance Preparation

## Contents

- [Instance Preparation](#instance-preparation)
  - [Contents](#contents)
- [Introduction](#introduction)
- [Preparation Steps](#preparation-steps)
  - [Set Up NFS for Shared Filesystems](#set-up-nfs-for-shared-filesystems)
  - [Update `/etc/hosts`](#update-etchosts)
  - [Set Up Image Infrastructure](#set-up-image-infrastructure)
    - [Directories for Image Data](#directories-for-image-data)
    - [Local Image Registry](#local-image-registry)
    - [Install Registry CLI tool](#install-registry-cli-tool)
    - [Working Directory](#working-directory)
    - [Local Image S3 Instance](#local-image-s3-instance)
    - [Install S3 Client](#install-s3-client)
  - [Install OpenCHAMI Services](#install-openchami-services)
    - [Install Command](#install-command)
    - [Review Installed Containers](#review-installed-containers)
    - [Configure CoreDHCP](#configure-coredhcp)
    - [Configure Cloud-Init](#configure-cloud-init)
    - [Start OpenCHAMI](#start-openchami)
    - [Trust Root CA Certificate](#trust-root-ca-certificate)
    - [Autorenewal of Certificates](#autorenewal-of-certificates)
  - [Install and Configure OpenCHAMI Client](#install-and-configure-openchami-client)
    - [Installation](#installation)
    - [Configuration](#configuration)
  - [Generating Authentication Token](#generating-authentication-token)

# Introduction

Once your AMI has launched as an instance, it will use the cloud-int process to install all the OpenCHAMI prerequisites.  This will take about five minutes depending on the status of the internal AWS network and your instance type.  Checking the process list for dnf commands is a reasonable way to ascertain if the process is complete.  You can also check the cloud-init logs in `/var/log/cloud-init`.  Errors are often logged while cloud-init continues without failure.

## Install Prerequisites for non-tutorial instances

If you are using a tutorial instance from AWS, this is handled within the startup of the instance.  If not, you may run these commands on your own Rocky9 host to get it to the right state for the tutorial

```bash
sudo dnf update -y
sudo dnf install -y \
  epel-release \
  libvirt \
  qemu-kvm \
  virt-install \
  virt-manager \
  dnsmasq \
  podman \
  buildah \
  git \ 
  vim \
  ansible-core \
  openssl \
  nfs-utils \
  s3cmd 
sudo systemctl enable --now libvirtd
sudo systemctl start libvirtd
sudo newgrp libvirt
sudo usermod -aG libvirt rocky
```

## Set up the node filesystems

Our tutorial uses NFS to share the system images for the diskless VMs.  We also use an S3 store and a container registry as part of our build process for system images.  They all need separate directories.

Create `/opt/nfsroot` to serve our images

```bash
sudo mkdir /srv/nfs
sudo chown rocky: /srv/nfs
```

Create a local directory for storing the container images

```bash
sudo mkdir -p /data/oci
sudo chown -R rocky: /data/oci
```

Create a local directory for s3 access to images

```bash
sudo mkdir -p /data/minio
sudo chown -R rocky: /data/minio
```

SELinux treats home directories specially. To avoid cgroups conflicting with SELinux enforcement, we set up a working directory outside our home directory.

```bash
sudo mkdir -p /opt/workdir
sudo chown -R rocky: /opt/workdir
cd /opt/workdir
```

## Set up the internal networks our containers expect and internal hostnames

```bash
cat <<EOF > openchami-net.xml
<network>
  <name>openchami-net</name>
  <bridge name="virbr-openchami" />
  <forward mode='nat'/>
   <ip address="172.16.0.254" netmask="255.255.255.0">
   </ip>
</network>
EOF

sudo virsh net-define openchami-net.xml
sudo virsh net-start openchami-net
sudo virsh net-autostart openchami-net
```

### Update /etc/hosts 

**Add the demo hostname to /etc/hosts so that all the certs and urls work**
   ```bash
   echo "127.0.0.1 demo.openchami.cluster" | sudo tee -a /etc/hosts > /dev/null
   ```


## Enable our non-openchami services

For NFS, we need to update the /etc/exports file and then reload the kernel nfs daemon

  - Create `/etc/exports` with the following contents to export the `/srv/nfs` directory for use by our compute nodes
    ```bash
    /srv/nfs *(ro,no_root_squash,no_subtree_check,noatime,async,fsid=0)
    ```

  - Reload the nfs daemon
    ```bash
    sudo modprobe -r nfsd && sudo modprobe nfsd
    ```

### minio

For our S3 gateway, we use minio which we'll define as a quadlet and start.

Like all the openchami services, we create a container definition in `/etc/containers/systemd/`.  Note that minio makes some network assumptions in this file.

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
Volume=/data/minio:/data:Z

# Ports
PublishPort=172.16.0.254:9090:9000
PublishPort=172.16.0.254:9091:9001

# Environemnt Variables
Environment=MINIO_ROOT_USER=admin
Environment=MINIO_ROOT_PASSWORD=admin123

# Command to run in container
Exec=server /data --console-address :9001

[Service]
Restart=always
ExecStartPost=podman exec minio-server bash -c 'until curl -sI http://localhost:9000 > /dev/null; do sleep 1; done; mc alias set local http://localhost:9000 admin admin123; mc mb local/efi; mc mb local/boot-images;mc anonymous set download local/efi;mc anonymous set download local/boot-images'

[Install]
WantedBy=multi-user.target
```

### container registry

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

### Reload systemd units to pick up the changes and start the services

```bash
sudo systemctl daemon-reload
sudo systemctl start minio.service
sudo systemctl start registry.service
```



## Install OpenCHAMI Services

There are several ways to install and activate OpenCHAMI on a head node.  For this tutorial, we will use the signed RPM from the [openchami/release](https://github.com/openchami/release) repository.  This RPM mainly exists to hold systemd unit filed which run containers as podman quadlets.  As part of the installation, the RPM pulls all the OpenCHAMI containers from the github container registry.  The RPM itself is signed and each container is attested publicly through Sigstore tooling integrated by GitHub.  You can read more about the attestation process in the [Github Documentation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds).

To make things easier for the tutorial, we have created a [bash script](https://gist.github.com/alexlovelltroy/96bfc8bb6f59c0845617a0dc659871de) that:

1. identifies the latest release rpm
1. downloads the public signing key for OpenCHAMI
1. downloads the rpm
1. verifies the signature
1. installs the RPM

### Install Command
```bash
curl -fsSL https://gist.githubusercontent.com/alexlovelltroy/96bfc8bb6f59c0845617a0dc659871de/raw | bash
```

### Review Installed Containers

The post-install script for the RPM pulls all the official containers from the github container registry and stores them for use later.  You can review them with `podman`.

```bash
sudo podman images
```

### Configure CoreDHCP

Check which interface has the internal IP of 172.16.0.254. Open `/etc/openchami/configs/coredhcp.yaml` and replace `%virbr-openchami` in the `listen` directive with it. We will also need to change the `server_id`, `dns`, and `router` entries to be this IP, as well as the IP in the `coresmd` directive.

So, if our listen interface is `enp2s0`, then our config file will look like this:

```yaml
server4:
  listen:
    - "%enp2s0"
  plugins:
    - server_id: 172.16.0.254
    - dns: 172.16.0.254
    - router: 172.16.0.254
    - netmask: 255.255.255.0
    - coresmd: https://demo.openchami.cluster:8443 http://172.16.0.254:8081 /root_ca/root_ca.crt 30s 1h false
    - bootloop: /tmp/coredhcp.db default 5m 172.16.0.200 172.16.0.250
```

### Configure Cloud-Init

We need to enable node impersonation in the cloud-init server so that we can use the `ochami` tool to view node config. To do that, edit `/etc/containers/systemd/cloud-init-server.container` and add:

```systemd
Exec=/usr/local/bin/cloud-init-server --impersonation=true
```

under the `[Container]` section.

### Initialize and Trust the Internal Root CA Certificate

When the Certificate Authority is started for the first time, a root CA certificate was generated in order to support TLS on the haproxy gateway. 

```bash
sudo systemctl start step-ca.service
```


We need to add this certificate to the trusted anchors:

```bash
sudo podman run --rm --network openchami-cert-internal docker.io/curlimages/curl -sk https://step-ca:9000/roots.pem | sudo tee /etc/pki/ca-trust/source/anchors/ochami.pem
sudo update-ca-trust
```

### Start OpenCHAMI

Even though OpenCHAMI runs as a collection of containers, the podman integration with systemd allows us to start, stop, and trace OpenCHAMI as a set of dependent services through the `openchami.target` unit.

```bash
sudo systemctl start openchami.target
systemctl list-dependencies openchami.target
```



### Autorenewal of Certificates

By default, the TLS certificate expires after 24 hours, so we need to set up a renewal mechanism. One way to do that is with a Systemd timer. Create the following Systemd unit files:

**/etc/systemd/system/ochami-cert-renewal.timer:**

```systemd
[Unit]
Description=Renew OpenCHAMI certificates daily

[Timer]
OnUnitActiveSec=1d
Persistent=true

[Install]
WantedBy=timers.target
```

**/etc/systemd/system/ochami-cert-renewal.service:**

```systemd
[Unit]
Description=Renew OpenCHAMI certificates

[Service]
Type=oneshot
ExecStart=systemctl restart acme-deploy
ExecStart=systemctl restart acme-register
ExecStart=systemctl restart haproxy
StandardOutput=journal

[Install]
WantedBy=multi-user.target
```

Then, reload Systemd and run the service file once to make sure renewal works:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ochami-cert-renewal.timer
sudo systemctl start ochami-cert-renewal
```

Make sure the timer shows up:

```bash
systemctl list-timers ochami-cert-renewal.timer
```

We should see:

```
NEXT                        LEFT     LAST PASSED UNIT                      ACTIVATES
Tue 2025-04-29 09:18:51 MDT 23h left -    -      ochami-cert-renewal.timer ochami-cert-renewal.service

1 timers listed.
Pass --all to see loaded but inactive timers, too.
```

## Install and Configure OpenCHAMI Client

The [`ochami` CLI](https://github.com/OpenCHAMI/ochami) provides us an easy way to interact with the OpenCHAMI services.

### Installation

We can install the latest RPM with the following:

```bash
latest_release_url=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.rpm")) | .browser_download_url')
curl -L "${latest_release_url}" -o ochami.rpm
sudo dnf install ./ochami.rpm
```

As a sanity check, check the version to make sure it is installed properly:

```bash
ochami version
```

The output should look something like:

```
Version:    0.3.2
Tag:        v0.3.2
Branch:     HEAD
Commit:     2a165a84e0ce51c0b8c88861e95e80ca0aed009c
Git State:  clean
Date:       2025-04-11T01:58:14Z
Go:         go1.24.2
Compiler:   gc
Build Host: fv-az1112-474
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

## Generating Authentication Token

In order to interact with protected endpoints, we will need to generate a JSON Web Token (JWT, pronounced _jot_). `ochami` reads an environment variable named `<CLUSTER_NAME>_ACCESS_TOKEN` where `<CLUSTER_NAME>` is the configured name of the cluster in all capitals, `DEMO` in our case.

Since we aren't using an external identity provider, we will use OpenCHAMI's internal one to generate a token. The RPM we installed comes with some shell functions that allow us to do this.

```bash
export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
```

Note that `sudo` is needed because the containers are running as root and so if `sudo` is omitted, the containers will not be found.

OpenCHAMI tokens last for an hour by default. Whenever one needs to be regenerated, run the above command.