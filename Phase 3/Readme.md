### Phase III — Post-Boot & Use Cases

6. **Cloud-Init Configuration**  
   - Merging `cloud-init.yaml`, host-group overrides   
   - Customizing users, networking, mounts  
   - Checkpoint: Inspect `/var/log/cloud-init.log` on node  
7. **Manage Virtual Nodes with OpenCHAMI**  
   - Replace http root filesystem with NFS root filesystem  
   - Change boot image and/or Linux distribution
   - Using groups to support different kinds of nodes in the same system  
     - Slurm node
     - Kubernetes Work node
     - AI Worker node?
     - Web server
   - Checkpoint: Run a sample MPI job across two VMs

---

OpenCHAMI's cloud-init metadata server 

[Cloud-Init](https://cloudinit.readthedocs.io/en/latest/index.html) is the way that OpenCHAMI provides post-boot configuration. The idea is to keep the image generic without any sensitive data like secrets and let cloud-init take care of that data.

Cloud-Init works by having an API server that keeps track of the configuration for all nodes, and nodes fetch their configuration from the server via a cloud-init client installed in the node image. The node configuration is split up into meta-data (variables) and a configuration specification that can optionally be templated using the meta-data.

OpenCHAMI [has its own flavor](https://github.com/OpenCHAMI/cloud-init) of Cloud-Init server that utilizes groups in SMD to provide the appropriate configuration. (This is why we added our compute nodes to a "compute" group during discovery.)

In a typical OpenCHAMI Cloud-Init setup, the configuration is set up in three phases:

1. Configure cluster-wide default meta-data
2. Configure group-level cloud-init configuration with optional group meta-data
3. (_OPTIONAL_) Configure node-specific cloud-init configuration and meta-data

We will be using the OpenCHAMI Cloud-Init server in this tutorial for node post-boot configuration.

## Configuring Your Cluster's Meta-Data

Let's create a directory for storing our configuration:

```bash
mkdir -p /opt/workdir/cloud-init
cd /opt/workdir/cloud-init
```

Now, create a new SSH key on the head node and follow all of the prompts:

```bash
ssh-keygen -r 2048 -t ed25519
```

The new that was generated can be found in `~/.ssh/id_ed25519.pub`. We're going to need this to include this in the cloud-init meta-data.

```bash
cat ~/.ssh/id_ed25519.pub
```

Create `defaults.yaml` with the following content replacing the `<YOUR SSH KEY GOES HERE>` line with your SSH key from above:

```yaml
---
base-url: "http://172.16.0.254:8081/cloud-init"
cluster-name: "demo"
nid-length: 3
public-keys:
- "<YOUR SSH KEY GOES HERE>"
short-name: "nid"
```

Then, we set the cloud-init defaults using the `ochami` CLI:

```bash
ochami cloud-init defaults set -f yaml -d @/opt/workdir/cloud-init/defaults.yaml
```

e can verify that these values were set with:

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
    "<YOUR SSH KEY>"
  ],
  "short-name": "nid"
}
```