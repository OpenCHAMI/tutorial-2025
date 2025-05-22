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
   - Verify DHCP options & TFTP with `tcpdump`, `tftp`  
   - Checkpoint: Successful serial console installer

---

# Node Discovery for Inventory

In order for OpenCHAMI to be useful, the State Management Database (SMD) needs to be populated with node information. This can be done one of two ways: _static_ discovery via [the `ochami` CLI](https://github.com/OpenCHAMI/ochami) or _dynamic_ discovery via [the `magellan` CLI](https://github.com/OpenCHAMI/magellan).

Static discovery is predictable and easily reproduceable, so we will use it in this tutorial.

## Dynamic Discovery Overview

Dynamic discovery happens via Redfish using `magellan`.

At a high level, `magellan` `scan`s a specified network for hosts running a Redfish server (e.g. BMCs). Once it knows which IPs are using Redfish, the tool can `crawl` each BMC's Redfish structure to get more detailed information about it, then `collect` this information and send it to SMD.

When combined with DHCP dynamically handing out IPs, this process can be non-deterministic.

## Static Discovery Overview

Static discovery happens via `ochami` by giving it a static discovery file. "Discovery" is a bit of a misnomer as nothing is actually discovered. Instead, predefined node data is given to SMD which creates the necessary internal structures to boot nodes.

## Anatomy of a Static Discovery File

`ochami` adds nodes to SMD through a yaml syntax (or json) that lists node descriptions throough a minimal set of node characteristics and a set of interface definitions.

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

#### Example
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
---

## "Discover" your nodes

Create a directory for putting our cluster configuration data into and copy the contents of [nodes.yaml](nodes.yaml) there:

```bash
mkdir -p /opt/workdir/nodes
vim /opt/workdir/nodes/nodes.yaml
```

Run the following to populate SMD with the node information (make sure `DEMO_ACCESS_TOKEN` is set):

```bash
ochami discover static -f yaml -d @/opt/workdir/nodes/nodes.yaml
```

## Checkpoint

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

---
# Building and Organizing System Images

Our virtual nodes operate the same way many HPC centers run their physical nodes.  Rather than managing installations on physical disks, they boot directly from the network and run entirely in memory.  And, through clever use of overlays and kernel parameters, all nodes reference the same remote system image (squashfs), dramatically reducing the chances of differences in the way they operate.

OpenCHAMI isn't opinionated about how these system images are created, managed, or served.  Sites can even run totally from disk if they choose.

For this tutorial, we'll use a project from the OpenCHAMI consortium that creates and manages system images called [image-builder](https://github.com/OpenCHAMI/image-builder).  It is an Infrastructure-as-Code (IaC) tool that translates yaml configuration files into squashfs images that can be managed and served through OCI registries and S3-compatible object stores.

Create a directory for our image configs.

```bash
mkdir -p /opt/workdir/images
cd /opt/workdir/images
```


## Preparing Tools

* To build images, we'll use a containerized version of [image-builder](https://github.com/OpenCHAMI/image-builder)
* To interact with images organized in the OCI registry, we'll use [regclient](https://github.com/regclient/regclient/)
* To interact with Minio for S3-compatible object storage, we'll use [s3cmd](https://s3tools.org/s3cmd)

### Install and configure regctl

```bash
curl -L https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64 > regctl && sudo mv regctl /usr/local/bin/regctl && sudo chmod 755 /usr/local/bin/regctl
/usr/local/bin/regctl registry set --tls disabled demo.openchami.cluster:5000
```

## Install and configure S3 Client

**`~/.s3cfg`**

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

## Create and configure S3 buckets

```bash
s3cmd mb s3://efi
s3cmd setacl s3://efi --acl-public
s3cmd mb s3://boot-images
s3cmd setacl s3://boot-images --acl-public

```

We should see the two that got created:

```
2025-04-22 15:24  s3://boot-images
2025-04-22 15:24  s3://efi
```

---

# Building System Images

Our image builder speeds iteration by encouraging the admin to compose bootable images by layering one image on top of another.  Below are two definitions for images.  Both are bootable and can be used with image-builder.  Base.yaml starts from an empty container and adds a minmal set of common packages including the kernel.  Copmpute.yaml doesn't have to rebuild everything in the base container.  Instead, it just references it and overlays it's own files on top to add more creature comforts necessary for HPC nodes.

**base.yaml**
```yaml
options:
  layer_type: 'base'
  name: 'rocky-base'
  publish_tags: '9.5'
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
    loglevel: INFO
  - cmd: 'echo DRACUT LOG:; cat /tmp/dracut.log'
    loglevel: INFO
```

**compute.yaml**
```yaml
options:
  layer_type: 'base'
  name: 'compute-base'
  publish_tags:
    - '9.5'
  pkg_manager: 'dnf'
  parent: 'demo.openchami.cluster:5000/demo/rocky-base:9.5'
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

## Build the base image

Ensure you have copied the files above into the `/opt/workdr/images` directory before running the image-build commands

```bash
podman run --rm --device /dev/fuse --network host -v /opt/workdir/images/base.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

Verify that the image has been created and stored in the registry

```bash
regctl repo ls demo.openchami.cluster:5000
```

## Build the compute image

```bash
podman run --rm --device /dev/fuse --network host -v /opt/workdir/images/compute.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

Verify that the image has been created and stored in the registry

```bash
regctl repo ls demo.openchami.cluster:5000
```

## Build the debug image

The images we've built so far don't contain any users.  We'll create those using cloud-init in a later step, but leaves us with no way to verify that the images are valid or to troubleshoot cloud-init.  We'll need to create our own new layer.  Follow the examples above and review the [image-builder reference](images.md).


- Use the base compute image as the parent:

  ```yaml
  parent: 'demo.openchami.cluster:5000/openchami/compute-base:9.5'
  registry_opts_pull:
    - '--tls-verify=false'
  ```

- Push the image to the `compute/debug` prefix:

  ```yaml
  s3_prefix: 'compute/debug/'
  ```

- Create a `testuser` user (password is `testuser`):

  ```yaml
  packages:
    - shadow-utils

  cmds:
    - cmd: "useradd -mG wheel -p '$6$VHdSKZNm$O3iFYmRiaFQCemQJjhfrpqqV7DdHBi5YpY6Aq06JSQpABPw.3d8PQ8bNY9NuZSmDv7IL/TsrhRJ6btkgKaonT.' testuser"
      loglevel: INFO
  ```

  This will be the user we will login to the console as.

Build this image:

```bash
podman run --rm --device /dev/fuse -e S3_ACCESS=admin -e S3_SECRET=admin123 -v /opt/workdir/images/compute-debug.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

Once finished, we should see the debug image artifacts show up in S3:

```bash
s3cmd ls -Hr s3://boot-images/
```

```
2025-04-22 15:48  1284M  s3://boot-images/compute/base/rocky9.5-compute-base-9.5
2025-04-22 17:28  1284M  s3://boot-images/compute/debug/rocky9.5-compute-debug-9.5
2025-04-22 15:48    75M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-503.38.1.el9_5.x86_64.img
2025-04-22 15:48    13M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-503.38.1.el9_5.x86_64
2025-04-22 17:28    75M  s3://boot-images/efi-images/compute/debug/initramfs-5.14.0-503.38.1.el9_5.x86_64.img
2025-04-22 17:28    13M  s3://boot-images/efi-images/compute/debug/vmlinuz-5.14.0-503.38.1.el9_5.x86_64
```

We will be using the following pieces of the debug URLs for the boot setup in the next section:

- `boot-images/compute/debug/rocky9.5-compute-debug-9.5`
- `boot-images/efi-images/compute/debug/initramfs-5.14.0-503.38.1.el9_5.x86_64.img`
- `boot-images/efi-images/compute/debug/vmlinuz-5.14.0-503.38.1.el9_5.x86_64`

--


# Managing Boot Parameters

The `ochami` tool gives us a convenient interface to changing boot parameters through IaC.  We store the desired configuration in a file and apply it with a command. 

> [!TIP]
> `ochami` supports both `add` and `set`.  The difference is idempotency.  If using the `add` command, `bss` will reject replacing an existing boot configuration

To set boot parameters, we need to pass:

1. The identity of the node that they will be for (MAC address, name, or node ID number)
1. At least one of:
   1. URI to kernel file
   2. URI to initrd file
   3. Kernel command line arguments

## Create the boot configuration

Create `/opt/workdir/nodes/boot-debug.yaml`:

```yaml
kernel: 'http://172.16.0.254:9090/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-503.38.1.el9_5.x86_64'
initrd: 'http://172.16.0.254:9090/boot-images/efi-images/compute/debug/initramfs-5.14.0-503.38.1.el9_5.x86_64.img'
params: 'nomodeset ro root=live:http://172.16.0.254:9090/boot-images/compute/debug/rocky9.5-compute-debug-9.5 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
```
## Set the boot configuration

```bash
ochami bss boot params set -f yaml -d @/opt/workdir/nodes/boot-debug.yaml
```

---
# Booting the first virtual compute node

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
  --virt-type kvm
```

> [!TIP]
> The default virt-install doesn't show anything during boot.
> To get the full details of the bios, replace the standard `--boot` flag for `virt-install` to one that activates the console before the Linux Kernel through a bootloader
> ```bash
>  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/var/lib/libvirt/qemu/nvram/compute.fd,loader_secure=no \
> ```