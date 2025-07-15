# Phase II — Boot & Image Infrastructure

3. **Static Discovery & SMD Population**
   - Anatomy of `nodes.yaml`, `ochami discover`
   - Checkpoint: `ochami smd component get | jq '.Components[] | select(.Type == "Node")'`
4. **Image Builder**
   - Define base, compute, debug container layers
   - Build & push to registry/S3
   - Checkpoints:
     - `s3cmd ls -Hr s3://boot-images/`
     - `regctl tag ls demo.openchami.cluster:5000/demo/rocky-base`
5. **PXE Boot Configuration**
   - `boot.yaml`, BSS parameters, virt-install examples
   - Checkpoint: Successful serial console installer
6. **Cloud-Init Configuration**
   - Merging `cloud-init.yaml`, host-group overrides
   - Customizing users, networking, mounts
   - Checkpoint: Inspect `/var/log/cloud-init.log` on node

## 2.0 Contents

- [Phase II — Boot \& Image Infrastructure](#phase-ii--boot--image-infrastructure)
  - [2.0 Contents](#20-contents)
  - [2.1 Libvirt introduction](#21-libvirt-introduction)
  - [2.2 Node Discovery for Inventory](#22-node-discovery-for-inventory)
    - [2.2.1 Dynamic Discovery Overview](#221-dynamic-discovery-overview)
    - [2.2.2 Static Discovery Overview](#222-static-discovery-overview)
      - [2.2.2.1 Anatomy of a Static Discovery File](#2221-anatomy-of-a-static-discovery-file)
    - [2.2.3 "Discover" your nodes](#223-discover-your-nodes)
    - [2.2.4 Checkpoint](#224-checkpoint)
  - [🛑 ***STOP HERE***](#-stop-here)
  - [2.3 Building and Organizing System Images](#23-building-and-organizing-system-images)
    - [2.3.1 Preparing Tools](#231-preparing-tools)
    - [2.3.2 Install and Configure `regctl`](#232-install-and-configure-regctl)
    - [2.3.3 Install and Configure S3 Client](#233-install-and-configure-s3-client)
    - [2.3.4 Create and Configure S3 Buckets](#234-create-and-configure-s3-buckets)
  - [2.4 Building System Images](#24-building-system-images)
    - [2.4.1 Configure The Base Image](#241-configure-the-base-image)
    - [2.4.2 Build the Base Image](#242-build-the-base-image)
    - [2.4.3 Configure the Base Compute Image](#243-configure-the-base-compute-image)
    - [2.4.4 Build the Compute Image](#244-build-the-compute-image)
    - [2.4.5 Configure the Debug Image](#245-configure-the-debug-image)
    - [2.4.6 Build the Debug Image](#246-build-the-debug-image)
    - [2.4.7 Verify Boot Artifact Creation](#247-verify-boot-artifact-creation)
  - [🛑 ***STOP HERE***](#-stop-here-1)
  - [2.5 Managing Boot Parameters](#25-managing-boot-parameters)
    - [2.5.1 Create the Boot Configuration](#251-create-the-boot-configuration)
    - [2.5.2 Set the Boot Configuration](#252-set-the-boot-configuration)
  - [2.6 Boot the Compute Node with the Debug Image](#26-boot-the-compute-node-with-the-debug-image)
    - [2.6.1 Log In to the Compute Node](#261-log-in-to-the-compute-node)
  - [🛑 ***STOP HERE***](#-stop-here-2)
  - [2.7 OpenCHAMI's Cloud-Init Metadata Server](#27-openchamis-cloud-init-metadata-server)
    - [2.7.1 Configure Cluster Meta-Data](#271-configure-cluster-meta-data)
    - [2.7.2 Configure Group-Level Cloud-Init](#272-configure-group-level-cloud-init)
  - [2.7.3 (_OPTIONAL_) Configure Node-Specific Meta-Data](#273-optional-configure-node-specific-meta-data)
    - [2.7.4 Check the Cloud-Init Metadata](#274-check-the-cloud-init-metadata)
  - [2.8 Boot Using the Compute Image](#28-boot-using-the-compute-image)
    - [2.8.1 Switch from the Debug Image to the Compute Image](#281-switch-from-the-debug-image-to-the-compute-image)
    - [2.8.2 Booting the Compute Node](#282-booting-the-compute-node)
    - [2.8.3 Logging Into the Compute Node](#283-logging-into-the-compute-node)
  - [🛑 ***STOP HERE***](#-stop-here-3)

## 2.1 Libvirt introduction

Libvirt is an open-source virtualization management toolkit that provides a unified interface for managing various virtualization technologies, including KVM/QEMU, Xen, VMware, LXC containers, and others. Through its standardized API and set of management tools, libvirt simplifies the tasks of defining, managing, and monitoring virtual machines and networks, regardless of the underlying hypervisor or virtualization platform.

For our tutorial, we leverage a hypervisor which is built-in to the Linux Kernel. The kernel portion is called Kernel-based Virtual Machine (KVM) and the userspace component is included in QEMU.

## 2.2 Node Discovery for Inventory

In order for OpenCHAMI to be useful, the State Management Database (SMD) needs to be populated with node information. This can be done one of two ways: _static_ discovery via [the `ochami` CLI](https://github.com/OpenCHAMI/ochami) or _dynamic_ discovery via [the `magellan` CLI](https://github.com/OpenCHAMI/magellan).

Static discovery is predictable and easily reproduceable, so we will use it in this tutorial.

### 2.2.1 Dynamic Discovery Overview

Dynamic discovery happens via Redfish using `magellan`.

At a high level, `magellan` `scan`s a specified network for hosts running a Redfish server (e.g. BMCs). Once it knows which IPs are using Redfish, the tool can `crawl` each BMC's Redfish structure to get more detailed information about it and `collect` it, then `send` this information to SMD.

When combined with DHCP dynamically handing out IPs, this process can be non-deterministic.

### 2.2.2 Static Discovery Overview

Static discovery happens via `ochami` by giving it a static discovery file. "Discovery" is a bit of a misnomer as nothing is actually discovered. Instead, predefined node data is given to SMD which creates the necessary internal structures to boot nodes.

#### 2.2.2.1 Anatomy of a Static Discovery File

`ochami` adds nodes to SMD through data or a file in YAML syntax (or JSON) that lists node descriptions through a minimal set of node characteristics and a set of interface definitions.

- **name:** User-friendly name of the node stored in SMD.
- **nid:** *Node Identifier*. Unique number identifying node, used in the DHCP-given hostname. Mainly used as a default hostname that can be easily ranged over (e.g. `nid[001-004,006]`).
- **xname:** The unique node identifier which follows HPE's [xname format](https://cray-hpe.github.io/docs-csm/en-10/operations/component_names_xnames/) (see the "Node" entry in the table) and is supposed to encode location data.
  The format is `x<cabinet>c<chassis>s<slot>b<bmc>n<node>` and must be unique per-node.
- **bmc_mac:** MAC address of node's BMC. This is required even if the node does not have a BMC because SMD uses BMC MAC addresses in its discovery process as the basis for node information. Thus, we need to emulate that here.
- **bmc_ip:** Desired IP address for node's BMC.
- **group:** An optional SMD group to add this node to. cloud-init reads SMD groups when determining which meta-data and cloud-init config to give a node.
- **interfaces** is a list of network interfaces attached to the node. Each of these interfaces has the following keys:
  - **mac_addr:** Network interface's MAC address. Used by CoreDHCP/CoreSMD to give the proper IP address for interface listed in SMD.
  - **ip_addrs:** The list of IP addresses for the node.
    - **name:** A human-readable name for this IP address for this interface.
    - **ip_addr:** An IP address for this interface.

**Example:**
```yaml
- name: node01
  nid: 1
  xname: x1000c1s7b0n0
  bmc_mac: de:ca:fc:0f:ee:ee
  bmc_ip: 172.16.0.101
  group: compute
  interfaces:
  - mac_addr: de:ad:be:ee:ee:f1
    ip_addrs:
    - name: internal
      ip_addr: 172.16.0.1
  - mac_addr: de:ad:be:ee:ee:f2
    ip_addrs:
    - name: external
      ip_addr: 10.15.3.100
  - mac_addr: 02:00:00:91:31:b3
    ip_addrs:
    - name: HSN
      ip_addr: 192.168.0.1
```

### 2.2.3 "Discover" your nodes

Create a directory for putting our cluster configuration data into and **copy the contents of [nodes.yaml](nodes.yaml) there**:

> [!WARNING]
> When writing YAML, it's important to be consistent with spacing. **It is recommended to use spaces for all indentation instead of tabs.**

```bash
mkdir -p /opt/workdir/nodes
# edit /opt/workdir/nodes/nodes.yaml
```

Run the following to populate SMD with the node information (make sure `DEMO_ACCESS_TOKEN` is set):

```bash
ochami discover static -f yaml -d @/opt/workdir/nodes/nodes.yaml
```

There should be no output for the above command.

### 2.2.4 Checkpoint

```bash
ochami smd component get | jq '.Components[] | select(.Type == "Node")'
```

The output should be:

```json
{
  "Enabled": true,
  "ID": "x1000c0s0b0n0",
  "NID": 1,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b1n0",
  "NID": 2,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b2n0",
  "NID": 3,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b3n0",
  "NID": 4,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b4n0",
  "NID": 5,
  "Role": "Compute",
  "Type": "Node"
}
```

🛑 ***STOP HERE***
---

## 2.3 Building and Organizing System Images

Our virtual nodes operate the same way many HPC centers run their physical nodes.  Rather than managing installations on physical disks, they boot directly from the network and run entirely in memory.  And, through clever use of overlays and kernel parameters, all nodes reference the same remote system image (SquashFS), dramatically reducing the chances of differences in the way they operate.

OpenCHAMI isn't opinionated about how these system images are created, managed, or served.  Sites can even run totally from disk if they choose.

For this tutorial, we'll use a project from the OpenCHAMI consortium that creates and manages system images called [image-builder](https://github.com/OpenCHAMI/image-builder).  It is an Infrastructure-as-Code (IaC) tool that translates YAML configuration files into:

- SquashFS images served through S3 (served to nodes)
- Container images served through OCI registries (used as parent layers for child image layers)

Create a directory for our image configs.

```bash
mkdir -p /opt/workdir/images
cd /opt/workdir/images
```


### 2.3.1 Preparing Tools

* To build images, we'll use a containerized version of [image-builder](https://github.com/OpenCHAMI/image-builder)
* To interact with images organized in the OCI registry, we'll use [regclient](https://github.com/regclient/regclient/)
* To interact with Minio for S3-compatible object storage, we'll use [s3cmd](https://s3tools.org/s3cmd)

### 2.3.2 Install and Configure `regctl`

> [!NOTE]
> Make sure you are running the below commands as the `rocky` user and not using `sudo` or a root shell. `regctl` configs are _only_ user-level configs (meaning they live in the running user's home directory) and we want to make sure they get read.

```bash
curl -L https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64 > regctl && sudo mv regctl /usr/local/bin/regctl && sudo chmod 755 /usr/local/bin/regctl
/usr/local/bin/regctl registry set --tls disabled demo.openchami.cluster:5000
```

Make sure the config got set:

```bash
cat ~/.regctl/config.json 
```

The output should be:

```json
{
  "hosts": {
    "demo.openchami.cluster:5000": {
      "tls": "disabled",
      "hostname": "demo.openchami.cluster:5000",
      "reqConcurrent": 3
    }
  }
}
```

### 2.3.3 Install and Configure S3 Client

> [!NOTE]
> Make sure you are running the below commands as the `rocky` user and not using `sudo` or a root shell. `s3cmd` configs are _only_ user-level configs (meaning they live in the running user's home directory) and we want to make sure they get read.

`s3cmd` was installed during the AWS setup, so we just need to create a user config file.

**Edit: `/home/rocky/.s3cfg`**

```ini
# Setup endpoint
host_base = demo.openchami.cluster:9000
host_bucket = demo.openchami.cluster:9000
bucket_location = us-east-1
use_https = False

# Setup access keys
access_key = admin
secret_key = admin123

# Enable S3 v4 signature APIs
signature_v2 = False
```

### 2.3.4 Create and Configure S3 Buckets

```bash
s3cmd mb s3://efi
s3cmd setacl s3://efi --acl-public
s3cmd mb s3://boot-images
s3cmd setacl s3://boot-images --acl-public
```

You should see the following output:

```
Bucket 's3://efi/' created
s3://efi/: ACL set to Public  
Bucket 's3://boot-images/' created
s3://boot-images/: ACL set to Public  
```

Set the policy to allow public downloads from minio's boot-images bucket:

**Edit: `/opt/workdir/s3-public-read-boot.json`**

```json
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":"*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::boot-images/*"]
    }
  ]
}
```

**Edit: `/opt/workdir/s3-public-read-efi.json`**

```json
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Principal":"*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::efi/*"]
    }
  ]
}
```
```bash
s3cmd setpolicy /opt/workdir/s3-public-read-boot.json s3://boot-images \
    --host=172.16.0.254:9000 \
    --host-bucket=172.16.0.254:9000

s3cmd setpolicy /opt/workdir/s3-public-read-efi.json s3://efi \
    --host=172.16.0.254:9000 \
    --host-bucket=172.16.0.254:9000
```

You should see the following command output:

```
s3://boot-images/: Policy updated
s3://efi/: Policy updated
```

We should see the two that got created with `s3cmd ls`:

```
2025-04-22 15:24  s3://boot-images
2025-04-22 15:24  s3://efi
```

## 2.4 Building System Images

Our image builder speeds iteration by encouraging the admin to compose bootable images by layering one image on top of another.  Below are two definitions for images.  Both are bootable and can be used with image-builder.  `base.yaml` starts from an empty container and adds a minmal set of common packages including the kernel.  `compute.yaml` doesn't have to rebuild everything in the base container.  Instead, it just references it and overlays it's own files on top to add more creature comforts necessary for HPC nodes.

Let's create a working directory for out image configs:

```bash
mkdir -p /opt/workdir/images
```

### 2.4.1 Configure The Base Image

**Edit: `/opt/workdir/images/rocky-base-9.yaml`**

```yaml
options:
  layer_type: 'base'
  name: 'rocky-base'
  publish_tags: '9'
  pkg_manager: 'dnf'
  parent: 'scratch'
  publish_registry: 'demo.openchami.cluster:5000/demo'
  registry_opts_push:
    - '--tls-verify=false'

repos:
  - alias: 'Rocky_9_BaseOS'
    url: 'https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/'
    gpg: 'https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9'
  - alias: 'Rocky_9_AppStream'
    url: 'https://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/'
    gpg: 'https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9'

package_groups:
  - 'Minimal Install'
  - 'Development Tools'

packages:
  - kernel
  - wget
  - dracut-live
  - cloud-init
  - chrony
  - rsyslog
  - sudo

cmds:
  - cmd: 'dracut --add "dmsquash-live livenet network-manager" --kver $(basename /lib/modules/*) -N -f --logfile /tmp/dracut.log 2>/dev/null'
  - cmd: 'echo DRACUT LOG:; cat /tmp/dracut.log'
```

Notice that we push to the OCI registry, but not S3. This is because we will not be booting this image directly but will be using it as a parent layer for our base compute image, which we will build later on.

### 2.4.2 Build the Base Image

After creating the base image config above, let's build it:

```bash
podman run --rm --device /dev/fuse --network host -v /opt/workdir/images/rocky-base-9.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

> [!NOTE]
> Messages prefixed with `ERROR` mean that these messages are being emitted at the "error" log level and aren't _necessarily_ errors.

This will take a good chunk of time (~10 minutes or so) since we are building an entire Linux filesystem from scratch. At the end, we should see:

```
-------------------BUILD LAYER--------------------
pushing layer rocky-base to demo.openchami.cluster:5000/demo/rocky-base:9
```

After the build completes, verify that the image has been created and stored in the registry:

```bash
regctl repo ls demo.openchami.cluster:5000
```

We should see:

```
demo/rocky-base
```

We can query this to verify that our "9.5" tag got pushed:

```
regctl tag ls demo.openchami.cluster:5000/demo/rocky-base
```

We should see:

```
9
```

> [!TIP]
> Since this is an OCI image, it can be inspected like one. Try it out:
> ```
> podman run --tls-verify=false --rm -it demo.openchami.cluster:5000/demo/rocky-base:9 bash
> ```

### 2.4.3 Configure the Base Compute Image

Now, let's create the base compute image that will use the base image we just built before as the parent layer. In the compute image layer, we are taking the stock Rocky 9.5 image and adding packages that will be common for all compute nodes.

**Edit: `/opt/workdir/images/compute-base-rocky9.yaml`**

```yaml
options:
  layer_type: 'base'
  name: 'compute-base'
  publish_tags:
    - 'rocky9'
  pkg_manager: 'dnf'
  parent: 'demo.openchami.cluster:5000/demo/rocky-base:9'
  registry_opts_pull:
    - '--tls-verify=false'

  # Publish SquashFS image to local S3
  publish_s3: 'http://demo.openchami.cluster:9000'
  s3_prefix: 'compute/base/'
  s3_bucket: 'boot-images'

  # Publish OCI image to container registry
  #
  # This is the only way to be able to re-use this image as
  # a parent for another image layer.
  publish_registry: 'demo.openchami.cluster:5000/demo'
  registry_opts_push:
    - '--tls-verify=false'

repos:
  - alias: 'Epel9'
    url: 'https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/'
    gpg: 'https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9'

packages:
  - vim
  - nfs-utils
  - tcpdump
  - traceroute
  - git
  - fortune-mod
  - cowsay
  - boxes
  - figlet
```

Notice that this time, we push both to the OCI registry _and_ S3. We will be using this image _both_ as a parent layer to subsequent images _and_ to boot nodes directly.

### 2.4.4 Build the Compute Image

Let's build the base compute image:

```bash
podman run --rm --device /dev/fuse --network host -e S3_ACCESS=admin -e S3_SECRET=admin123 -v /opt/workdir/images/compute-base-rocky9.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

This won't take as long as the base image since we are only installing packages on top of the already-built filesystem. This time, since we are pushing to S3 (and we passed `--log-level DEBUG`) we will see _a lot_ of S3 output. We should see in the output:

```
Pushing /var/tmp/tmpda2ddyh0/rootfs as compute/base/rocky9.6-compute-base-rocky9 to boot-images
pushing layer compute-base to demo.openchami.cluster:5000/demo/compute-base:rocky9
```

Verify that the image has been created and stored in the registry:

```bash
regctl repo ls demo.openchami.cluster:5000
```

We should see both of our images now:

```
demo/compute-base
demo/rocky-base
```

We should see the tag of our new `demo/compute-base` image:

```
regctl tag ls demo.openchami.cluster:5000/demo/compute-base
```

The output should be:

```
rocky9
```

We should also see our image, kernel, and initramfs in S3:

```
s3cmd ls -Hr s3://boot-images | grep compute/base
```

The output should akin to:

```
2025-06-13 00:04  1356M  s3://boot-images/compute/base/rocky9.6-compute-base-rocky9
2025-06-13 00:03    78M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.21.1.el9_6.x86_64.img
2025-06-13 00:03    14M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.21.1.el9_6.x86_64
```

- SquashFS image: `s3://boot-images/compute/base/rocky9.6-compute-base-rocky9`
- Initramfs: `s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.21.1.el9_6.x86_64.img`
- Kernel: `s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.21.1.el9_6.x86_64`

### 2.4.5 Configure the Debug Image

Before we boot an image, let's build a debug image that is based off of the base compute image. The images we've built so far don't contain users (these can be created using post-boot configuration via cloud-init). This image will contain a user with a known password which can be logged into via the serial console. This will be useful later on when debugging potential post-boot configuration issues (e.g. SSH keys weren't provisioned and so login is impossible).

**Edit: `/opt/workdir/images/compute-debug-rocky9.yaml`**

```yaml
options:
  layer_type: base
  name: compute-debug
  publish_tags:
    - 'rocky9'
  pkg_manager: dnf
  parent: '172.16.0.254:5000/demo/compute-base:rocky9'
  registry_opts_pull:
    - '--tls-verify=false'

  # Publish to local S3
  publish_s3: 'http://172.16.0.254:9000'
  s3_prefix: 'compute/debug/'
  s3_bucket: 'boot-images'

packages:
  - shadow-utils

cmds:
  - cmd: "useradd -mG wheel -p '$6$VHdSKZNm$O3iFYmRiaFQCemQJjhfrpqqV7DdHBi5YpY6Aq06JSQpABPw.3d8PQ8bNY9NuZSmDv7IL/TsrhRJ6btkgKaonT.' testuser"
```

If you have the time (or have questions) on the image builder config format, take a look at the [image-builder reference](images.md). Let's take a minute to draw attention to what our debug image config does:

- Use the base compute image as the parent, pull it from the registry without TLS, and call the new image "compute-debug":

  ```yaml
  name: 'compute-debug'
  parent: '172.16.0.254:5000/demo/compute-base:rocky9'
  registry_opts_pull:
    - '--tls-verify=false'
  ```

- Push the image to `http://172.16.0.254:9000/boot-images/compute/debug/` in S3:

  ```yaml
  publish_s3: 'http://172.16.0.254:9000'
  s3_prefix: 'compute/debug/'
  s3_bucket: 'boot-images'
  ```

- Create a `testuser` user (password is `testuser`):

  ```yaml
  packages:
    - shadow-utils

  cmds:
    - cmd: "useradd -mG wheel -p '$6$VHdSKZNm$O3iFYmRiaFQCemQJjhfrpqqV7DdHBi5YpY6Aq06JSQpABPw.3d8PQ8bNY9NuZSmDv7IL/TsrhRJ6btkgKaonT.' testuser"
  ```

  This will be the user we will login to the console as.

### 2.4.6 Build the Debug Image

Build this image:

```bash
podman run --rm --device /dev/fuse -e S3_ACCESS=admin -e S3_SECRET=admin123 -v /opt/workdir/images/compute-debug-rocky9.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

### 2.4.7 Verify Boot Artifact Creation

Once finished, we should see the debug image artifacts show up in S3:

```bash
s3cmd ls -Hr s3://boot-images/
```

We should see output akin to (note that our base image is not here because we didn't push it to S3, only the registry):

```
2025-06-13 00:04  1356M  s3://boot-images/compute/base/rocky9.6-compute-base-rocky9
2025-06-13 00:13  1356M  s3://boot-images/compute/debug/rocky9.6-compute-debug-rocky9
2025-06-13 00:03    78M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.21.1.el9_6.x86_64.img
2025-06-13 00:03    14M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.21.1.el9_6.x86_64
2025-06-13 00:12    78M  s3://boot-images/efi-images/compute/debug/initramfs-5.14.0-570.21.1.el9_6.x86_64.img
2025-06-13 00:12    14M  s3://boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.21.1.el9_6.x86_64
```

We should see a kernel, initramfs, and SquashFS for each image we built.

> [!NOTE]
> Each time an image pushed to S3, three items are pushed:
>
>  - The SquashFS image
>  - The kernel
>  - The initramfs
>
> Make sure you select the right one when setting boot parameters (make sure the S3 prefixes match).

We will be using the URLs (everthing after `s3://`) for the debug boot artifacts next, so use:

```bash
s3cmd ls -Hr s3://boot-images | grep compute/debug
```

to fetch them and copy them somewhere. E.g:

- `boot-images/compute/debug/rocky9.6-compute-debug-9`
- `boot-images/efi-images/compute/debug/initramfs-<REPLACE WITH ACTUAL KERNEL VERSION>.el9_6.x86_64.img`
- `boot-images/efi-images/compute/debug/vmlinuz-<REPLACE WITH ACTUAL KERNEL VERSION>.el9_6.x86_64`

Keep these handy!

🛑 ***STOP HERE***
---

## 2.5 Managing Boot Parameters

The `ochami` tool gives us a convenient interface to changing boot parameters through IaC (Infrastructure as Code).  We store the desired configuration in a file and apply it with a command.

To set boot parameters, we need to pass:

1. The identity of the node that they will be for (MAC address, name, or node ID number)
1. At least one of:
   1. URI to kernel file
   2. URI to initrd file
   3. Kernel command line arguments

   ***OR:***

   1. A file containing the boot parameter data (we will be using this method)

### 2.5.1 Create the Boot Configuration

Create a directory for our boot configs:

```bash
mkdir -p /opt/workdir/boot
```

Then, edit the file below where:

- `kernel` is the kernel URL. It starts with `http://172.16.0.254:9000/` and ends with the kernel path that we copied from the `s3cmd` output earlier (everything past `s3://`)
- `initrd` is the initramfs URL. It starts with `http://172.16.0.254:9000/` and ends with the initramfs path that we copied from the `s3cmd` output earlier (everything past `s3://`)
- `params` is the kernel command line arguments. Copy the ones from the line below, **but change the `root=` parameter to point to the SquashFS image**
  - The format is `root=live:http://172.16.0.254:9000/` concatenated with the path to the SquashFS image obtained from `s3cmd` eariler (everything past `s3://`)
- `macs` is the list of MAC addresses corresponding to the boot interface for our virtual compute nodes. These can be verbatim.

**Edit: `/opt/workdir/boot/boot-compute-debug.yaml`**

> [!WARNING]
> Your file will not look like the one below due to differences in kernel versions over time.
> Be sure to update with the output of `s3cmd ls` as stated above!

```yaml
kernel: 'http://172.16.0.254:9000/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.21.1.el9_6.x86_64'
initrd: 'http://172.16.0.254:9000/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.21.1.el9_6.x86_64.img'
params: 'nomodeset ro root=live:http://172.16.0.254:9000/boot-images/compute/debug/rocky9.6-compute-debug-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
```
### 2.5.2 Set the Boot Configuration

> [!NOTE]
> `ochami` supports both `add` and `set`.  The difference is idempotency.  If using the `add` command, `bss` will reject replacing an existing boot configuration.

```bash
ochami bss boot params set -f yaml -d @/opt/workdir/boot/boot-compute-debug.yaml
```

Verify that the parameters were set correctly with:

```bash
ochami bss boot params get -F yaml
```

The output should be akin to:

```yaml
- cloud-init:
    meta-data: null
    phone-home:
        fqdn: ""
        hostname: ""
        instance_id: ""
        pub_key_dsa: ""
        pub_key_ecdsa: ""
        pub_key_rsa: ""
    user-data: null
  initrd: http://172.16.0.254:9000/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.21.1.el9_6.x86_64.img
  kernel: http://172.16.0.254:9000/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.21.1.el9_6.x86_64
  macs:
    - 52:54:00:be:ef:01
    - 52:54:00:be:ef:02
    - 52:54:00:be:ef:03
    - 52:54:00:be:ef:04
    - 52:54:00:be:ef:05
  params: nomodeset ro root=live:http://172.16.0.254:9000/boot-images/compute/debug/rocky9.6-compute-debug-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init
```

The things to check are:

- `initrd` URL points to debug initrd (try `curl`ing it to make sure it works)
- `kernel` URL points to debug kernel (try `curl`ing it to make sure it works)
- `root=live:` URL points to debug image (try `curl`ing it to make sure it works)

## 2.6 Boot the Compute Node with the Debug Image

Boot the first compute node into the debug image, following the console:

```bash
sudo virt-install \
  --name compute1 \
  --memory 4096 \
  --vcpus 1 \
  --disk none \
  --pxe \
  --os-variant centos-stream9 \
  --network network=openchami-net,model=virtio,mac=52:54:00:be:ef:01 \
  --graphics none \
  --console pty,target_type=serial \
  --boot network,hd \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/OVMF/OVMF_VARS.fd,loader_secure=no \
  --virt-type kvm
```

> [!TIP]
> If you need to destroy and restart the VM, first exit the console with `Ctrl`+`]`. Then:
> 1. Shut down ("destroy") the VM:
>    ```
>    sudo virsh destroy compute1
>    ```
> 2. Undefine the VM:
>    ```
>    sudo virsh undefine --nvram compute1
>    ```
> 3. Rerun the `virt-install` command above.

Watch it boot. First, it should PXE:

```
>>Start PXE over IPv4.
  Station IP address is 172.16.0.1

  Server IP address is 172.16.0.254
  NBP filename is ipxe-x86_64.efi
  NBP filesize is 1079296 Bytes
 Downloading NBP file...

  NBP file downloaded successfully.
BdsDxe: loading Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
BdsDxe: starting Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
iPXE initialising devices...
autoexec.ipxe... Not found (https://ipxe.org/2d12618e)



iPXE 1.21.1+ (ge9a2) -- Open Source Network Boot Firmware -- https://ipxe.org
Features: DNS HTTP HTTPS iSCSI TFTP VLAN SRP AoE EFI Menu
```
> [!TIP]
> You may need to edit the `/etc/openchami/configs/coredhcp.yaml` config file and uncomment all the values if you see an error when booting.
> ```bash
> >>Start PXE over IPv4.
>  PXE-E18: Server response timeout.
> BdsDxe: failed to load Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0): Not Found
> ```

Then, we should see it get it's boot script from TFTP, then BSS (the `/boot/v1` URL), then download it's kernel/initramfs and boot into Linux.

```
Configuring (net0 52:54:00:be:ef:01)...... ok
tftp://172.16.0.254:69/config.ipxe... ok
Booting from http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01
http://172.16.0.254:8081/boot/v1/bootscript... ok
http://172.16.0.254:9000/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-570.21.1.el9_6.x86_64... ok
http://172.16.0.254:9000/boot-images/efi-images/compute/debug/initramfs-5.14.0-570.21.1.el9_6.x86_64.img... ok
```

During Linux boot, we should see the SquashFS image get downloaded and loaded.

```
[    2.169210] dracut-initqueue[545]:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
[    2.170532] dracut-initqueue[545]:                                  Dload  Upload   Total   Spent    Left  Speed
100 1356M  100 1356M    0     0  1037M      0  0:00:01  0:00:01 --:--:-- 1038M
[    3.627908] squashfs: version 4.0 (2009/01/31) Phillip Lougher
```

Cloud-Init (and maybe SSH) will fail (since we haven't set it up yet), but that's okay for now.

### 2.6.1 Log In to the Compute Node

```
Rocky Linux 9.6 (Blue Onyx)
Kernel 5.14.0-570.21.1.el9_6.x86_64 on x86_64

nid0001 login:
```

Login with `testuser` for the username and password and check that we are on the live image:

```bash
[testuser@nid0001 ~]$ findmnt /
TARGET SOURCE        FSTYPE  OPTIONS
/      LiveOS_rootfs overlay rw,relatime,lowerdir=/run/rootfsbase,upperdir=/run/
```

Excellent! Play around a bit more and then logout. Use `Ctrl`+`]` to exit the Virsh console.

🛑 ***STOP HERE***
---

## 2.7 OpenCHAMI's Cloud-Init Metadata Server

[Cloud-Init](https://cloudinit.readthedocs.io/en/latest/index.html) is the way that OpenCHAMI provides post-boot configuration. The idea is to keep the image generic without any sensitive data like secrets and let cloud-init take care of that data.

Cloud-Init works by having an API server that keeps track of the configuration for all nodes, and nodes fetch their configuration from the server via a cloud-init client installed in the node image. The node configuration is split up into meta-data (variables) and a configuration specification that can optionally be templated using the meta-data.

OpenCHAMI [has its own flavor](https://github.com/OpenCHAMI/cloud-init) of Cloud-Init server that utilizes groups in SMD to provide the appropriate configuration. (This is why we added our compute nodes to a "compute" group during discovery.)

In a typical OpenCHAMI Cloud-Init setup, the configuration is set up in three phases:

1. Configure cluster-wide default meta-data
2. Configure group-level cloud-init configuration with optional group meta-data
3. (_OPTIONAL_) Configure node-specific cloud-init configuration and meta-data

We will be using the OpenCHAMI Cloud-Init server in this tutorial for node post-boot configuration.

### 2.7.1 Configure Cluster Meta-Data

Let's create a directory for storing our configuration:

```bash
mkdir -p /opt/workdir/cloud-init
cd /opt/workdir/cloud-init
```

Now, create a new SSH key on the head node and press **Enter** for all of the prompts:

```bash
ssh-keygen -t ed25519
```

The new that was generated can be found in `~/.ssh/id_ed25519.pub`. We're going to need this to include this in the cloud-init meta-data.

```bash
cat ~/.ssh/id_ed25519.pub
```

Create `ci-defaults.yaml` with the following content, replacing the `<YOUR SSH KEY GOES HERE>` line with your SSH public key from above:

**Edit: `/opt/workdir/cloud-init/ci-defaults.yaml`**

```yaml
---
base-url: "http://172.16.0.254:8081/cloud-init"
cluster-name: "demo"
nid-length: 3
public-keys:
- "<YOUR SSH KEY GOES HERE>"
short-name: "nid"
```

Then, we set the cloud-init defaults using the `ochami` CLI:

```bash
ochami cloud-init defaults set -f yaml -d @/opt/workdir/cloud-init/ci-defaults.yaml
```

e can verify that these values were set with:

```bash
ochami cloud-init defaults get -F json-pretty
```

The output should be:

```json
{
  "base-url": "http://172.16.0.254:8081/cloud-init",
  "cluster-name": "demo",
  "nid-length": 2,
  "public-keys": [
    "<YOUR SSH KEY>"
  ],
  "short-name": "nid"
}
```

### 2.7.2 Configure Group-Level Cloud-Init

Now, we need to set the cloud-init configuration for the `compute` group, which is the SMD group that all of our nodes are in. For now, we will create a simple config that only sets our SSH key.

First, let's create a templated cloud-config file. Create `ci-group-compute.yaml` with the following contents:

**Edit: `/opt/workdir/cloud-init/ci-group-compute.yaml`**

```yaml
- name: compute
  description: "compute config"
  file:
    encoding: plain
    content: |
      ## template: jinja
      #cloud-config
      merge_how:
      - name: list
        settings: [append]
      - name: dict
        settings: [no_replace, recurse_list]
      users:
        - name: root
          ssh_authorized_keys: {{ ds.meta_data.instance_data.v1.public_keys }}
      disable_root: false
```

Now, we need to set this configuration for the compute group:

```bash
ochami cloud-init group set -f yaml -d @/opt/workdir/cloud-init/ci-group-compute.yaml
```

We can check that it got added with:

```bash
ochami cloud-init group get config compute
```

We should see the cloud-config file we created above print out:

```yaml
## template: jinja
#cloud-config
merge_how:
- name: list
  settings: [append]
- name: dict
  settings: [no_replace, recurse_list]
users:
  - name: root
    ssh_authorized_keys: {{ ds.meta_data.instance_data.v1.public_keys }}
disable_root: false
```

We can also check that the Jinja2 is rendering properly for a node. Let's see what the cloud-config would render to for our first compute node (x1000c0s0b0n0):

```bash
ochami cloud-init group render compute x1000c0s0b0n0
```

> [!NOTE]
> This feature requires that impersonation is enabled with cloud-init. Check and make sure that the `IMPERSONATION` environment variable is set in `/etc/openchami/configs/openchami.env`.

We should see the SSH key we created in the config:

```yaml
#cloud-config
merge_how:
- name: list
  settings: [append]
- name: dict
  settings: [no_replace, recurse_list]
users:
  - name: root
    ssh_authorized_keys: ['<SSH_KEY>']
```

## 2.7.3 (_OPTIONAL_) Configure Node-Specific Meta-Data

If we wanted, we could configure node-specific meta-data.

For instance, if we wanted to change the hostname of our first compute node from the default `nid01`, we could change it to `compute1` with:

```bash
ochami cloud-init node set -d '[{"id":"x1000c0s0b0n0","local-hostname":"compute1"}]'
```

### 2.7.4 Check the Cloud-Init Metadata

We can examine the merged cloud-init meta-data for a node with:

```bash
ochami cloud-init node get meta-data x1000c0s0b0n0 -F yaml
```

We should get something like:

```yaml
- cluster-name: demo
  hostname: nid001
  instance-id: i-3903b323
  instance_data:
    v1:
        instance_id: i-3903b323
        local_ipv4: 172.16.0.1
        public_keys:
            - <SSH_KEY>
        vendor_data:
            cloud_init_base_url: http://172.16.0.254:8081/cloud-init
            cluster_name: demo
            groups:
                compute:
                    Description: compute config
            version: "1.0"
  local-hostname: compute1
```

This merges the cluster default, group, and node-specific meta-data.

If the node is a member of multiple groups, the order of the merging of those groups' configs can be seen by running:

```bash
ochami cloud-init node get vendor-data x1000c0s0b0n0
```

The result will be an `#include` directive followed by a list of URIs to each group cloud-config endpoint for each group the node is a member of:

```
#include
http://172.16.0.254:8081/cloud-init/compute.yaml
```

So far, this compute node is only a member of the one group above.

## 2.8 Boot Using the Compute Image

### 2.8.1 Switch from the Debug Image to the Compute Image

BSS still thinks our nodes are booting the debug image, so we need to tell it to boot our compute image.

First, we will need to know the paths to the boot artifacts for the compute image, which we can query S3 for:

```bash
s3cmd ls -Hr s3://boot-images/ | awk '{print $4}' | grep base
```

We should see:

```
s3://boot-images/compute/base/rocky9.6-compute-base-rocky9
s3://boot-images/efi-images/compute/base/initramfs-5.14.0-570.21.1.el9_6.x86_64.img
s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.21.1.el9_6.x86_64
```

Let's create `boot-compute.yaml` with these values.

**Edit: `/opt/workdir/boot/boot-compute.yaml`**

```yaml
kernel: 'http://172.16.0.254:9000/boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.21.1.el9_6.x86_64'
initrd: 'http://172.16.0.254:9000/boot-images/efi-images/compute/base/initramfs-5.14.0-570.21.1.el9_6.x86_64.img'
params: 'nomodeset ro root=live:http://172.16.0.254:9000/boot-images/compute/base/rocky9.6-compute-base-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
```

We should only have to change `debug` to `base` compared to out debug boot configuration since the images we built before should be similar.

Then, we can set these new parameters with:

```bash
ochami bss boot params set -f yaml -d @/opt/workdir/boot/boot-compute.yaml
```

Double-check that the params were updated if needed:

```bash
ochami bss boot params get -f json-pretty
```

They should match the file above:

```yaml
- cloud-init:
    meta-data: null
    phone-home:
        fqdn: ""
        hostname: ""
        instance_id: ""
        pub_key_dsa: ""
        pub_key_ecdsa: ""
        pub_key_rsa: ""
    user-data: null
  initrd: http://172.16.0.254:9000/boot-images/efi-images/compute/base/initramfs-5.14.0-570.21.1.el9_6.x86_64.img
  kernel: http://172.16.0.254:9000/boot-images/efi-images/compute/base/vmlinuz-5.14.0-570.21.1.el9_6.x86_64
  macs:
    - 52:54:00:be:ef:01
    - 52:54:00:be:ef:02
    - 52:54:00:be:ef:03
    - 52:54:00:be:ef:04
    - 52:54:00:be:ef:05
  params: nomodeset ro root=live:http://172.16.0.254:9000/boot-images/compute/base/rocky9.6-compute-base-rocky9 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init
```

### 2.8.2 Booting the Compute Node

Now that we have our compute base image, BSS configured to point to it, and Cloud-Init configured with the post-boot configuration, we are now ready to boot a node.

Check that the boot parameters point to the base image with `ochami boot params get | jq`.

Then, power cycle `compute1` and attach to the console to watch it boot:

```bash
sudo virsh destroy compute1
sudo virsh start --console compute1
```

> [!TIP]
> If you get:
> ```
> error: failed to get domain 'compute1'
> ```
> it may be that your VM is already undefined. Run the `virt-install` command above again to recreate it.

Just like with the debug image, we should see the node:

1. Get its IP address (172.16.0.1)
2. Download the iPXE bootloader binary from CoreSMD
3. Download the `config.ipxe` script that chainloads the iPXE script from BSS (http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01)
4. Download the kernel and initramfs in S3
5. Boot into the image, running cloud-init

```
>>Start PXE over IPv4.
  Station IP address is 172.16.0.1

  Server IP address is 172.16.0.254
  NBP filename is ipxe-x86_64.efi
  NBP filesize is 1079296 Bytes
 Downloading NBP file...

  NBP file downloaded successfully.
BdsDxe: loading Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
BdsDxe: starting Boot0001 "UEFI PXEv4 (MAC:525400BEEF01)" from PciRoot(0x0)/Pci(0x1,0x0)/Pci(0x0,0x0)/MAC(525400BEEF01,0x1)/IPv4(0.0.0.0,0x0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
iPXE initialising devices...
autoexec.ipxe... Not found (https://ipxe.org/2d12618e)



iPXE 1.21.1+ (ge9a2) -- Open Source Network Boot Firmware -- https://ipxe.org
Features: DNS HTTP HTTPS iSCSI TFTP VLAN SRP AoE EFI Menu
Configuring (net0 52:54:00:be:ef:01)...... ok
tftp://172.16.0.254:69/config.ipxe... ok
Booting from http://172.16.0.254:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01
http://172.16.0.254:8081/boot/v1/bootscript... ok
http://172.16.0.254:9000/boot-images/efi-images/compute/base/vmlinuz-5.14.0-503.38.1.el9_5.x86_64... ok
http://172.16.0.254:9000/boot-images/efi-images/compute/base/initramfs-5.14.0-503.38.1.el9_5.x86_64.img... ok
```

> [!WARNING]
> If the logs includes this, we've got trouble `8:37PM DBG IP address 10.89.2.1 not found for an xname in nodes`
>
> It means that our iptables has mangled the packet and we're not receiving correctly through the bridge.

### 2.8.3 Logging Into the Compute Node

Login as root to the compute node, ignoring its host key:

```
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@172.16.0.1
```

> [!TIP]
> We don't store the SSH host key of the compute nodes because cloud-init regenerates it on each reboot. To permanently ignore, create `/etc/ssh/ssh_config.d/ignore.conf` **on the head node (not the virtual compute)** with the following content:
> ```
> Match host=172.16.0.*
>         UserKnownHostsFile=/dev/null
>         StrictHostKeyChecking=no
> ```
> Then, the `-o` options can be omitted to `ssh`.

If Cloud-Init provided our SSH key, it should work:

```
Warning: Permanently added '172.16.0.1' (ED25519) to the list of known hosts.
Last login: Thu May 29 06:59:26 2025 from 172.16.0.254
[root@compute1 ~]#
```

Congratulations, you've just used OpenCHAMI to boot and login to a compute node! 🎉

🛑 ***STOP HERE***
---
