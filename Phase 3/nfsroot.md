For NFS, we need to update the /etc/exports file and then reload the kernel nfs daemon

Create `/opt/nfsroot` to serve our images

```bash
sudo mkdir /srv/nfs
sudo chown rocky: /srv/nfs
```

  - Create the `/etc/exports` file with the following contents to export the `/srv/nfs` directory for use by our compute nodes
    ```bash
    /srv/nfs *(ro,no_root_squash,no_subtree_check,noatime,async,fsid=0)
    ```

  - Reload the nfs daemon
    ```bash
    sudo modprobe -r nfsd && sudo modprobe nfsd
    ```

### Webserver for Boot Artifacts

We expose our NFS directory over https as well to make it easy to serve boot artifacts.

```yaml
# nginx.container
[Unit]
Description=Serve /srv/nfs over HTTP
After=network-online.target
Wants=network-online.target

[Container]
ContainerName=nginx
Image=docker.io/library/nginx:1.28-alpine
Volume=/srv/nfs:/usr/share/nginx/html:Z
PublishPort=80:80

[Service]
TimeoutStartSec=0
Restart=always
```

### Import Images from OCI to Share with NFS

[Import-image Script](https://github.com/OpenCHAMI/image-builder/blob/main/scripts/image-import.sh)

