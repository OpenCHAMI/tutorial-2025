# OpenCHAMI Tutorial

This repository walks a user through setting up an EC2 instance to test the OpenCHAMI software.

## Getting ready


If you are using this tutorial as part of an organized class, the AWS instance will be provided for you.  However, you can choose to run this independently by following the directions in [AWS_Environment.md](/AWS_Environment.md).

## Organization

The tutorial is organized into four parts.  Each part starts with slides and education followed by an exercise for students to apply what they've learned

### 1. Head Node Preparation

In a real HPC system, you'll certainly use automation to create your head node(s) to run OpenCHAMI.  For this tutorial, the student will directly interact with Podman Quadlets to create services and configurations to set up a head node that can not only control an HPC system, but also act as a virtualization platform for diskless HPC nodes.

* Head Node Preparation is covered by [Instance_Presentation.md](Instance_Preparation.md)

### 2. OpenCHAMI Installation

OpenCHAMI can be managed via Kubernetes, Docker Compose, and Podman Quadlets.  The official OpenCHAMI release process builds an RPM that includes quadlet files.  These unit files reference official containers to start and manage services.

* OpenCHAMI Installation is covered by [OpenCHAMI_Installation.md](OpenCHAMI_Installation.md)

### 3. Discover Nodes and Set Configuration

In a normal OpenCHAMI installation, we would use Magellan to discover our BMCs on a known BMC network.  With libvirt, we need to fake the discovery process by providing inventory information directly through the ochami commandline tool.

* Simulating node discovery is covered in [discovery.md](discovery.md)
* Creating system images is covered in [images.md](images.md)
* Configuring boot parameters is covered in [boot.md](boot.md)
* Adding cloud-init parameters for post-boot configuration is covered in [cloud-init.md](cloud-init.md)

### 3. Simulated HPC Nodes

Testing system management without physical nodes presents significant challenges.  Rather than expose the complexity of sourcing and configuring hardware as a prerequisite, we will use a recipe for virtualizing a network and set of diskless nodes using libvirt.  Using the `c5.metal` instance type allows us to leverage the kernel virtualization engine without emulation.  Students will learn the libvirt toolset and they apply it to create and manage diskless compute nodes.

* Libvirt-based Virtual Nodes are covered by [Virtual_Compute_Nodes.md](Virtual_Compute_Nodes.md)

### 4. OpenCHAMI Management Use Cases

Using APIs, students will use the OpenCHAMI services to create and manage a virtual HPC system.  This involves:

* Discovering your virtual nodes (discovery.md)[discovery.md]
* Creating layered system images and organizing them with an OCI registry (images.md)[images.md]
* Creating a boot configuration for compute node (boot.md)[boot.md]
* Leveraging cloud-init to customize the boot of compute nodes (cloud-init.md)[cloud-init.md]
* Updating kernel parameters for all nodes



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
