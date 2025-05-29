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

