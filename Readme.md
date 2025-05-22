# OpenCHAMI Tutorial

Welcome to the OpenCHAMI hands-on tutorial! This guide walks you through building a complete PXE-boot & cloud-init environment for HPC compute nodes using libvirt/KVM.

---
## 📋 Prerequisites

The cloud-based instance provided for this class is detailed in [AWS_Environment.md](/AWS_Environment.md). Your instance must meet these requirements before you begin:

- **OS & Kernel**:  
  - RHEL/CentOS/Rocky 9+ or equivalent  
  - Linux kernel ≥ 5.10 with cgroups v2 enabled  
- **Packages** (minimum versions):  
  - QEMU 6.x, `virt-install` ≥ 4.x  
  - Podman 4.x   
- **Networking**:  
  - Bridge device (e.g. `br0`)
- **Storage**:  
  - NFS (or equivalent) export for `/var/lib/ochami/images`  
  - MinIO (or S3) with credentials ready
  - OCI Container registry with credentials ready
- **Tools**:  
  - `tcpdump`, `tftp`, `virsh`, `curl`  

---
## 🗺️ Conceptual Data Flows

A quick snapshot of the data flows:

1. **Discovery**: Head node learns about virtual nodes via `ochami discover`. 
2. **Image Build**: Containerized image layers → squashfs → organized with registry and served via S3.  
3. **Provisioning**: PXE boot → TFTP pulls kernel/initrd → installer.  
4. **Config & Join**: cloud-init applies user-data, finalizes OS.

---

## 🚀 Phased Tutorial Outline

> Each “Phase” is a self-contained lab with a checkpoint exercise.

### Phase I — Platform Setup

1. **Instance Preparation**  
   - Host packages, kernel modules, cgroups, bridge setup, nfs setup
   - Deploy MinIO, nginx, and registry 
   - Checkpoints: 
     - `systemctl status minio`
     - `systemctl status registry`
2. **OpenCHAMI & Core Services** 
   - Install OpenCHAMI RPMs
   - Deploy internal Certificate Authority and import signing certificate  
   - Checkpoints: 
     - `ochami bss status`
     - `systemctl list-dependencies openchami.target`

### Phase II — Boot & Image Infrastructure

3. **Static Discovery & SMD Population**  
   - Anatomy of `nodes.yaml`, `ochami discover`  
   - Checkpoint: `ochami smd component get | jq '.Components[] | select(.Type == "Node")'`  
4. **Image Builder**  
   - Define base, compute, debug container layers  
   - Build & push to registry/S3  
   - Checkpoints: 
     - `s3cmd ls -Hr s3://boot-images/`
     - `regctl tag ls demo.openchami.cluster:5000/demo/rocky-base`  
5. **PXE Boot Configuration**  
   - `boot.yaml`, BSS parameters, virt-install examples  
   - Verify DHCP options & TFTP with `tcpdump`, `tftp`  
   - Checkpoint: Successful serial console installer

### Phase III — Post-Boot & Use Cases

6. **Cloud-Init Configuration**  
   - Merging `cloud-init.yaml`, host-group overrides  
   - Customizing users, networking, mounts  
   - Checkpoint: Inspect `/var/log/cloud-init.log` on node  
7. **Virtual Compute Nodes & Demo**  
   - `virsh console`, node reboot workflows, cleanup scripts  
   - Scaling to multiple nodes with a looped script  
   - Checkpoint: Run a sample MPI job across two VMs

---

## 🔧 Troubleshooting & Tips

- **PXE ROM silent on serial**  
  - BIOS stage → VGA only; use `--extra-args 'console=ttyS0,115200n8 inst.text'`  
- **No DHCP OFFER**  
  - Verify via `sudo tcpdump -i br0 port 67 or 68`   
- **Service fai​​ls to start**  
  - Inspect `journalctl -u <service name>`, check port conflicts
- **Certficate Issues**
  - Ensure the system cert contains our root cert `grep CHAMI /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`
- **Token Issues**
  - Tokens are only valid for an hour.  Renew with `export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')` in each terminal windown

---

## 🔐 Security & Best Practices

- **Insecure default credentials** (MinIO, CoreDHCP admin).  
- **Use TLS** for API endpoints and registry.  
- **Isolate VLANs** for provisioning traffic.  
- **Harden** cloud-init scripts: avoid embedding secrets in plaintext.

---

## 📖 Further Reading & Feedback

- **OpenCHAMI Docs**: https://openchami.org  
- **cloud-init Reference**: https://cloudinit.readthedocs.io  
- **PXE/TFTP How-To**: https://wiki.archlinux.org/title/PXE  
- **Give Feedback**: [Issue Tracker or Feedback Form Link]

---

© 2025 OpenCHAMI Project · Licensed under Apache 2.0  

