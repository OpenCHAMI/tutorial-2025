# Discovery and SMD Population

## Contents

- [Discovery and SMD Population](#discovery-and-smd-population)
  - [Contents](#contents)
- [Introduction](#introduction)
  - [Prerequisites](#prerequisites)
  - [Dynamic Discovery Overview](#dynamic-discovery-overview)
  - [Static Discovery Overview](#static-discovery-overview)
- [Anatomy of a Static Discovery File](#anatomy-of-a-static-discovery-file)
- [Using Static Discovery to Populate SMD](#using-static-discovery-to-populate-smd)

# Introduction

In order for OpenCHAMI to be useful, the State Management Database (SMD) needs to be populated with node information. This can be done one of two ways: _static_ discovery via [the `ochami` CLI](https://github.com/OpenCHAMI/ochami) or _dynamic_ discovery via [the `magellan` CLI](https://github.com/OpenCHAMI/magellan).

Static discovery is predictable and easily reproduceable, so we will use it in this tutorial.

## Prerequisites

Make sure you have the `ochami` CLI installed and configued and that your access token is set and not expired. Refer to the [OpenCHAMI Installation guide](OpenCHAMI_Installation) for details on [installing the `ochami` tool](OpenCHAMI_Installation.md#install-and-configure-openchami-client) and [generating an access token](OpenCHAMI_Installation#generating-authentication-token).

## Dynamic Discovery Overview

Dynamic discovery happens via Redfish using `magellan`.

At a high level, `magellan` `scan`s a specified network for hosts running a Redfish server (e.g. BMCs). Once it knows which IPs are using Redfish, the tool can `crawl` each BMC's Redfish structure to get more detailed information about it, then `collect` this information and send it to SMD.

When combined with DHCP dynamically handing out IPs, this process can be non-deterministic.

## Static Discovery Overview

Static discovery happens via `ochami` by giving it a static discovery file. "Discovery" is a bit of a misnomer as nothing is actually discovered. Instead, predefined node data is given to SMD.

# Anatomy of a Static Discovery File

`ochami` accepts a file in either JSON or YAML format. We will use YAML here since it is more easily read by humans. The structure of this file is an array of node data structures mapped to a `nodes` key.

```yaml
nodes:
- name: node01
  nid: 1
  xname: x1000c1s7b0n0
  bmc_mac: de:ca:fc:0f:ee:ee
  bmc_ip: 172.16.0.101
  group: compute
  interfaces:
  - mac_addr: de:ad:be:ee:ee:f1
    ip_addrs:
    - name: internal
      ip_addr: 172.16.0.1
  - mac_addr: de:ad:be:ee:ee:f2
    ip_addrs:
    - name: external
      ip_addr: 10.15.3.100
  - mac_addr: 02:00:00:91:31:b3
    ip_addrs:
    - name: HSN
      ip_addr: 192.168.0.1
```

The above example has a single node with three network interfaces defined. The top level node keys are:

- **name:** User-friendly name of the node stored in SMD.
- **nid:** *Node Identifier*. Unique number identifying node, used in the DHCP-given hostname. Mainly used as a default hostname (since it can be overridden in cloud-init) that can be easily ranged over (e.g. `nid[001-004,006]`).
- **xname:** The unique node identifier which follows HPE's [xname format](https://cray-hpe.github.io/docs-csm/en-10/operations/component_names_xnames/) (see the "Node" entry in the table) and is supposed to encode location data. The format is `x<cabinet>c<chassis>s<slot>b<bmc>n<node>`. OpenCHAMI doesn't care about location data, so these can be arbitrary if you don't care about it. They just need to be unique per-node.
- **bmc_mac:** MAC address of node's BMC. This is required even if the node does not have a BMC because SMD uses BMC MAC addresses in its discovery process as the basis for node information. Thus, we need to emulate that here.
- **bmc_ip:** Desired IP address for node's BMC.
- **group:** An optional SMD group to add this node to. cloud-init reads SMD groups when determining which meta-data and cloud-init config to give a node.

Then, the **interfaces** is a list of network interfaces attached to the node. Each of these interfaces has the following keys:

- **mac_addr:** Network interface's MAC address. Used by CoreDHCP/CoreSMD to give the proper IP address for interface listed in SMD.
- **ip_addrs:** The list of IP addresses for the node.
  - **name:** A human-readable name for this IP address for this interface.
  - **ip_addr:** An IP address for this interface.

# Using Static Discovery to Populate SMD

We need a file containing the node information that we can pass to `ochami` to have it populate SMD. Take a look at `nodes.yaml`. Here's an excerpt:

```yaml
nodes:
- name: compute1
  nid: 1
  xname: x1000c0s0b0n0
  bmc_mac: de:ca:fc:0f:fe:e1
  bmc_ip: 172.16.0.101
  group: compute
  interfaces:
  - mac_addr: 52:54:00:be:ef:01
    ip_addrs:
    - name: management
      ip_addr: 172.16.0.1
```

Create a directory for putting our cluster configuration data into and copy the contents of [nodes.yaml](nodes.yaml) there:

```bash
mkdir -p /opt/workdir/nodes
vim /opt/workdir/nodes/nodes.yaml
```

Run the following to populate SMD with the node information (make sure `DEMO_ACCESS_TOKEN` is set):

```bash
ochami discover static -f yaml -d @/opt/workdir/nodes/nodes.yaml
```

We can check SMD that the components got added with:

```bash
ochami smd component get | jq '.Components[] | select(.Type == "Node")'
```

The output should be:

```json
{
  "Enabled": true,
  "ID": "x1000c0s0b0n0",
  "NID": 1,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b1n0",
  "NID": 2,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b2n0",
  "NID": 3,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b3n0",
  "NID": 4,
  "Role": "Compute",
  "Type": "Node"
}
{
  "Enabled": true,
  "ID": "x1000c0s0b4n0",
  "NID": 5,
  "Role": "Compute",
  "Type": "Node"
}
```
