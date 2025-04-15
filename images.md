# Boot Images

## Contents

- [Boot Images](#boot-images)
  - [Contents](#contents)
- [Introduction](#introduction)
- [Concepts](#concepts)
  - [Layers](#layers)
- [Anatomy of an Image Configuration](#anatomy-of-an-image-configuration)
  - [Key Reference](#key-reference)
  - [Examples](#examples)

# Introduction

In order for our nodes to be useful, they need to have an image to boot. Luckily, OpenCHAMI provides a layer-based boot image builder that can export into OCI and SquashFS images. It is creatively named [image-builder](https://github.com/OpenCHAMI/image-builder), and can be thought of as a fancy wrapper around [buildah](https://github.com/containers/buildah/blob/main/README.md).

The image builder works by reading a YAML-formatted image specification, which it uses to create an OCI container image (`buildah from ...`, `buildah mount ...`) and run commands in (`buildah run ...`) in order to build a filesystem within the image. It can then be configured to push the resulting image to a container registry or export it to a SquashFS image and push to S3.

# Concepts

## Layers

The image builder deals with image _layers_, which are analogous to container image layers (underneath, this is the mechanism it leverages). Similar to a Dockerfile, an image configuration can start from scratch (blank filesystem) or use an image as its parent.

For example, it is idiomatic to have a "base" image that installs a basic filesystem that is generic then having more specific layers build off of that: For example, a "compute" image that has "base" as its parent and installs compute-related packages, places configurations in `/etc`, etc.

The benefit of layers is apparent when rebuilding an image: if something needs to change in the "compute" image, only that layer needs to be rebuilt instead of rebuilding a monolithic image.

# Anatomy of an Image Configuration

## Key Reference

## Examples

Let's examine two image configuration files:

**base.yaml**

```yaml
options:
  layer_type: 'base'
  name: 'rocky-base'
  publish_tags: '9.5'
  pkg_manager: 'dnf'
  parent: 'scratch'
  publish_registry: 'registry.dist.si.usrc:5000/redondo'
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
  - kitty-terminfo

cmds:
  - cmd: 'dracut --add "dmsquash-live livenet network-manager" --kver $(basename /lib/modules/*) -N -f --logfile /tmp/dracut.log 2>/dev/null'
    loglevel: INFO
  - cmd: 'echo DRACUT LOG:; cat /tmp/dracut.log'
    loglevel: INFO
```

**compute.yaml**

```yaml
options:
  layer_type: 'base'
  name: 'compute-base'
  publish_tags:
    - '9.5'
  pkg_manager: 'dnf'
  parent: 'registry.my.cluster/my-cluster/rocky-base:9.5'
  registry_opts_pull:
    - '--tls-verify=false'

  # Publish SquashFS image to local S3
  publish_s3: 'http://s3.my.cluster'
  s3_prefix: 'compute/base/'
  s3_bucket: 'boot-images'

  # Publish OCI image to container registry
  #
  # This is the only way to be able to re-use this image as
  # a parent for another image layer.
  publish_registry: 'registry.my.cluster/my-cluster'
  registry_opts_push:
    - '--tls-verify=false'

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
  - nss_db
  - lua-posix
  - tcl
  - git
  - fortune-mod
```