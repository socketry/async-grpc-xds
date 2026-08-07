# Async::GRPC::XDS

xDS support for `async-grpc` clients.

This gem contains the experimental xDS implementation extracted from `async-grpc`, including Envoy xDS protobuf definitions, aggregated and resource-specific discovery, CDS/EDS resource handling, and client-side load balancing.

[![Development Status](https://github.com/socketry/async-grpc-xds/workflows/Test/badge.svg)](https://github.com/socketry/async-grpc-xds/actions?workflow=Test)

## Usage

Please see the [project documentation](https://socketry.github.io/async-grpc-xds/) for more details.

  - [Getting Started](https://socketry.github.io/async-grpc-xds/guides/getting-started/index) - This guide explains how to use `async-grpc-xds` to publish CDS and EDS resources to Envoy, or to discover gRPC backends from Ruby using xDS.

## Testing

The `integration/` directory contains Docker Compose environments for testing the Ruby xDS client against a Go control plane and the Ruby control plane against Envoy.

``` bash
bundle exec bake test:integration
```

## Releases

Please see the [project releases](https://socketry.github.io/async-grpc-xds/releases/index) for all releases.

### v0.3.0

  - Add Envoy HTTP active health-check resources and attach health checks to generated clusters.

### v0.2.0

  - Add ORCA load reporting messages, service interface, and client-side weighted-round-robin resources.
  - Support endpoint hostnames in generated EDS resources.
  - Replace the general resource builder with focused cluster and endpoint builders.

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
