# OpenCHAMI Tutorial

This repository walks a user through setting up an EC2 instance to test the OpenCHAMI software.

## Getting ready

If you are using this tutorial as part of an organized class, the AWS instance will be provided for you.  However, you can choose to run this independently by following the directions in [AWS_Environment.md](/AWS_Environment.md).

## Organization

The tutorial is organized into four parts.  Each part starts with slides and education followed by an exercise for students to apply what they've learned

### 1. Head Node Preparation

In a real HPC system, you'll certainly use automation to create your head node(s) to run OpenCHAMI.  For this tutorial, the student will directly interact with Podman Quadlets to create services and configurations to set up a head node that can not only control an HPC system, but also act as a virtualization platform for diskless HPC nodes.

* Head Node Preparation is covered by [Instance_Presentation.md](Instance_Preparation.md)

### 2. OpenCHAMI installation

OpenCHAMI can be managed via Kubernetes, Docker Compose, and Podman Quadlets.  The official OpenCHAMI release process builds an RPM that includes quadlet files.  These unit files reference official containers to start and manage services.

* OpenCHAMI Installation is covered by [OpenCHAMI_Installation.md](OpenCHAMI_Installation.md)

### 3. Simulated HPC Nodes

Testing system management without physical nodes presents significant challenges.  Rather than expose the complexity of sourcing and configuring hardware as a prerequisite, we will use a recipe for virtualizing a network and set of diskless nodes using libvirt.  Using the `c5.metal` instance type allows us to leverage the kernel virtualization engine without emulation.  Students will learn the libvirt toolset and they apply it to create and manage diskless compute nodes.

* Libvirt-based Virtual Nodes are covered by [Virtual_Compute_Nodes.md](Virtual_Compute_Nodes.md)

### 4. OpenCHAMI Management Use Cases

Using APIs, students will use the OpenCHAMI services to create and manage a virtual HPC system.  This involves:

* Creating layered system images and organizing them with an OCI registry
* Creating a boot configuration for compute node
* Converting a compute node to a front-end node
* Updating kernel parameters for all nodes

See [Instance_Preparation.md](/Instance_Preparation.md) for the manual steps to prepare a node to be an OpenCHAMI head node.
1. Create the virtual node information
   - Each node will need a dedicated MAC address that we will load into OpenCHAMI as a "discovered" node.  Since we'll probably be restarting these diskless nodes fairly regularly, we should keep a list of our mac addresses handy.  For the tutorial, we'll use MACs that have already been assigned to RedHat for QEMU so there's no chance of a collision with a real MAC.
   ```
     52:54:00:be:ef:01
     52:54:00:be:ef:02
     52:54:00:be:ef:03
     52:54:00:be:ef:04
     52:54:00:be:ef:05
   ```
1. Create the internal network for the OpenCHAMI tutorial
   ```
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


  - Use podman to pull the public root certificate from our internal ACME certificate authority
  - Use the `ochami` command to verify that unauthenticated operations are successful
1. Use the OpenCHAMI image-builder to configure a system image for the compute nodes to use.
  - Run a local container registry: `podman container run -dt -p 5000:5000 --name registry docker.io/library/registry:2`
  - Copy the image definition from [image-configs/rocky-9-base.yaml](/image-configs/rocky-9-base.yaml) to `/opt/workdir/rocky9-base.yaml`
  - Create a system image for the computes:
  ```bash
  podman run --rm --device /dev/fuse \
  --security-opt label=disable \
  -v ${PWD}:/data/:Z,ro ghcr.io/openchami/image-build \
  image-build --config /data/rocky9-base.yaml --log-level DEBUG
  ```

1. Make system images from a container registry available for nfs boot
   ```bash
   ./scripts/import_image.sh localhost:5000/rocky9-base:9 /opt/nfsroot/rocky-9-base/
   ```
1. Create virtual diskless compute nodes using [virsh](https://www.libvirt.org/index.html), the linux kernel virtualization toolkit
   ```bash
   sudo virt-install --name compute1 \
   --memory 4096 --vcpus 1 \
   --disk none \
   --pxe \
   --os-variant generic \
   --mac '52:54:00:be:ef:01' \
   --network network:openchami-net,model=virtio \
   --boot network,hd
   ```
1. Use the OpenCHAMI API to control the node identity and boot configuration of the diskless nodes
1. Add OpenHPC to the cluster and set up slurm for a hello world job
1. Update JWTs and rotate certs

# Use cases

1. Use `ochami` and a fake-discovery file to create nodes in smd and then get information about them through the cli.
   - [ ] Document the fake-discovery file format and link to this tutorial
   - [ ] Document how this is different with Magellan
2. Use `ochami` to update group membership for nodes and set up bss parameters per group and then lookup boot characteristics of individual nodes.
   - [ ] BSS may not currently support boot parameters per group.  We need to check and possibly update.  See [BSS Issue #50](https://github.com/OpenCHAMI/bss/issues/50)
   - [ ] Without a BSS that understands groups, we may need to show through scripting how to get the MACs for all nodes in a group and set the boot information directly on each.
   - [ ] Confirm that ochami command can support the bss group functionality once bss is fixed
3. Use `ochami` to set cloud-init info for a group and use impersonation to confirm it at the node level.
   - [ ] Create example cloud-config files for students to use. (in this repo?)
4. Students should be able to configure three nodes as front-end, compute, and io with different configurations via groups
5. Students should be able to create a new kubernetes image and switch from slurm to kubernetes via reboot of a node


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

- [ ] Add `ochami` commands to create groups and add virtual nodes to groups
- [ ] Add `ochami` commands to configure boot using image, kernel, and cloud-init for each group of nodes
- [ ] Add `ochami` commands to switch from rocky 9 to rocky 8 on a subset of the compute nodes (Kubernetes?)
- [ ] Create a dedicated md file that covers ACME certificate rotation in the context of OpenCHAMI.  Show how to set up cron to do daily rotation
- [ ] Create a dedicated md file that describes the authentication flow and how to connect an OpenCHAMI instance to github/gitlab for users
