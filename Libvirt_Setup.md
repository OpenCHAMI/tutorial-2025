# Virtual Compute Nodes

## Libvirt introduction

Libvirt is an open-source virtualization management toolkit that provides a unified interface for managing various virtualization technologies, including KVM/QEMU, Xen, VMware, LXC containers, and others. Through its standardized API and set of management tools, libvirt simplifies the tasks of defining, managing, and monitoring virtual machines and networks, regardless of the underlying hypervisor or virtualization platform.

For our tutorial, we leverage a hypervisor which is built-in to the Linux Kernel. The kernel portion is called Kernel-based Virtual Machine (KVM) and the userspace component is included in QEMU.

## Libvirt Networking

In order to establish networking for the virtual nodes, we need to define a bridge network with NAT so each compute node can contact the OpenCHAMI services on the node as well as access remote resouces for package updates.  Since OpenCHAMI offers it's own dhcp server, we do not include a DHCP server as we create the network.

Create the internal network:
```bash
cat <<EOF > openchami-net.xml
<network>
  <name>openchami-net</name>
  <bridge name="virbr-openchami" />
</network>
EOF
sudo virsh net-define openchami-net.xml
sudo virsh net-start openchami-net
sudo virsh net-autostart openchami-net
```

## Virtual Compute Node Startup

Copy the UEFI variables from the stock one to a dedicated compute one:

```bash
sudo cp /usr/share/OVMF/OVMF_VARS.fd /var/lib/libvirt/qemu/nvram/compute.fd
```

Create virtual diskless compute nodes using [virsh](https://www.libvirt.org/index.html)

```bash
sudo virt-install \
  --name compute1 \
  --memory 4096 \
  --vcpus 1 \
  --disk none \
  --pxe \
  --os-variant centos-stream9 \
  --network network=openchami-net,model=virtio,mac=52:54:00:be:ef:01 \
  --graphics none \
  --console pty,target_type=serial \
  --boot loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/var/lib/libvirt/qemu/nvram/compute.fd,loader_secure=no \
  --virt-type kvm
```

We haven't set up PXE yet, so this will fail over. `Ctrl`+`]` to exit the console. We will leave it running for now.