# HTTP Server

## Description

This module aims to provide a HTTP/S server to expose handy endpoints to talk to Gorgone.

It relies on a core API module to server Gorgone events and can dispatch any other piece of code.

## Configuration

| Directive | Description | Default value |
| :- | :- | :- |
| address | IP address for the server to bind to | `0.0.0.0` |
| port | Port on which the server will listen to requests | `8080` |
| ssl | Boolean to enable SSL terminaison | `false` |
| ssl_cert_file | Path to the SSL certificate (if SSL enabled) |  |
| ssl_key_file | Path to the SSL key (if SSL enabled) |  |
| auth | Basic credentials to access the server |  |

#### Example

```yaml
name: httpserver
package: "gorgone::modules::core::httpserver::hooks"
enable: true
address: 0.0.0.0
port: 8443
ssl: true
ssl_cert_file: /etc/pki/tls/certs/server-cert.pem
ssl_key_file: /etc/pki/tls/server-key.pem
auth:
  user: admin
  password: password
```

Below the configuration to add other endpoints:

```yaml
dispatch:
  - endpoint: "/mycode"
    method: GET
    class: "path::to::my::code"
```

## Events

| Event | Description |
| :- | :- |
| HTTPSERVERREADY | Internal event to notify the core |

## API

### Get HTTP server status

| Endpoint | Method |
| :- | :- |
| /status | `GET` |

#### Headers

| Header | Value |
| :- | :- |
| Accept | application/json |

#### Example

```bash
curl --request GET "https://hostname:8443/status" \
  --header "Accept: application/json"
```
