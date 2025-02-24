# OpenCHAMI Tutorial

This repository walks a user through setting up an EC2 instance to test the OpenCHAMI software.

1. Start and access an EC2 instance (or access one that has been provisioned for you)
    - Use a cheap(er) aarch instance
    - Use a launch template that allows you to preload some packages we'll need
    - **user-data:**
      ```
       #cloud-config
       repo_update: true
       repo_upgrade: all

       packages:
       - libvirt
       - qemu-kvm
       - virt-install
       - virt-manager 
       - dnsmasq
       - podman
       - buildah
       - git
       - vim
       - ansible-core
       - openssl
       - nfs-utils

       runcmd:
       - systemctl enable --now libvirtd
       - systemctl start libvirtd
       - usermod -aG libvirt rocky
       - newgrp libvirt
     ```
1. Create the virtual node information
  - Each node will need a dedicated MAC address that we will load into OpenCHAMI as a "discovered" node.  Since we'll probably be restarting these diskless nodes fairly regularly, we should keep a list of our mac addresses handy.  For the tutorial, we'll use MACs that have already been assigned to RedHat for QEMU so there's no chance of a collision with a real MAC.
  ```
     52:54:00:be:ef:01
     52:54:00:be:ef:02
     52:54:00:be:ef:03
     52:54:00:be:ef:04
     52:54:00:be:ef:05
     52:54:00:be:ef:06
     52:54:00:be:ef:07
     52:54:00:be:ef:08
     52:54:00:be:ef:09
     52:54:00:be:ef:10
     52:54:00:be:ef:11
     52:54:00:be:ef:12
     52:54:00:be:ef:13
     52:54:00:be:ef:14
     52:54:00:be:ef:15
     52:54:00:be:ef:16
  ```
  - TODO: Add tpms to this setup. virt-install doesn't make this terribly easy (https://github.com/tompreston/qemu-ovmf-swtpm and https://github.com/virt-manager/virt-manager/blob/main/man/virt-install.rst#--tpm)
  - 
1. Create the internal network for the OpenCHAMI tutorial
   ```
   cat <<EOF > openchami-net.xml
   <network>
     <name>openchami-net</name>
     <bridge name="virbr-openchami" />
     <forward mode='nat'/>
      <ip address="172.16.0.1" netmask="255.255.255.0">
      </ip>
   </network>
   EOF

   sudo virsh net-define openchami-net.xml
   sudo virsh net-start openchami-net
   sudo virsh net-autostart openchami-net
   ```

1. Add the demo hostname to /etc/hosts so that all the certs and urls work

   ` echo 127.0.0.1   demo.openchami.cluster >> /etc/hosts`

1. Install OpenCHAMI on the EC2 instance and familiarize yourself with the components.
  - Download the release RPM [https://github.com/OpenCHAMI/release/releases](https://github.com/OpenCHAMI/release/releases)
  - Download the client rpm [https://github.com/OpenCHAMI/ochami/releases](https://github.com/OpenCHAMI/ochami/releases)
  - Install the RPMs and verify all services are running
    ```

    ```
  - Use podman to pull the public root certificate from our internal ACME certificate authority
  - Use the `ochami` command to verify that unauthenticated operations are successful
  
1. Use the OpenCHAMI image-builder to configure a system image for the compute nodes to use.
  - Run a local container registry: ` podman container run -dt -p 5000:5000 --name registry docker.io/library/registry:2`
1. Manage system image(s) in a container registry
  - Create a system image for the computes: ` podman run --rm --device /dev/fuse --security-opt label=disable -v ${PWD}:/home/builder/:Z ghcr.io/openchami/image-build image-build --config image-configs/rocky-9-base.yaml --log-level DEBUG`
1. Make system images from a container registry available for nfs boot
1. Create virtual diskless compute nodes using [virsh](https://www.libvirt.org/index.html), the linux kernel virtualization toolkit

```bash
sudo virt-install --name compute1 \
--memory 4096 --vcpus 1 \
--disk none \
--pxe \
--os-variant generic
--mac '52:54:00:be:ef:01'
--network network:openchami-net,model=virtio
--boot network,hd
```
1. Use the OpenCHAMI API to control the node identity and boot configuration of the diskless nodes
1. Add OpenHPC to the cluster and set up slurm for a hello world job
1. Update JWTs and rotate certs

# Notes

Troubleshooting can be a challenge.  Here are some commands that allow you to review everything.

* `sudo systemctl list-dependencies openchami.target`
* `sudo systemctl status openchami.target`
* `sudo podman run --rm --network openchami-cert-internal docker.io/curlimages/curl -sk https://step-ca:9000/roots.pem`