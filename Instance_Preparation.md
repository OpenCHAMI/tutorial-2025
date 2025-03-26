# Instance Preparation

Once your AMI has launched as an instance, it will use the cloud-int process to install all the OpenCHAMI prerequisites.  This will take about five minutes depending on the status of the internal AWS network and your instance type.  Checking the process list for dnf commands is a reasonable way to ascertain if the process is complete.  You can also check the cloud-init logs in `/var/log/cloud-init`.  Errors are often logged while cloud-init continues without failure.

## Set up NFS for filesystems

**Create the directory and make sure it is properly shared.**

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

## Update /etc/hosts 

**Add the demo hostname to /etc/hosts so that all the certs and urls work**
   ```bash
   echo "127.0.0.1 demo.openchami.cluster" | sudo tee -a /etc/hosts > /dev/null
   ```

## Set up a local container registry and working directory for system images

  - Create a local directory for storing the container images
    ```bash
    sudo mkdir /opt/containers/ && sudo chown rocky /opt/containers/
    ```

  - Start the local container registry
    ```bash
    podman container run -dt -p 5000:5000 -v /opt/containers:/var/lib/registry:Z --name registry docker.io/library/registry:2
    ```

  - Set up the working directories we'll use for images

    SELinux treats home directories specially.  To avoid cgroups conflicting with SELinux enforcement, we set up a working directory outside our home directory.
    ```bash
    sudo mkdir -p /opt/workdir  && sudo chown -R rocky:rocky /opt/workdir && cd /opt/workdir
    ```

## Install OpenCHAMI

There are several ways to install and activate OpenCHAMI on a head node.  For this tutorial, we will use the signed RPM from the [openchami/release](https://github.com/openchami/release) repository.  This RPM mainly exists to hold systemd unit filed which run containers as podman quadlets.  As part of the installation, the RPM pulls all the OpenCHAMI containers from the github container registry.  The RPM itself is signed and each container is attested publicly through Sigstore tooling integrated by GitHub.  You can read more about the attestation process in the [Github Documentation](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds).

To make things easier for the tutorial, we have created a [bash script](https://gist.github.com/alexlovelltroy/96bfc8bb6f59c0845617a0dc659871de) that:

1. identifies the latest release rpm
1. downloads the public signing key for OpenCHAMI
1. downloads the rpm
1. verifies the signature
1. installs the RPM

### Install Command
```bash
curl -fsSL https://gist.githubusercontent.com/alexlovelltroy/96bfc8bb6f59c0845617a0dc659871de/raw | bash
```

### Review Installed Containers

The post-install script for the RPM pulls all the official containers from the github container registry and stores them for use later.  You can review them with `podman`.

```bash
sudo podman images
```

### Start OpenCHAMI

Even though OpenCHAMI runs as a collection of containers, the podman integration with systemd allows us to start, stop, and trace OpenCHAMI as a set of dependent services through the `openchami.target` unit.

```bash
sudo systemctl start openchami.target
sudo systemctl list-dependencies openchami.target
```
