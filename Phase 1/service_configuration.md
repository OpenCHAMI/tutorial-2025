# Service Configuration

The release RPM includes a set of configurations that make a few assumptions about your setup.  All of these can be changed before starting the system to work with your environment.  The release RPM puts all configuration files in `/etc/openchami/`.

> [!NOTE]
> Default usernames, passwords, and initialization secrets are included.  Don't use these for production.  They are very insecure.
>

## Environment variables

All containers share the same environment variables file for the demo.  We recommend splitting them up per service where keys/secrets are concerned by following the comments in the openchami.env file

## coredhcp configuration

The OpenCHAMI dhcp server is a coredhcp container with a custom plugin that interfaces with smd to ensure that changes in node ip are quickly and accurately reflected.  It uses a plugin configuration at /etc/openchami/coredhcp.yaml

### listen
The yaml below instructs the container to listen on an interface called `virbr-openchami`.  If you are running this configuration for local development/testing, you will need to have this interface configured as a virtual bridge interface.  On a real system, you will need to change the listen interface.  CoreDHCP will use this interface to listen for DHCP requests.

### plugins

The plugins section of the `coredhcp` configuration is read by our coresmd plugin (and others) to control the way that addresses and netboot parameters are handled for each DHCP request.  They describe the ip address of the server, the router and netmask, and how to connect to the rest of the OpenCHAMI system.  The `bootloop` directive instructs the plugin to provide a reboot ipxe script to unknown nodes.

```yaml
server4:
  listen:
    - "%virbr-openchami"
  plugins:
    - server_id: 172.16.0.2
    - dns: 172.16.0.2
    - router: 172.16.0.1
    - netmask: 255.255.255.0
    - coresmd: https://demo.openchami.cluster:8443 http://172.16.0.2:8081 /root_ca/root_ca.crt 30s 1h
    - bootloop: /tmp/coredhcp.db default 5m 172.16.0.200 172.16.0.250
```

## haproxy configuration

Haproxy is a reverse proxy that allows all of our microservices to run in separate containers, but only one hostname/url is needed to access them all.  You are not likely to need to change it at all from system to system.  As configured, each microservice is a unique backend that handles a subset of URLs within the microservice.  Since each container has a predictable name within the podman (or docker) network, the microservices only need to be referenced by name.

## Hydra Configuration

Hydra is our JWT provider.  It's configuration file is as narrow as possible in this example and shouldn't need to be changed.  Depending on your own needs, you may want to consult the full list at [Hydra's Documentation](https://www.ory.sh/docs/hydra/reference/configuration).

```yaml
serve:
  cookies:
    same_site_mode: Lax

oidc:
  dynamic_client_registration:
    enabled: true
  subject_identifiers:
    supported_types:
      - public

oauth2:
  grant:
    jwt:
      jti_optional: true
      iat_optional: true
      max_ttl: 24h

strategies:
  access_token: jwt
```

## OPAAL Configuration

The OPAAL service is a shim that we use to connect our external authentication service (gitlab) with our internal authorization service (hydra).  We intend to deprecate it in favor of a third-party system in the future, but it is necessary at this stage in OpenCHAMI development.  The yaml configuration file lists many of the urls that are necessary to convert from an OIDC login flow to our token-granting service.  If you change things like the cluster and domain names, you will need to update this file.

**NB** OPAAL is not used in this tutorial.  We create our own access tokens directly without an OIDC login.