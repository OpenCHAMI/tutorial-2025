# Install OpenCHAMI Services

## Contents

- [Install OpenCHAMI Services](#install-openchami-services)
  - [Contents](#contents)
  - [Install Command](#install-command)
  - [Review Installed Containers](#review-installed-containers)
  - [Configure CoreDHCP](#configure-coredhcp)
  - [Configure Cloud-Init](#configure-cloud-init)
  - [Start OpenCHAMI](#start-openchami)
  - [Trust Root CA Certificate](#trust-root-ca-certificate)
  - [Autorenewal of Certificates](#autorenewal-of-certificates)
  - [Install and Configure OpenCHAMI Client](#install-and-configure-openchami-client)
    - [Installation](#installation)
    - [Configuration](#configuration)
  - [Generating Authentication Token](#generating-authentication-token)

Install the signed RPM from the [openchami/release](https://github.com/openchami/release) repository with verification using a [Public Gist](https://gist.github.com/alexlovelltroy/96bfc8bb6f59c0845617a0dc659871de).

1. identifies the latest release rpm
1. downloads the public signing key for OpenCHAMI
1. downloads the rpm
1. verifies the signature
1. installs the RPM

## Install Command

```bash
curl -fsSL https://gist.githubusercontent.com/alexlovelltroy/96bfc8bb6f59c0845617a0dc659871de/raw | bash
```

## Initialize and Trust the OpenCHAMI Certificate Auhority

OpenCHAMI includes a minimal open source certificate authority from smallstep.  The included automation initialized the CA on first startup.  We can immediately download a certificate into the system trust bundle on the host for trusting all subsequent OpenCHAMI certificates.  Notably, the certificate authority features ACME for automatic certificate rotation.

Start the certificate authority:

```bash
sudo systemctl start step-ca
sudo systemctl status step-ca
```

Import the root certificate into the system trust bundle:

```bash
sudo podman run --rm --network openchami-cert-internal docker.io/curlimages/curl -sk https://step-ca:9000/roots.pem | sudo tee /etc/pki/ca-trust/source/anchors/ochami.pem
sudo update-ca-trust
```

## Start OpenCHAMI

Even OpenCHAMI runs as a collection of containers. Podman's integration with systemd allows us to start, stop, and trace OpenCHAMI as a set of dependent services through the `openchami.target` unit.

```bash
sudo systemctl start openchami.target
systemctl list-dependencies openchami.target
```

> [!TIP]
> If the `openchami.target` fails because of a dependency issue, try looking at the logs with `journalctl -xe` or `journalctl -eu $container_name` for more information.

### Service Configuration

The OpenCHAMI release rpm is created with sensible default configurations for this tutorial and all configuration files are included in the `/etc/openchami` directory.  To understand each one in detail, review the [service_configuration](service_configuration.md) instructions

## Install and Configure OpenCHAMI Client

The [`ochami` CLI](https://github.com/OpenCHAMI/ochami) provides us an easy way to interact with the OpenCHAMI services.

### Installation

We can install the latest RPM with the following:

```bash
latest_release_url=$(curl -s https://api.github.com/repos/OpenCHAMI/ochami/releases/latest | jq -r '.assets[] | select(.name | endswith("amd64.rpm")) | .browser_download_url')
curl -L "${latest_release_url}" -o ochami.rpm
sudo dnf install -y ./ochami.rpm
```

As a sanity check, check the version to make sure it is installed properly:

```bash
ochami version
```

The output should look something like:

```
Version:    0.2.1
Tag:        v0.2.1
Branch:     HEAD
Commit:     3b28490f9a9a84070533d6794a1e5442a0c43dff
Git State:  clean
Date:       2025-04-08T18:18:34Z
Go:         go1.24.2
Compiler:   gc
Build Host: fv-az1333-80
Build User: runner
```

### Configuration

To configure `ochami` to be able to communicate with our cluster, we need to create a config file. We can create one in one fell swoop with:

```bash
ochami config cluster set --user --default demo cluster.uri https://demo.openchami.cluster:8443
```

This will create a config file at `~/.config/ochami/config.yaml`. We can check that `ochami` is reading it properly with:

```bash
ochami config show
```

We should see:

```yaml
clusters:
    - cluster:
        uri: https://demo.openchami.cluster:8443
      name: demo
default-cluster: demo
log:
    format: rfc3339
    level: warning
```

Now we should be able to communicate with our cluster. Let's make sure by checking the status of one of the services:

```bash
ochami bss status
```

We should get:

```json
{"bss-status":"running"}
```

Voilà!

> [!TIP]
> If you receive an error related to TLS when runing `ochami bss status`, then try re-running `acme-deploy` and restarting the `haproxy` service.
>
> ```bash
> systemctl restart acme-deploy
> systemctl restart haproxy
> ```


## Generating Authentication Token

In order to interact with protected endpoints, we will need to generate a JSON Web Token (JWT, pronounced _jot_). `ochami` reads an environment variable named `<CLUSTER_NAME>_ACCESS_TOKEN` where `<CLUSTER_NAME>` is the configured name of the cluster in all capitals, `DEMO` in our case.

Since we aren't using an external identity provider, we will use OpenCHAMI's internal one to generate a token. The RPM we installed comes with some shell functions that allow us to do this.

```bash
export DEMO_ACCESS_TOKEN=$(sudo bash -lc 'gen_access_token')
```

Note that `sudo` is needed because the containers are running as root and so if `sudo` is omitted, the containers will not be found.

OpenCHAMI tokens last for an hour by default. Whenever one needs to be regenerated, run the above command.
