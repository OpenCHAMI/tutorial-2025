# AWS Tutorial Environment

For this tutorial, you will be provided with your own EC2 instance and ssh key for access to it.  If you would like to replicate it outside the tutorial environment, here are the relevant details.

## Instance Information

In order to run multiple compute nodes as VMs inside your instance, you will need plenty of RAM.  We've found that at least 4G per guest is necessary.  It's possible to oversubscribe the instances, but performance suffers.  We chose c5.metal instances to optimize for RAM and cost. 

In addition, while the aarch (Graviton) instances are cheaper than the comparable x86 instances, not all of the software we rely on is confirmed to work on an ARM system.  Future versions of this tutorial will likely switch to cheaper ARM instances.

### Operating System (Rocky 9)

The Operating System for the tutorial is expected to be Rocky Linux version 9.  Official AMIs are available on the AWS Marketplace.  See [Rocky Linux AMIs](https://aws.amazon.com/marketplace/seller-profile?id=01538adc-2664-49d5-b926-3381dffce12d) for the latest AMIs in your region and availability zone.  The entitlement process is easy and doesn't add cost to the standard instance usage.

### Storage

Default root disks for instances are too small for storing the squashfs images needed.  Our launch template expands `/dev/sda1` to 100G.  This doesn't automatically extend the filesystem which must be done at boot time with cloud-init.

## Launch Template

AWS offers the ability to stand up multiple instances based on the same template.  For tutorial development, we found the templates to be less error-prone than creating individual instances without template.  We recommend creating the template and then starting instances from that template.


### Cloud-Init

Just like OpenCHAMI, AWS provides teh ability to inject cloud-config data at runtime.  In the "Advanced details" section of the template or instance definition, you will find a text box for `User data`.  This is what we're using for the tutorial:

**user-data:**
```
#cloud-config

packages:
- ansible-core
- bash-completion
- buildah
- dnsmasq
- git
- libvirt
- nfs-utils
- openssl
- podman
- qemu-kvm
- s3cmd
- vim
- virt-install
- virt-manager

runcmd:
  - dnf install -y epel-release
  - dnf install -y s3cmd
  - systemctl enable libvirtd
  - systemctl start libvirtd
  - usermod -aG libvirt rocky
  - newgrp libvirt
  - sudo growpart /dev/xvda 4
  - sudo pvresize /dev/xvda4
  - sudo lvextend -l +100%FREE /dev/rocky/lvroot
  - sudo xfs_growfs /
```
