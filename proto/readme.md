# Envoy Protobuf Definitions

This directory contains vendored Envoy protobuf definitions for xDS support.

## Source

These files come from [envoyproxy/data-plane-api](https://github.com/envoyproxy/data-plane-api).

## Contents

- `envoy/service/discovery/v3/` - Discovery service definitions (ADS, DiscoveryRequest/Response)
- `envoy/config/cluster/v3/` - Cluster definitions (CDS)
- `envoy/config/endpoint/v3/` - Endpoint definitions (EDS)
- `envoy/config/listener/v3/` - Listener definitions (LDS)
- `envoy/config/route/v3/` - Route definitions (RDS)
- `envoy/config/core/v3/` - Core types (Node, Address, etc.)
- `envoy/extensions/transport_sockets/tls/v3/` - TLS/Secret definitions (SDS)
- `envoy/extensions/load_balancing_policies/` - Typed load-balancing policy definitions
- `xds/data/orca/v3/` - ORCA load reports
- `xds/service/orca/v3/` - Out-of-band ORCA reporting service
- `google/protobuf/` - Google protobuf well-known types

## Updating

To update these files, run:

```bash
bundle exec bake update_protos
```

This fetches the pinned upstream revisions defined in `bake.rb`, updates the vendored definitions, and regenerates the checked-in Ruby classes.

## Generating Ruby Code

After updating proto files, generate Ruby classes:

```bash
bundle exec bake generate_protos
```

## Version

The source repositories and revisions are defined by `PROTOBUF_SOURCES` in `bake.rb`. They include:

- `envoyproxy/data-plane-api` - Envoy API definitions
- `protocolbuffers/protobuf` - Google protobuf well-known types
- `googleapis/api-common-protos` - Google RPC status
- `cncf/xds` - xDS API definitions
- `cncf/udpa` - UDPA annotations
- `envoyproxy/protoc-gen-validate` - Validation annotations

## Note on Dependencies

Some proto files import `udpa/annotations/*` and `validate/validate.proto`. These are optional annotations used for validation and versioning. They won't break compilation if missing, but you may want to include them for full compatibility:

- `udpa` annotations: https://github.com/cncf/udpa
- `validate` annotations: https://github.com/envoyproxy/protoc-gen-validate
