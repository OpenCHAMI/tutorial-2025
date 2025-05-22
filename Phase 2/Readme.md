# Phase II — Boot & Image Infrastructure

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

---

# Node Discovery for Inventory


In order for OpenCHAMI to be useful, the State Management Database (SMD) needs to be populated with node information. This can be done one of two ways: _static_ discovery via [the `ochami` CLI](https://github.com/OpenCHAMI/ochami) or _dynamic_ discovery via [the `magellan` CLI](https://github.com/OpenCHAMI/magellan).

Static discovery is predictable and easily reproduceable, so we will use it in this tutorial.

## Dynamic Discovery Overview

Dynamic discovery happens via Redfish using `magellan`.

At a high level, `magellan` `scan`s a specified network for hosts running a Redfish server (e.g. BMCs). Once it knows which IPs are using Redfish, the tool can `crawl` each BMC's Redfish structure to get more detailed information about it, then `collect` this information and send it to SMD.

When combined with DHCP dynamically handing out IPs, this process can be non-deterministic.

## Static Discovery Overview

Static discovery happens via `ochami` by giving it a static discovery file. "Discovery" is a bit of a misnomer as nothing is actually discovered. Instead, predefined node data is given to SMD which creates the necessary internal structures to boot nodes.

### Anatomy of a Static Discovery File

`ochami` accepts a file in either JSON or YAML format. We will use YAML here since it is more easily read by humans. The structure of this file is an array of node data structures mapped to a `nodes` key.