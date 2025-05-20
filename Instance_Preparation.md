# Instance Preparation

## Contents

- [Instance Preparation](#instance-preparation)
  - [Contents](#contents)
- [Introduction](#introduction)
  - [Install Prerequisites for non-tutorial instances](#install-prerequisites-for-non-tutorial-instances)
  - [Set up the node filesystems](#set-up-the-node-filesystems)
  - [Set up the internal networks our containers expect and internal hostnames](#set-up-the-internal-networks-our-containers-expect-and-internal-hostnames)
    - [Update /etc/hosts](#update-etchosts)
  - [Enable our non-openchami services](#enable-our-non-openchami-services)
    - [minio](#minio)
    - [container registry](#container-registry)
    - [Webserver for boot artifacts](#webserver-for-boot-artifacts)
    - [Reload systemd units to pick up the changes and start the services](#reload-systemd-units-to-pick-up-the-changes-and-start-the-services)

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
```

Start the libvirtd daemon and add the rocky user to a new libvirt group.

```bash
sudo systemctl enable --now libvirtd
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
   echo "172.16.0.254 demo.openchami.cluster" | sudo tee -a /etc/hosts > /dev/null
   ```


## Enable our non-openchami services

For NFS, we need to update the /etc/exports file and then reload the kernel nfs daemon

  - Create the `/etc/exports` file with the following contents to export the `/srv/nfs` directory for use by our compute nodes
    ```bash
    /srv/nfs *(ro,no_root_squash,no_subtree_check,noatime,async,fsid=0)
    ```

  - Reload the nfs daemon
    ```bash
    sudo modprobe -r nfsd && sudo modprobe nfsd
    ```

### minio

For our S3 gateway, we use minio which we'll define as a quadlet and start.

Like all the openchami services, we create a container definition in `/etc/containers/systemd/`.

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
PublishPort=9090:9000
PublishPort=9091:9001

# Environemnt Variables
Environment=MINIO_ROOT_USER=admin
Environment=MINIO_ROOT_PASSWORD=admin123

# Command to run in container
Exec=server /data --console-address :9001

[Service]
Restart=always
ExecStartPost=podman exec minio-server bash -c 'until curl -sI http://localhost:9090 > /dev/null; do sleep 1; done; mc alias set local http://localhost:9090 admin admin123; mc mb local/efi; mc mb local/boot-images;mc anonymous set download local/efi;mc anonymous set download local/boot-images'

[Install]
WantedBy=multi-user.target
```

> [!NOTE]
> `minio` makes some network assumptions in this file. Change it accordingly to fit your setup or use case.

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

### Webserver for boot artifacts

We expose our NFS directory over https as well to make it easy to serve boot artifacts.

```yaml
# nginx.container
[Unit]
Description=Serve /srv/nfs over HTTP
After=network-online.target
Wants=network-online.target

[Container]
ContainerName=nginx
Image=docker.io/library/nginx:1.28-alpine
Volume=/srv/nfs:/usr/share/nginx/html:Z
PublishPort=80:80

[Service]
TimeoutStartSec=0
Restart=always
```

### Reload systemd units to pick up the changes and start the services

```bash
sudo systemctl daemon-reload
sudo systemctl start minio.service
sudo systemctl start registry.service
sudo systemctl start nginx.service
```
