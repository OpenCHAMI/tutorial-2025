# Cloud-Init for Post-Boot Configuration

## Contents

- [Cloud-Init for Post-Boot Configuration](#cloud-init-for-post-boot-configuration)
  - [Contents](#contents)
- [Introduction](#introduction)
- [Anatomy of a Cloud-Init Configuration](#anatomy-of-a-cloud-init-configuration)
- [Reference: Using `ochami` to Manage Cloud-Init Configuration](#reference-using-ochami-to-manage-cloud-init-configuration)
  - [Cluster Default Meta-Data](#cluster-default-meta-data)
    - [Retrieval](#retrieval)
    - [Setting](#setting)
- [Prerequisite: Create an SSH Key](#prerequisite-create-an-ssh-key)
- [Creating a Basic Cloud-Init Config](#creating-a-basic-cloud-init-config)
  - [Configuring Cluster-Wide Default Meta-Data](#configuring-cluster-wide-default-meta-data)
  - [Configuring Group-Level Cloud-Init Configuration](#configuring-group-level-cloud-init-configuration)
    - [Creating the Compute Group Cloud-Config File](#creating-the-compute-group-cloud-config-file)
    - [Setting the Cloud-Config File for the Compute Group](#setting-the-cloud-config-file-for-the-compute-group)
  - [(_OPTIONAL_) Configuring Node-Specific Meta-Data](#optional-configuring-node-specific-meta-data)
  - [Checking the Cloud-Init Metadata](#checking-the-cloud-init-metadata)
- [Booting the Compute Image](#booting-the-compute-image)
  - [Switching from the Debug Image to the Compute Image](#switching-from-the-debug-image-to-the-compute-image)
  - [Booting the Compute Node](#booting-the-compute-node)

# Introduction

[Cloud-Init](https://cloudinit.readthedocs.io/en/latest/index.html) is the way that OpenCHAMI provides post-boot configuration. The idea is to keep the image generic without any sensitive data like secrets and let cloud-init take care of that data.

Cloud-Init works by having an API server that keeps track of the configuration for all nodes, and nodes fetch their configuration from the server via a cloud-init client installed in the node image. The node configuration is split up into meta-data (variables) and a configuration specification that can optionally be templated using the meta-data.

OpenCHAMI [has its own flavor](https://github.com/OpenCHAMI/cloud-init) of Cloud-Init server that utilizes groups in SMD to provide the appropriate configuration. (This is why we added our compute nodes to a "compute" group during discovery.)

In a typical OpenCHAMI Cloud-Init setup, the configuration is set up in three phases:

1. Configure cluster-wide default meta-data
2. Configure group-level cloud-init configuration with optional group meta-data
3. (_OPTIONAL_) Configure node-specific cloud-init configuration and meta-data

We will be using the OpenCHAMI Cloud-Init server in this tutorial for node post-boot configuration.

# Anatomy of a Cloud-Init Configuration

# Reference: Using `ochami` to Manage Cloud-Init Configuration

## Cluster Default Meta-Data

### Retrieval

```bash
ochami cloud-init defaults get
```

# Creating a Basic Cloud-Init Config

Let's create a directory for storing our configuration:

```bash
mkdir -p /opt/workdir/cloud-init
cd /opt/workdir/cloud-init
```

## Configuring Cluster-Wide Default Meta-Data

Create `defaults.yaml` with the following content:

```yaml
---
base-url: "http://172.16.0.254:8081/cloud-init"
cluster-name: "demo"
nid-length: 3
public-keys:
- "<YOUR SSH KEY GOES HERE>"
short-name: "nid"
```

Replace the SSH key in `public-keys` to be your own that you created above. You can obtain it locally:

```bash
cat ~/.ssh/id_ed25519.pub
```

> [!TIP]
> Did you know that github makes it easy to download your public ssh keys?
> `https://github.com/$USERNAME.keys`

Notice that we specify the following information:

- `base-url`: The base URI of the cloud-init server. This is used when fetching group cloud-init configuration when merging configuration for a node.
- `cluster-name`: The human-readable, brief name of the cluster.
- `nid-length`: The width of node ID number, used when zero-padding the node ID in the hostname.

  By default, the hostname of a node is something like `nid001`, which is `nid` followed by the padded node ID (NID) number. Notice that the NID is padded with two zeroes for a `nid_length` of `3` (which is the default). This option allows one to change this width.
- `public_keys`: A list of SSH public keys to place on nodes.
- `short-name`: The prefix to the NID number in the hostname (`nid` by default).

  Hostnames are, by default, formatted as `<short-name><padded-nid>`. For instance, if `short-name` was `foo`, the default hostname for NID 1 would be `foo001`.

  Hostnames can be overridden on a per-node basis.

Cluster default meta-data is not arbitrary and only has the keys that we set above. As implied by the name, this meta-data applies cluster-wide.

Set this data in Cloud-Init with:

```bash
ochami cloud-init defaults set -f yaml -d @/opt/workdir/cloud-init/defaults.yaml
```

We can verify that these values were set with:

```bash
ochami cloud-init defaults get | jq
```

The output should be:

```json
{
  "base-url": "http://172.16.0.254:8081/cloud-init",
  "cluster-name": "demo",
  "nid-length": 2,
  "public-keys": [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKlJg... rocky@tutorial.openchami.cluster"
  ],
  "short-name": "nid"
}
```

## Configuring Group-Level Cloud-Init Configuration

Now, we need to set the cloud-init configuration for the `compute` group, which is the SMD group that all of our nodes are in. For now, we will create a simple config that only sets our SSH key.

### Creating the Compute Group Cloud-Config File

First, let's create a templated cloud-config file. Create `computes.yaml` with the following contents:

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

Notice a few things:

- `## template: jinja` as the first line tells cloud-init to render Jinja2 templates in this config.
  - **WARNING:** cloud-init expects this line to appear _exactly_ this way and will err if not.
- `#cloud-config` is read by cloud-init to tell it that it is a cloud-init config (sort of like a shebang).
  - **WARNING:** cloud-init expects this line to appear _exactly_ this way and will err if not.
- `merge_how` is a cloud-init-ism that tells cloud-init how to merge configs.

  Here, we tell it to append items in a child list to the parent list instead of overriding the parent with the child and to not replace parent dictionary item keys with child item keys.
- `{{ ds.meta_data.instance_data.v1.public_keys }}` is a Jinja2 variable that will place the list of SSH keys into the value of `ssh_authorized_keys`.

  In our simple config, we only set it for the root user.

### Setting the Cloud-Config File for the Compute Group

Now, we need to set this configuration for the compute group. This can be a bit awkward because we have to embed the cloud-config file into a JSON or YAML payload wrapped by the group information. We could create a file for this, but we want to be able to easily modify the cloud-config file and re-set the config with ease.

Thus, we will dynamically include the cloud-config file in the payload:

```bash
cat <<EOF | ochami cloud-init group set -l debug -f yaml
---
- name: compute
  description: "compute group cloud-config template"
  file:
    encoding: base64
    content: $(base64 -w0 /opt/workdir/cloud-init/computes.yaml)
EOF
```

We can check that it got added with:

```bash
ochami cloud-init group get config compute
```

We should see the cloud-config file we created above print out.

We can also check that the Jinja2 is rendering properly for a node. Let's see what the cloud-config would render to for our first compute node (x1000c0s0b0n0):

```bash
ochami cloud-init group render compute x1000c0s0b0n0
```

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
    ssh_authorized_keys: ['ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKlJg... rocky@tutorial.openchami.cluster']
```

## (_OPTIONAL_) Configuring Node-Specific Meta-Data

If we wanted, we could configure node-specific meta-data.

For instance, if we wanted to change the hostname of our first compute node from the default `nid01`, we could change it to `compute1` with:

```bash
ochami cloud-init node set -d '[{"id":"x1000c0s0b0n0","local_hostname":"compute1"}]'
```

## Checking the Cloud-Init Metadata

We can examine the merged cloud-init meta-data for a node with:


```bash
ochami cloud-init node get meta-data x1000c0s0b0n0 | jq
```

```json
[
  {
    "cluster-name": "demo",
    "hostname": "nid01",
    "instance-id": "i-fd37994e",
    "instance_data": {
      "v1": {
        "instance_id": "i-fd37994e",
        "local_ipv4": "172.16.0.1",
        "public_keys": [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKlJg... rocky@tutorial.openchami.cluster"
        ],
        "vendor_data": {
          "cloud_init_base_url": "http://172.16.0.254:8081/cloud-init",
          "cluster_name": "demo",
          "groups": {
            "compute": {
              "Description": "compute group cloud-config template"
            }
          },
          "version": "1.0"
        }
      }
    },
    "local-hostname": "compute1"
  }
]
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

So far, the node is only a member of one group.

# Booting the Compute Image

## Switching from the Debug Image to the Compute Image

BSS still thinks our nodes are booting the debug image, so we need to tell it to boot our compute image.

First, we will need to know the paths to the boot artifacts for the compute image, which we can query S3 for:

```bash
s3cmd ls -Hr s3://boot-images/ | awk '{print $4}' | grep base
```

We should see:

```
s3://boot-images/compute/base/rocky9.5-compute-base-9.5
s3://boot-images/efi-images/compute/base/initramfs-5.14.0-503.38.1.el9_5.x86_64.img
s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-503.38.1.el9_5.x86_64
```

We can copy `/opt/workdir/nodes/boot-debug.yaml` to `/opt/workdir/nodes/boot-compute.yaml` and make modifications. We modify the `kernel`, `initrd`, and `params` to point to the boot artifacts listed in S3 above:

```yaml
kernel: 'http://172.16.0.254:9090/boot-images/efi-images/compute/base/vmlinuz-5.14.0-503.38.1.el9_5.x86_64'
initrd: 'http://172.16.0.254:9090/boot-images/efi-images/compute/base/initramfs-5.14.0-503.38.1.el9_5.x86_64.img'
params: 'nomodeset ro root=live:http://172.16.0.254:9090/boot-images/compute/base/rocky9.5-compute-base-9.5 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
```

Then, we can modify the boot parameters with:

```bash
ochami bss boot params set -f yaml -d @/opt/workdir/nodes/boot-compute.yaml
```

## Booting the Compute Node

Now that we have our compute base image, BSS configured to point to it, and Cloud-Init configured with the post-boot configuration, we are now ready to boot a node.

Check that the boot parameters point to the base image with `ochami boot params get | jq`.

Then, power cycle `compute1` and attach to the console to watch it boot:

```bash
sudo virsh destroy compute1
sudo virsh start --console compute1
```

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
http://172.16.0.254:9090/boot-images/efi-images/compute/base/vmlinuz-5.14.0-503.38.1.el9_5.x86_64... ok
http://172.16.0.254:9090/boot-images/efi-images/compute/base/initramfs-5.14.0-503.38.1.el9_5.x86_64.img... ok
```