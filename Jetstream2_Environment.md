# Jetstream2 Tutorial Environment

For this tutorial, you will be provided with your own compute instance and ssh key for access to it.  If you would like to replicate it outside the tutorial environment, here are the relevant details.

## Instance Information

In order to run multiple compute nodes as VMs inside your instance, you will need plenty of RAM.  We've found that at least 4G per guest is necessary.  It's possible to oversubscribe the instances, but performance suffers.  We chose m3.medium (8GB RAM) instances to optimize for RAM and cost.

In addition, we are using x86 instances since not all of the software we rely on is confirmed to work on an ARM system.  Future versions of this tutorial will likely switch to cheaper ARM instances.

### Operating System (Rocky 9)

The Operating System for the tutorial is expected to be Rocky Linux version 9.  Official images are available, for example **Featured-RockyLinux9**. However, see note about SELinux below.

### Storage

We use the default 60GB root disk size for the tutorial. In the launch template below, we extend the filesystem to use the full disk.

## Launch Template

Jetstream2 offers the ability to stand up multiple instances based on the same template.  For tutorial development, we found the templates to be less error-prone than creating individual instances withour template.  We recommend creating the template and then starting instances from that template.

### Cloud-Init

Just like OpenCHAMI, Jetstream2 provides the ability to inject cloud-config data at runtime.  In the "Advanced Options`" section of the template or instance definition, you will find a text box marked **Boot Script**. Underneath the following header:

```
--=================exosphere-user-data====
Content-Transfer-Encoding: 7bit
Content-Type: text/cloud-config
Content-Disposition: attachment; filename="exosphere.yml"
```

This is what we're using for the tutorial:

> [!NOTE]
> The Rocky 9 Jetstream2 image does not allow containers to accept TCP connections, which prevents connections to Quadlet services. As a mitigation, the below cloud-config adds/enables/starts a Systemd service that marks the `container\_t` type as permissive.

```yaml
#cloud-config

packages:
  - ansible-core
  - buildah
  - dnsmasq
  - git
  - libvirt
  - nfs-utils
  - openssl
  - podman
  - qemu-kvm
  - vim
  - virt-install
  - virt-manager

write_files:
  - path: /etc/systemd/system/selinux-container-permissive.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Make container_t domain permissive
      After=network.target

      [Service]
      Type=oneshot
      ExecStart=/usr/sbin/semanage permissive -a container_t
      Restart=on-failure
      RestartSec=5
      StartLimitBurst=5

      [Install]
      WantedBy=multi-user.target

# Post-package installation commands
runcmd:
  - dnf install -y epel-release
  - dnf install -y s3cmd
  - systemctl enable --now libvirtd
  - newgrp libvirt
  - usermod -aG libvirt rocky
  - sudo growpart /dev/xvda 4
  - sudo pvresize /dev/xvda4
  - sudo lvextend -l +100%FREE /dev/rocky/lvroot
  - sudo xfs_growfs /
  - systemctl daemon-reload
  - systemctl enable selinux-container-permissive
  - systemctl start selinux-container-permissive
```
