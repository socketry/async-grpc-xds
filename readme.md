# Async::GRPC::XDS

xDS support for `async-grpc` clients.

This gem contains the experimental xDS implementation extracted from `async-grpc`, including Envoy xDS protobuf definitions, ADS discovery, CDS/EDS resource handling, and client-side load balancing.

[![Development Status](https://github.com/socketry/async-grpc-xds/workflows/Test/badge.svg)](https://github.com/socketry/async-grpc-xds/actions?workflow=Test)

## Usage

Please see the [project documentation](https://socketry.github.io/async-grpc-xds/) for more details.

## Status

This is an early implementation focused on ADS with CDS and EDS. LDS/RDS, full routing semantics, NACK handling, locality weighting, and delta xDS are not complete yet.

## Testing

The `xds/` directory contains a Docker Compose integration environment with a Go xDS control plane and Ruby gRPC backends.

``` bash
docker compose -f xds/docker-compose.yaml up --build --exit-code-from tests
```

## Releases

Please see the [project releases](https://socketry.github.io/async-grpc-xds/releases/index) for all releases.

### v0.1.0

  - Add complete documentation coverage for the public xDS API.
  - Support grouped IP and Unix-domain-socket addresses in EDS endpoints.
  - Support selecting HTTP/1 or HTTP/2 for generated clusters.

### v0.1.0

  - Add complete documentation coverage for the public xDS API.
  - Support grouped IP and Unix-domain-socket addresses in EDS endpoints.
  - Support selecting HTTP/1 or HTTP/2 for generated clusters.

## See Also

  - [async-grpc](https://github.com/socketry/async-grpc)
  - [protocol-grpc](https://github.com/socketry/protocol-grpc)
  - [async-http](https://github.com/socketry/async-http)
