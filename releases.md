# Releases

## Unreleased

  - Add dedicated Cluster Discovery Service and Endpoint Discovery Service implementations, allowing resource-specific xDS streams without claiming ADS.
  - Allow generated clusters to use a dedicated EDS configuration source instead of ADS.
  - Add a guide covering control-plane setup, Envoy bootstrap configuration, resource updates, and Ruby client usage.

## v0.3.0

  - Add Envoy HTTP active health-check resources and attach health checks to generated clusters.

## v0.2.0

  - Add ORCA load reporting messages, service interface, and client-side weighted-round-robin resources.
  - Support endpoint hostnames in generated EDS resources.
  - Replace the general resource builder with focused cluster and endpoint builders.

## v0.1.0

  - Add complete documentation coverage for the public xDS API.
  - Support grouped IP and Unix-domain-socket addresses in EDS endpoints.
  - Support selecting HTTP/1 or HTTP/2 for generated clusters.

## v0.1.0

  - Initial extraction from `async-grpc`.
