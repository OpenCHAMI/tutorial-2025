# Instance Preparation

Once your AMI has launched as an instance, it will use the cloud-int process to install all the OpenCHAMI prerequisites.  This will take about five minutes depending on the status of the internal AWS network and your instance type.  Checking the process list for dnf commands is a reasonable way to ascertain if the process is complete.  You can also check the cloud-init logs in `/var/log/cloud-init`.  Errors are often logged while cloud-init continues without failure.

## Install Registry CLI tool

We will be using a registry for storing our images, and we need to be able to interact with it somehow so we will be using [`regctl`](https://github.com/regclient/regclient/tree/main/cmd/regctl).

```bash
sudo curl -fSL https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64 -o /usr/local/bin/regctl
sudo chmod +x /usr/local/bin/regctl
```

## Set up NFS for Shared Filesystems

Create `/opt/nfsroot` to store our images

```bash
sudo mkdir /srv/nfs
sudo chown rocky: /srv/nfs
```

Create `/etc/exports` with the following contents to export the `/srv/nfs` directory for use by our compute nodes

```
/srv/nfs *(ro,no_root_squash,no_subtree_check,noatime,async,fsid=0)
```

Reload the NFS daemon

```bash
modprobe -r nfsd
sudo modprobe nfsd
```

## Update /etc/hosts

**Add the demo hostname to /etc/hosts so that all the certs and urls work**
   ```bash
   echo "172.16.0.253 demo.openchami.cluster" | sudo tee -a /etc/hosts > /dev/null
   ```

## Set Up Image Infrastructure

### Directories for Image Data

- Create a local directory for storing the container images

  ```bash
  sudo mkdir -p /data/oci
  sudo chown -R rocky: /data/oci
  ```

- Create a local directory for storing SquashFS images

  ```bash
  sudo mkdir -p /data/minio
  sudo chown -R rocky: /data/minio
  ```

### Local Image Registry

This is where OCI-formatted images will live so that they can serve as parents for children image layers.

- Create a quadlet for the registry at `/etc/containers/systemd/registry.container`:

  ```systemd
  [Unit]
  Description=Image OCI Registry
  After=network-online.target
  Requires=network-online.target

  [Container]
  ContainerName=registry
  HostName=registry
  Image=docker.io/library/registry:latest
  Volume=/data/oci:/var/lib/registry:z
  PublishPort=5000:5000

  [Service]
  TimeoutStartSec=0
  Restart=always

  [Install]
  WantedBy=default.target
  ```

- Start the registry:

  ```bash
  sudo systemctl daemon-reload
  sudo systemctl start registry
  ```

- Disable TLS for registry in registry CLI:
  ```bash
  regctl registry set --tls disabled demo.openchami.cluster:5000
  ```

- Set up the working directories we'll use for images

  SELinux treats home directories specially.  To avoid cgroups conflicting with SELinux enforcement, we set up a working directory outside our home directory.
  ```bash
  sudo mkdir -p /opt/workdir
  sudo chown -R rocky: /opt/workdir
  cd /opt/workdir
  ```

### Local Image S3 Instance

Create `/etc/containers/systemd/minio.service`:

```systemd
[Unit]
Description=Minio S3
After=local-fs.target network-online.target
Wants=local-fs.target network-online.target

[Container]
ContainerName=minio-server
Image=docker.io/minio/minio:latest
# Volumes
Volume=/data/minio:/data

# Ports
PublishPort=172.16.0.253:9090:9000
PublishPort=172.16.0.253:9091:9001

# Environemnt Variables
Environment=MINIO_ROOT_USER=admin
Environment=MINIO_ROOT_PASSWORD=admin123

# Command to run in container
Exec=server /data --console-address :9001

[Service]
Restart=always
ExecStartPost=podman exec minio-server bash -c 'until curl -sI http://localhost:9000 > /dev/null; do sleep 1; done; mc alias set local http://localhost:9000 admin admin123; mc mb local/efi; mc mb local/boot-images;mc anonymous set download local/efi;mc anonymous set download local/boot-images'

[Install]
# Start by default on boot
WantedBy=multi-user.target default.target
```

Reload SystemD and start the service:

```
sudo systemctl daemon-reload
sudo systemctl start minio
```

To verify it works, we should be able to cURL the base endpoint:

```bash
curl http://172.16.0.253:9090
```

and get an Access Denied:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>AccessDenied</Code><Message>Access Denied.</Message><Resource>/</Resource><RequestId>1838AD5A9941A638</RequestId><HostId>dd9025bab4ad464b049177c95eb6ebf374d3b3fd1af9251148b658df7ac2e3e8</HostId></Error>
```

After we've verified it works, let's enable the service:

Now, we need to setup our S3 client, `s3cmd`. Create the following file:

**`~/.s3cfg`**

```
# Setup endpoint
host_base = demo.openchami.cluster:9090
host_bucket = demo.openchami.cluster:9090
bucket_location = us-east-1
use_https = False

# Setup access keys
access_key = admin
secret_key = admin123

# Enable S3 v4 signature APIs
signature_v2 = False
```

To make sure it works, list the S3 buckets:

```bash
s3cmd ls
```

We should see the two that got created:

```
2025-04-22 15:24  s3://boot-images
2025-04-22 15:24  s3://efi
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

### Start OpenCHAMI

Even though OpenCHAMI runs as a collection of containers, the podman integration with systemd allows us to start, stop, and trace OpenCHAMI as a set of dependent services through the `openchami.target` unit.

```bash
sudo systemctl start openchami.target
systemctl list-dependencies openchami.target
```

### Trust Root CA Certificate

When the OpenCHAMI services started for the first time, a root CA certificate was generated in order to support TLS on the haproxy gateway. We need to add this certificate to the trusted anchors:

```
sudo podman run --rm --network openchami-cert-internal docker.io/curlimages/curl -sk https://step-ca:9000/roots.pem | sudo tee /etc/pki/ca-trust/source/anchors/ochami.pem
sudo update-ca-trust
```

### Autorenewal of Certificates

By default, the TLS certificate expires after 24 hours, so we need to set up a renewal mechanism. One way to do that is with a Systemd timer. Create the following Systemd unit files:

**/etc/systemd/system/ochami-cert-renewal.timer:**

```systemd
[Unit]
Description=Renew OpenCHAMI certificates daily

[Timer]
OnBootSec=30sec
OnUnitActiveSec=1d

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
sudo systemctl start ochami-cert-renewal
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