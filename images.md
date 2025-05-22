# Boot Images

## Contents

- [Boot Images](#boot-images)
  - [Contents](#contents)
- [Introduction](#introduction)
- [Concepts](#concepts)
  - [Layers](#layers)
- [Anatomy of an Image Configuration](#anatomy-of-an-image-configuration)
  - [Key Reference](#key-reference)
    - [Base Layers](#base-layers)
      - [`options` **(REQUIRED)**](#options-required)
      - [`repos`](#repos)
      - [`package_groups`](#package_groups)
      - [`packages`](#packages)
      - [`remove_packages`](#remove_packages)
      - [`copyfiles`](#copyfiles)
      - [`cmds`](#cmds)
    - [Ansible Layers](#ansible-layers)
      - [`options` **(REQUIRED)**](#options-required-1)
  - [Examples](#examples)
    - [`base.yaml`](#baseyaml)
  - [`compute.yaml`](#computeyaml)
- [Creating a Base Image Layer](#creating-a-base-image-layer)
- [Creating a Compute Image Layer](#creating-a-compute-image-layer)
- [Creating a Debug Image](#creating-a-debug-image)

# Introduction

In order for our nodes to be useful, they need to have an image to boot. Luckily, OpenCHAMI provides a layer-based boot image builder that can export into OCI and SquashFS images. It is creatively named [image-builder](https://github.com/OpenCHAMI/image-builder), and can be thought of as a fancy wrapper around [buildah](https://github.com/containers/buildah/blob/main/README.md).

The image builder works by reading a YAML-formatted image specification, which it uses to create an OCI container image (`buildah from ...`, `buildah mount ...`) and run commands in (`buildah run ...`) in order to build a filesystem within the image. It can then be configured to push the resulting image to a container registry or export it to a SquashFS image and push to S3.

## Install and configure regctl

```bash
curl -L https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64 > regctl && sudo mv regctl /usr/local/bin/regctl && sudo chmod 755 /usr/local/bin/regctl
/usr/local/bin/regctl registry set --tls disabled demo.openchami.cluster:5000
```

## Configure S3 Client

**`~/.s3cfg`**

```ini
# Setup endpoint
host_base = demo.openchami.cluster:9000
host_bucket = demo.openchami.cluster:9000
bucket_location = us-east-1
use_https = False

# Setup access keys
access_key = admin
secret_key = admin123

# Enable S3 v4 signature APIs
signature_v2 = False
```

To make sure it works, list the S3 buckets:

```bash
s3cmd ls
```

We should see the two that got created:

```
2025-04-22 15:24  s3://boot-images
2025-04-22 15:24  s3://efi
```

# Concepts

## Layers

The image builder deals with image _layers_, which are analogous to container image layers (underneath, this is the mechanism it leverages). Similar to a Dockerfile, an image configuration can start from scratch (blank filesystem) or use an image as its parent.

For example, it is idiomatic to have a "base" image that installs a basic filesystem that is generic then having more specific layers build off of that: For example, a "compute" image that has "base" as its parent and installs compute-related packages, places configurations in `/etc`, etc.

The benefit of layers is apparent when rebuilding an image: if something needs to change in the "compute" image, only that layer needs to be rebuilt instead of rebuilding a monolithic image.

# Anatomy of an Image Configuration

## Key Reference

### Base Layers

Base layers are considered "normal" in the sense that they are considered independent (as opposed to Ansible layers, which run Ansible on an existing image; this will probably be unified in the future).

#### `options` **(REQUIRED)**

These represent the global image builder options for this image.

- `layer_type`: the type of image layer this will be

  Supported values are:
  - `ansible` - build an image layer provisioned by Ansible
  - `base` - build an image layer that is a simple filesystem
- `log_level`: log level of the image builder, especially when running `cmds`

  Currently supported values:
  - `DEBUG` (default)
  - `INFO`
  - `WARNING`
  - `ERROR`
  - `CRITICAL`
- `name`: the name of this image layer (will be used as OCI/SquashFS image name)
- `publish_tags`: the tag(s) to use to identify the version of this image

  This can either be a string (for one tag) or a YAML list of tags.

  If the image is exported as an OCI image, these will be used as the container image tag(s).

  If the image is exported as a SquashFS image, a version of the image will be pushed with the tag appended to the `name`, one for each tag.
- `pkg_manager`: the package manager used in this image

  This can be thought of as the way to determine the "distro" of the image.

  Currently supported values are:
  - `dnf`
  - `zypper`
- `parent`: the image to use as the parent of this one, or `scratch` if none
  - See `registry_opts_pull`.
- `publish_registry`: (_OPTIONAL_) a URI to push the image in OCI format to

  - See `registry_opts_push`.
- `publish_s3`: (_OPTIONAL_) base URI of S3 to push image in SquashFS format to
  - See `s3_*`.
  - S3 images are published at `<s3_publish>/<s3_prefix>/<ID><ID_VERSION>-<name>-<publish_tag>`
    - `<ID>` is `ID` field from `/etc/os-release` (e.g. "rocky")
    - `<ID_VERSION>` is `ID_VERSION` field from `/etc/os-release` (e.g. "9.5")
- `registry_opts_pull`: (_OPTIONAL_) CLI options to pass to `buildah` when pulling `parent`
- `registry_opts_push`: (_OPTIONAL_) CLI options to pass to `buildah` when pushing to `publish_registry`
- `s3_prefix`: (_OPTIONAL_) URI path prefix of image, appended to `s3_bucket`
- `s3_bucket`: (_OPTIONAL_) S3 bucket image will reside in, appended to `publish_s3`

#### `repos`

Configure package manager repositories before installing packages and running commands.

- `alias`: unique, human-readable repository name for logging
- `url`: repository URI
- `gpg`: (_OPTIONAL_) URL of GPG key for verifying packages in repo

#### `package_groups`

A YAML list of names of package groups to install (passed to package manager group install command).

#### `packages`

A YAML list of packages to install in the image (passed to package manager install command).

#### `remove_packages`

A YAML list of packages to remove from the image (passed to package manager uninstall command).

#### `copyfiles`

A YAML list of files to copy to the image from the host.

Each item in the list has the following keys:

- `src`: source file to copy
- `dst`: destination path in image to copy file to

#### `cmds`

A YAML list of commands to run after package manager items are installed. Each command in the list is run with `buildah run <image> -- bash -c '<cmd>'` where `<image>` is where the image is mounted and `<cmd>` is the command line to run.

Each item in the list has the following keys:

- `cmd`: the command line to run
  - Run in a shell so shell structures are allowed
- `loglevel`: (_OPTIONAL_) level to log command standard error with

  Possible values are:
  - `ERROR` (default)
  - `WARN`
  - `INFO`

### Ansible Layers

Ansible layers require that a parent base layer exists with Ansible installed, and runs an Ansible playbook on the layer.

#### `options` **(REQUIRED)**

The same as the base layer `options` key with the following keys added. Only the `parent` and `name` fields are read that are common with the base layer type.

- `groups`: a string or YAML list of the Ansible groups to run the playbook for
- `playbooks`: a string or YAML list of the Ansible playbook file(s) to run
- `inventory`: the Ansible inventory file/directory
- `vars`: YAML keys/values to set as additional Ansible variables

## Examples

Let's examine two image configuration files.


### `base.yaml`

```yaml
options:
  layer_type: 'base'
  name: 'rocky-base'
  publish_tags: '9.5'
  pkg_manager: 'dnf'
  parent: 'scratch'
  publish_registry: 'demo.openchami.cluster:5000/demo'
  registry_opts_push:
    - '--tls-verify=false'

repos:
  - alias: 'Rocky_9_BaseOS'
    url: 'https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/'
    gpg: 'https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9'
  - alias: 'Rocky_9_AppStream'
    url: 'https://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/'
    gpg: 'https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9'

package_groups:
  - 'Minimal Install'
  - 'Development Tools'

packages:
  - kernel
  - wget
  - dracut-live

cmds:
  - cmd: 'dracut --add "dmsquash-live livenet network-manager" --kver $(basename /lib/modules/*) -N -f --logfile /tmp/dracut.log 2>/dev/null'
    loglevel: INFO
  - cmd: 'echo DRACUT LOG:; cat /tmp/dracut.log'
    loglevel: INFO
```

This file will build our basic Rocky Linux image.

It has no parent and publishes only the OCI image (no SquashFS) at `registry.demo.openchami.cluster:5000/openchami/rocky-base:9.5`. TLS verification is turned off when pushing to the registry.

Two of the Rocky package repositories, BaseOS and Appstream, are added. Then, the `Minimal Install` and `Development Tools` are installed. Following that, three packages are installed. We install `kernel` to get the kernel image (since, being a container, it is not included by default) so that it, along with the initramfs image, can be pulled out and used for booting.

Finally, some commands are run. We run `dracut` to include kernel modules that enable the kernel to be able to mount a SquashFS image as its rootfs in memory.

### `compute.yaml`

```yaml
options:
  layer_type: 'base'
  name: 'compute-base'
  publish_tags:
    - '9.5'
  pkg_manager: 'dnf'
  parent: 'demo.openchami.cluster:5000/demo/rocky-base:9.5'
  registry_opts_pull:
    - '--tls-verify=false'

  # Publish SquashFS image to local S3
  publish_s3: 'http://demo.openchami.cluster:9090'
  s3_prefix: 'compute/base/'
  s3_bucket: 'boot-images'

  # Publish OCI image to container registry
  #
  # This is the only way to be able to re-use this image as
  # a parent for another image layer.
  publish_registry: 'demo.openchami.cluster:5000/demo'
  registry_opts_push:
    - '--tls-verify=false'

repos:
  - alias: 'Epel9'
    url: 'https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/'
    gpg: 'https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9'

packages:
  - cloud-init
  - python3
  - vim
  - nfs-utils
  - chrony
  - cmake3
  - dmidecode
  - dnf
  - efibootmgr
  - golang
  - ipmitool
  - jq
  - make
  - perf
  - rsyslog
  - sqlite
  - sudo
  - tcpdump
  - traceroute
  - lua-posix
  - tcl
  - git
  - fortune-mod
```

This config builds our compute image layer.

Notice how it uses the `rocky-base:9.5` image as its parent. Therefore, it doesn't need to re-add the Rocky repositories or install base packages. The only thing this image does is install additional packages.

Also notice that this image gets pushed to S3 (in SquashFS format). In this tutorial, we will not be using S3 and so will squash and push manually.

The image also gets pushed as an OCI image to the registry so it, too, can be used as a parent for further image layers.

# Creating a Base Image Layer

Let's create a directory for our image configs.

```bash
mkdir -p /opt/workdir/images
cd /opt/workdir/images
```


Build the image using the `image-build` container:

```bash
podman run --rm --device /dev/fuse --network host -v /opt/workdir/images/base.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

Example output:

```
INFO - --------------------ARGUEMENTS--------------------
INFO - log_level : DEBUG
INFO - config : config.yaml
INFO - layer_type : base
INFO - pkg_man : dnf
INFO - parent : scratch
INFO - proxy :
INFO - name : rocky-base
INFO - publish_local : False
INFO - publish_s3 : None
INFO - publish_registry : demo.openchami.cluster:5000/openchami
INFO - registry_opts_push : ['--tls-verify=false']
INFO - registry_opts_pull : []
INFO - publish_tags : 9.5
[...snip...]
WARNING - Getting image source signatures
WARNING - Copying blob sha256:b2e25adb6eafb8903862049ddb8b755e4665ab9f6928774a245259f94edeb1c1
WARNING - Copying config sha256:327ed14011200c2c9a381f244ff0ca2ddf95fd83f747d2891e0456c079c4c23c
WARNING - Writing manifest to image destination
INFO - 327ed14011200c2c9a381f244ff0ca2ddf95fd83f747d2891e0456c079c4c23c
WARNING - Getting image source signatures
WARNING - Copying blob sha256:b2e25adb6eafb8903862049ddb8b755e4665ab9f6928774a245259f94edeb1c1
WARNING - Copying config sha256:327ed14011200c2c9a381f244ff0ca2ddf95fd83f747d2891e0456c079c4c23c
WARNING - Writing manifest to image destination
INFO - 4a46e58a1187b17721afb89d18ca852de1955a0748b5f29213e3bea60f962be8
INFO - untagged: localhost/rocky-base:9.5
INFO - 327ed14011200c2c9a381f244ff0ca2ddf95fd83f747d2891e0456c079c4c23c

-------------------BUILD LAYER--------------------
pushing layer rocky-base to demo.openchami.cluster:5000/demo/rocky-base:9.5
```

Now, if we list the images in our registry:

```bash
regctl repo ls demo.openchami.cluster:5000
```

We will see the base image:

```
demo/rocky-base
```

> [!TIP]
> If you get an error that states "http: server gave HTTP response to HTTPS client", try running `regctl registry set --tls disabled demo.openchami.cluster:5000` to disable TLS and thne try listing the images again.

We should also be able to see the tag we set:

```bash
regctl tag ls demo.openchami.cluster:5000/demo/rocky-base
```

Output:

```
9.5
```

# Creating a Compute Image Layer

- The compute image uses the base image as its parent:

  ```yaml
  parent: 'demo.openchami.cluster:5000/demo/rocky-base:9.5'
  registry_opts_pull:
    - '--tls-verify=false'
  ```

- Besides pushing the OCI image to the registry, this image will also get pushed to S3 as a SquashFS image at `http://172.16.0.254:9090/boot-images/compute/base/:

  ```yaml
  name: 'compute-base'
  publish_tags:
    - '9.5'
  ```
  ```yaml
  publish_s3: 'http://172.16.0.254:9090'
  s3_prefix: 'compute/base/'
  s3_bucket: 'boot-images'
  ```

- We only perform the actions required by this layer and not the parent. For this image, that only entails adding an additional repository and installing additional packages.

Let's build the image:

```bash
podman run --rm --device /dev/fuse -e "S3_ACCESS=admin" -e "S3_SECRET=admin123" -v /opt/workdir/images/compute.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

Notice that this time we pass S3 credentials into the image builder so it can push the image to S3.

We should see a header in the output similar to the base image:

```
INFO - --------------------ARGUEMENTS--------------------
INFO - log_level : DEBUG
INFO - config : config.yaml
INFO - layer_type : base
INFO - pkg_man : dnf
INFO - parent : demo.openchami.cluster:5000/openchami/rocky-base:9.5
INFO - proxy :
INFO - name : compute-base
INFO - publish_local : False
INFO - publish_s3 : http://172.16.0.254:9090
INFO - s3 endpoint : http://172.16.0.254:9090
INFO - s3_prefix : compute/base/
INFO - s3_bucket : boot-images
INFO - publish_registry : demo.openchami.cluster:5000/openchami
INFO - registry_opts_push : ['--tls-verify=false']
INFO - registry_opts_pull : ['--tls-verify=false']
INFO - publish_tags : ['9.5']
ERROR - Trying to pull demo.openchami.cluster:5000/openchami/rocky-base:9.5...
ERROR - Getting image source signatures
ERROR - Copying blob sha256:23589bb5b153826e2661212609e3094d720038db1e8fa3b7872c10fb01059835
```

The parent image should get pulled from the container registry:

```
ERROR - Trying to pull demo.openchami.cluster:5000/openchami/rocky-base:9.5...
ERROR - Getting image source signatures
ERROR - Copying blob sha256:23589bb5b153826e2661212609e3094d720038db1e8fa3b7872c10fb01059835
ERROR - Copying config sha256:e1958ddb8034ff874636f9428dae9e1d614acca309e09ecadf87e6fc61d5e003
ERROR - Writing manifest to image destination
```

Then, we should see that the packages we specified get installed:

```
INFO - chrony
cloud-init
cmake3
dmidecode
dnf
efibootmgr
git
ipmitool
jq
lua-posix
make
nfs-utils
python3
rsyslog
sudo
tcl
tcpdump
traceroute
vim
```

At the end, we should see it squash the image and push it to S3:

```
-------------------BUILD LAYER--------------------
pushing to s3
/home/builder/.local/share/containers/storage/overlay/81a28a4b02a1d2a13eb927fb718d1fc593f0bb4c35b4acd85ba2a3581e0c0dcf/merged
squashing container image
Image Name: compute/base/rocky9.5-compute-base-9.5
initramfs: initramfs-5.14.0-503.35.1.el9_5.x86_64.img
vmlinuz: vmlinuz-5.14.0-503.35.1.el9_5.x86_64
Pushing /home/builder/.local/share/containers/storage/overlay/81a28a4b02a1d2a13eb927fb718d1fc593f0bb4c35b4acd85ba2a3581e0c0dcf/merged/boot/initramfs-5.14.0-503.35.1.el9_5.x86_64.img as efi-images/compute/base/initramfs-5.14.0-503.35.1.el9_5.x86_64.img to boot-images
Pushing /home/builder/.local/share/containers/storage/overlay/81a28a4b02a1d2a13eb927fb718d1fc593f0bb4c35b4acd85ba2a3581e0c0dcf/merged/boot/vmlinuz-5.14.0-503.35.1.el9_5.x86_64 as efi-images/compute/base/vmlinuz-5.14.0-503.35.1.el9_5.x86_64 to boot-images
Pushing /var/tmp/tmpzzz7d3nz/rootfs as compute/base/rocky9.5-compute-base-9.5 to boot-images
pushing layer compute-base to demo.openchami.cluster:5000/openchami/compute-base:9.5
```

We can see what got added to S3 with:

```bash
s3cmd ls -Hr s3://boot-images/
```

We should see:

- the rootfs in SquashFS format
- the boot kernel
- the boot initramfs

```
2025-04-22 15:48  1284M  s3://boot-images/compute/base/rocky9.5-compute-base-9.5
2025-04-22 15:48    75M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-503.38.1.el9_5.x86_64.img
2025-04-22 15:48    13M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-503.38.1.el9_5.x86_64
```

We will be using these in the next section on setting boot parameters.

# Creating a Debug Image

Our base compute image does not have any users, since those will be created by cloud-init (which we haven't configured or enabled yet). Therefore, it will be difficult to test if things work.

In order to provide a sanity check, let's create a "debug" image that has a single "testuser" so we can poke around at the image we booted to make sure things work. Copy `image-configs/compute-debug-9.5.yaml` to `/opt/workdir/images/` and take a look at it.

Notice:

- We use the base compute image as the parent:

  ```yaml
  parent: 'demo.openchami.cluster:5000/openchami/compute-base:9.5'
  registry_opts_pull:
    - '--tls-verify=false'
  ```

- We push the image to the `compute/debug` prefix:

  ```yaml
  s3_prefix: 'compute/debug/'
  ```

- We create a `testuser` user (password is `testuser`):

  ```yaml
  packages:
    - shadow-utils

  cmds:
    - cmd: "useradd -mG wheel -p '$6$VHdSKZNm$O3iFYmRiaFQCemQJjhfrpqqV7DdHBi5YpY6Aq06JSQpABPw.3d8PQ8bNY9NuZSmDv7IL/TsrhRJ6btkgKaonT.' testuser"
      loglevel: INFO
  ```

  This will be the user we will login to the console as.

Let's build this image:

```bash
podman run --rm --device /dev/fuse -e S3_ACCESS=admin -e S3_SECRET=admin123 -v /opt/workdir/images/compute-debug-9.5.yaml:/home/builder/config.yaml ghcr.io/openchami/image-build:latest image-build --config config.yaml --log-level DEBUG
```

Once finished, we should see the debug image artifacts show up in S3:

```bash
s3cmd ls -Hr s3://boot-images/
```

```
2025-04-22 15:48  1284M  s3://boot-images/compute/base/rocky9.5-compute-base-9.5
2025-04-22 17:28  1284M  s3://boot-images/compute/debug/rocky9.5-compute-debug-9.5
2025-04-22 15:48    75M  s3://boot-images/efi-images/compute/base/initramfs-5.14.0-503.38.1.el9_5.x86_64.img
2025-04-22 15:48    13M  s3://boot-images/efi-images/compute/base/vmlinuz-5.14.0-503.38.1.el9_5.x86_64
2025-04-22 17:28    75M  s3://boot-images/efi-images/compute/debug/initramfs-5.14.0-503.38.1.el9_5.x86_64.img
2025-04-22 17:28    13M  s3://boot-images/efi-images/compute/debug/vmlinuz-5.14.0-503.38.1.el9_5.x86_64
```

We will be using the following pieces of the debug URLs for the boot setup in the next section:

- `boot-images/compute/debug/rocky9.5-compute-debug-9.5`
- `boot-images/efi-images/compute/debug/initramfs-5.14.0-503.38.1.el9_5.x86_64.img`
- `boot-images/efi-images/compute/debug/vmlinuz-5.14.0-503.38.1.el9_5.x86_64`
