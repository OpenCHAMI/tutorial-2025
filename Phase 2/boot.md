# Boot Parameters

## Contents

- [Boot Parameters](#boot-parameters)
  - [Contents](#contents)
- [Introduction](#introduction)
- [Using `ochami` for Managing Boot Parameters](#using-ochami-for-managing-boot-parameters)
  - [Retrieving Boot Parameters](#retrieving-boot-parameters)
  - [Adding New Boot Parameters](#adding-new-boot-parameters)
- [Booting the Debug Image](#booting-the-debug-image)
  - [Configuring Debug Boot Parameters](#configuring-debug-boot-parameters)
  - [Boot Compute VM into Debug Image](#reboot-compute-vm-into-debug-image)

# Introduction

SMD may know about the nodes so that DHCP can give them their IP address and point them to their boot script, but that boot script won't do anything useful if no boot parameters exist.

The `ochami` CLI tool can do this for us. Let's take a look at some uses of it.

Let's add some. We will be using the `ochami` CLI tool for this.

# Using `ochami` for Managing Boot Parameters

## Retrieving Boot Parameters

We can get the boot parameters for all known nodes (in JSON form):

```bash
ochami bss boot params get | jq
```

We can filter by node as well:

```bash
ochami bss boot params get --mac 52:54:00:be:ef:01,52:54:00:be:ef:02 | jq
```

## Adding New Boot Parameters

The `ochami bss boot params add` command will work for this task, but it will fail if we want to overwrite existing parameters. For more idempotency, we can use `ochami boot params set`. We will use this from here on out. See **ochami-bss**(1) for more information.

To set boot parameters, we need to pass:

1. The identity of the node that they will be for (MAC address, name, or node ID number)
1. At least one of:
   1. URI to kernel file
   2. URI to initrd file
   3. Kernel command line arguments

# Booting the Debug Image

## Configuring Debug Boot Parameters

Let's test that we can actually boot a working image by booting the debug image we created in the last section.

Create `/opt/workdir/nodes/boot-debug.yaml`:

```yaml
kernel: 'http://172.16.0.254:9000/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-503.38.1.el9_5.x86_64'
initrd: 'http://172.16.0.254:9090/boot-images/efi-images/compute/debug/initramfs-5.14.0-503.38.1.el9_5.x86_64.img'
params: 'nomodeset ro root=live:http://172.16.0.254:9090/boot-images/compute/debug/rocky9.5-compute-debug-9.5 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init'
macs:
  - 52:54:00:be:ef:01
  - 52:54:00:be:ef:02
  - 52:54:00:be:ef:03
  - 52:54:00:be:ef:04
  - 52:54:00:be:ef:05
```

Notice:

- The `kernel` and `initrd` values prepend the base S3 HTTP URI (`http://demo.openchami.cluster:9090`) to the S3 paths to those artifacts (output from `s3cmd ls`).
  - This is the same for the `root=` kernel command line argument, and uses the S3 path to the SquashFS image.
- `cloud-init=disabled` in `params`. This will be enabled when we run the compute base image and configure cloud-init.
- We assign these parameters to a list of `macs`.
  - Per-group assignment is in the works!

Let's assign these boot parameters:

```bash
ochami bss boot params set -f yaml -d @/opt/workdir/nodes/boot-debug.yaml
```

We can verify that these parameters were correctly assigned with:

```bash
ochami bss boot params get | jq
```

The output should be:

```json
[
  {
    "cloud-init": {
      "meta-data": null,
      "phone-home": {
        "fqdn": "",
        "hostname": "",
        "instance_id": "",
        "pub_key_dsa": "",
        "pub_key_ecdsa": "",
        "pub_key_rsa": ""
      },
      "user-data": null
    },
    "initrd": "http://172.16.0.254:9090/boot-images/efi-images/compute/debug/initramfs-5.14.0-503.38.1.el9_5.x86_64.img",
    "kernel": "http://172.16.0.254:9090/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-503.38.1.el9_5.x86_64",
    "macs": [
      "52:54:00:be:ef:01",
      "52:54:00:be:ef:02",
      "52:54:00:be:ef:03",
      "52:54:00:be:ef:04",
      "52:54:00:be:ef:05"
    ],
    "params": "nomodeset ro root=live:http://172.16.0.254:9090/boot-images/compute/debug/rocky9.5-compute-debug-9.5 ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 selinux=0 console=ttyS0,115200 ip6=off cloud-init=enabled ds=nocloud-net;s=http://172.16.0.254:8081/cloud-init",
  }
]
```

We should now be ready to boot the image!

## Boot Compute VM into Debug Image

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



We should see our IP address get assigned, kernel and initramfs downloaded, and SquashFS loaded:

```
  Station IP address is 172.16.1.1

  Server IP address is 172.16.1.253
  NBP filename is ipxe-x86_64.efi
  NBP filesize is 1079296 Bytes
 Downloading NBP file...

  NBP file downloaded successfully.
[...snip...]
tftp://172.16.1.253:69/config.ipxe... ok
Booting from http://172.16.1.253:8081/boot/v1/bootscript?mac=52:54:00:be:ef:01
http://172.16.1.253:8081/boot/v1/bootscript... ok
http://172.16.1.253:9090/boot-images/efi-images/compute/debug/vmlinuz-5.14.0-503.38.1.el9_5.x86_64... ok
http://172.16.1.253:9090/boot-images/efi-images/compute/debug/initramfs-5.14.0-503.38.1.el9_5.x86_64.img... ok

[...snip...]

         Starting dracut initqueue hook...
[    2.787513] dracut-initqueue[542]:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
[    2.789189] dracut-initqueue[542]:                                  Dload  Upload   Total   Spent    Left  Speed
[  OK  ] Finished dracut initqueue hook.
```

When all done, we should see a login prompt:

```
Rocky Linux 9.5 (Blue Onyx)
Kernel 5.14.0-503.38.1.el9_5.x86_64 on an x86_64

nid0001 login:
```

Login with `testuser` for the username and password and check that we are on the live image:

```bash
[testuser@nid0001 ~]$ findmnt /
TARGET SOURCE        FSTYPE  OPTIONS
/      LiveOS_rootfs overlay rw,relatime,lowerdir=/run/rootfsbase,upperdir=/run/
```

Excellent! Play around a bit more and then logout. Use `Ctrl`+`]` to exit the Virsh console.

Before we switch to the base compute image, we should first configure Cloud-Init, our post-boot configuration service, so that we can login via SSH.