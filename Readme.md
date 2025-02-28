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

1. We will serve the root filesystems of our diskless nodes using nfs.  Configure NFS to serve your squashfs nfsroot with as much performance as possible.
  - Create `/opt/nfsroot` to store our images
    ```bash
    sudo mkdir /opt/nfsroot && sudo chown rocky /opt/nfsroot
    ```
  - Create `/etc/exports` with the following contents to export the `/opt/nfsroot` directory for use by our compute nodes
    ```bash
    /opt/nfsroot *(ro,no_root_squash,no_subtree_check,noatime,async,fsid=0)
    ```
  - Reload the nfs daemon
    ```bash
    modprobe -r nfsd && modprobe nfsd
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
  `sudo systemctl list-dependencies openchami.target`
  - Download the client rpm [https://github.com/OpenCHAMI/ochami/releases](https://github.com/OpenCHAMI/ochami/releases)
  - Install the RPMs and verify all services are running
    ```bash
    curl -fsSL https://gist.githubusercontent.com/alexlovelltroy/96bfc8bb6f59c0845617a0dc659871de/raw | bash
    sudo systemctl start openchami.target
    sudo systemctl list-dependencies openchami.target

    ```
  - Use podman to pull the public root certificate from our internal ACME certificate authority
  - Use the `ochami` command to verify that unauthenticated operations are successful
  
1. Use the OpenCHAMI image-builder to configure a system image for the compute nodes to use.
  - Run a local container registry: `podman container run -dt -p 5000:5000 --name registry docker.io/library/registry:2`
1. Manage system image(s) in a container registry
  - Create a system image for the computes: `podman run --rm --device /dev/fuse --security-opt label=disable -v ${PWD}:/home/builder/:Z ghcr.io/openchami/image-build image-build --config image-configs/rocky-9-base.yaml --log-level DEBUG`
    `podman run --rm --userns=keep-id --device /dev/fuse --security-opt label=disable -v /opt/workdir/:/home/builder/:Z ghcr.io/openchami/image-build image-build --config rocky-9-base.yaml --log-level DEBUG`
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

# Configuration

The release RPM includes a set of configurations that make a few assumptions about your setup.  All of these can be changed before starting the system to work with your environment.  The release RPM puts all configuration files in /etc/openchami/

## Environment variables

All containers share the same environment variables file for the demo.  We recommend splitting them up per service where keys/secrets are concerned by following the comments in the openchami.env file

## coredhcp configuration

The OpenCHAMI dhcp server is a coredhcp container with a custom plugin that interfaces with smd to ensure that changes in node ip are quickly and accurately reflected.  It uses a plugin configuration at /etc/openchami/coredhcp.yaml

### listen
The yaml below instructs the container to listen on an interface called `virbr-openchami`.  If you are running this configuration for local development/testing, you will need to have this interface configured as a virtual bridge interface.  On a real system, you will need to change the listen interface.  CoreDHCP will use this interface to listen for DHCP requests.

### plugins

The plugins section of the `coredhcp` configuration is read by our coresmd plugin (and others) to control the way that addresses and netboot parameters are handled for each DHCP request.  They describe the ip address of the server, the router and netmask, and how to connect to the rest of the OpenCHAMI system.  The `bootloop` directive instructs the plugin to provide a reboot ipxe script to unknown nodes.

```yaml
server4:
  listen:
    - "%virbr-openchami"
  plugins:
    - server_id: 172.16.0.2
    - dns: 172.16.0.2
    - router: 172.16.0.1
    - netmask: 255.255.255.0
    - coresmd: https://demo.openchami.cluster:8443 http://172.16.0.2:8081 /root_ca/root_ca.crt 30s 1h
    - bootloop: /tmp/coredhcp.db default 5m 172.16.0.200 172.16.0.250
```

## haproxy configuration

Haproxy is a reverse proxy that allows all of our microservices to run in separate containers, but only one hostname/url is needed to access them all.  You are not likely to need to change it at all from system to system.  As configured, each microservice is a unique backend that handles a subset of URLs within the microservice.  Since each container has a predictable name within the podman (or docker) network, the microservices only need to be referenced by name.

## Hydra Configuration

Hydra is our JWT provider.  It's configuration file is as narrow as possible in this example and shouldn't need to be changed.  Depending on your own needs, you may want to consult the full list at [Hydra's Documentation](https://www.ory.sh/docs/hydra/reference/configuration).

```yaml
serve:
  cookies:
    same_site_mode: Lax

oidc:
  dynamic_client_registration:
    enabled: true
  subject_identifiers:
    supported_types:
      - public

oauth2:
  grant:
    jwt:
      jti_optional: true
      iat_optional: true
      max_ttl: 24h

strategies:
  access_token: jwt
```

## OPAAL Configuration

The OPAAL service is a shim that we use to connect our external authentication service (gitlab) with our internal authorization service (hydra).  We intend to deprecate it in favor of a third-party system in the future, but it is necessary at this stage in OpenCHAMI development.  The yaml configuration file lists many of the urls that are necessary to convert from an OIDC login flow to our token-granting service.  If you change things like the cluster and domain names, you will need to update this file.

**NB** OPAAL is not used in this tutorial.  We create our own access tokens directly without an OIDC login.

# Notes

Troubleshooting can be a challenge.  Here are some commands that allow you to review everything.

* `sudo systemctl start openchami.target`
* `sudo systemctl list-dependencies openchami.target`
* `sudo systemctl status openchami.target`
* Fetch the automatically created root certificate: `sudo podman run --rm --network openchami-cert-internal docker.io/curlimages/curl -sk https://step-ca:9000/roots.pem`

# TODO

- [ ] Add TPMs to the libvirt VMs for demonstration of TPM attestation
- [ ] Add tooling to control libvirt nodes with virtual bmcs
- [ ] Add `ochami` commands to create the virtual nodes before attempting to boot them
- [ ] Add `ochami` commands to create groups and add virtual nodes to groups
- [ ] Add `ochami` commands to configure boot using image, kernel, and cloud-init for each group of nodes
- [ ] Add `ochami` commands to switch from rocky 9 to rocky 8 on a subset of the compute nodes
- [ ] Create a dedicated md file that covers ACME certificate rotation in the context of OpenCHAMI.  Show how to set up cron to do daily rotation
- [ ] Create a dedicated md file that describes the authentication flow and how to connect an OpenCHAMI instance to github/gitlab for users