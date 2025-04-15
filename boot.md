# Boot Parameters

## Contents

- [Adding Boot Parameters](#adding-boot-parameters)

# Introduction

SMD may know about the nodes so that DHCP can give them their IP address and point them to their boot script, but that boot script won't do anything useful if no boot parameters exist.

Let's add some. We will be using the `ochami` CLI tool for this.

# Retrieving Boot Parameters

```bash
ochami boot params get | jq
```

We can filter by node as well:

```bash
ochami boot params get --mac 52:54:00:be:ef:01,52:54:00:be:ef:02 | jq
```

# Adding Boot Parameters

The `ochami bss boot params add` command will work for this task, but it will fail if we want to overwrite existing parameters. For more idempotency, we can use `ochami boot params set`. We will use this from here on out. See **ochami-bss**(1) for more information.

To set boot parameters, we need to pass:

1. The identity of the node that they will be for (MAC address, name, or node ID number)
1. At least one of:
   1. URI to kernel file
   2. URI to initrd file
   3. Kernel command line arguments