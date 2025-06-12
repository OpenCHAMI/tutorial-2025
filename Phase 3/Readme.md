### Phase III — Use Cases and Customization

7. **Manage Virtual Nodes with OpenCHAMI**
   - Serve images using NFS instead of HTTP
   - Customize boot images and operating system
   - Use cloud-init groups to support different types of nodes in the same system
     - Slurm node
     - Kubernetes Work node
     - Web server
   - Use `kexec` to reboot nodes with POSTing
   - Discovery dynamically using `magellan`
   - Checkpoint: Run a sample MPI job across two VMs

---

At this point, we can use what we have learned so far in the OpenCHAMI tutorial to customize our nodes in various ways such as changing how we serve images, deriving new images, and updating our cloud-init config. This sections explores some of the use cases that you may want to explore to utilize OpenCHAMI to fit your own needs.

## Serve Images Using NFS Instead of HTTP

For this tutorial, we served images via HTTP using a local S3 bucket (MinIO) and OCI registry. We could instead serve our images using NFS by setting up and running a NFS server on the head node, include NFS tools in our base image, and configuring our nodes to work with NFS.

## Customize Boot Image and Operating System

Often, we want to allocate nodes for different purposes using different images. Let's use the base image that we created before and create another Kubernetes layer called `kubernetes-worker` based on the `base` image we created before. We would need to modify the boot script to use this new Kubernetes image and update cloud-init set up the nodes.

## Use `kexec` to reboot nodes with POSTing

## Discovery dynamically using `magellan`

In this tutorial, we used static discovery to to populate our inventory in SMD instead of dynamically discovering nodes on our network. Static discovery is good when we know beforehand the MAC address, IP address, xname, and NID of our nodes and guarantee determistic behavior. However, if we don't know these properties or if we want to update our inventory state, we can use `magellan` to scan, collect, and populate SMD with these properties.

## Run a Sample MPI job across two VMs

After getting our nodes to boot using our compute images, let's try running a test MPI job. We need to install and configure both SLURM and MPI to do so. We can do this at least two ways here:

- Create a new `compute-mpi` image similar to the `compute-debug` image using the `compute-base` image as a base. You do not have to rebuild the parent images unless you want to make changes to them, but keep in mind that you will also have to rebuild any derivative images. 

- Alternatively, we can install the necessary SLURM and MPI packages in our cloud-init config and set up or node in the `cmds` section of the config file.
