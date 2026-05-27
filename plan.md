# Envoy Monitor Plan

## Goal

Add support for `async-service-supervisor` to publish worker health and endpoint information to Envoy using xDS.

The implementation should keep generic xDS protocol machinery in `async-grpc-xds`, and put supervisor-specific behavior in a separate monitor gem.

## Proposed Gems

### `async-grpc-xds`

Owns generic Ruby xDS client and control-plane support.

Existing client-side xDS support remains here. New server-side support should also live here so it can be reused by integrations beyond `async-service-supervisor`.

Responsibilities:

- ADS gRPC service implementation for Envoy.
- Snapshot/resource state management.
- Resource versioning.
- ACK/NACK handling.
- Stream reconnect support.
- Resource builders for common Envoy xDS resources.
- Tests and Docker compose fixtures for xDS behavior.

Initial server-side resource coverage:

- CDS: `envoy.config.cluster.v3.Cluster`.
- EDS: `envoy.config.endpoint.v3.ClusterLoadAssignment`.
- Endpoint health via `LbEndpoint#health_status`.

Possible API shape:

```ruby
control_plane = Async::GRPC::XDS::ControlPlane.new

control_plane.update_cluster("myservice")
control_plane.update_endpoints("myservice", endpoints)

server = Async::GRPC::XDS::Server.new(control_plane)
server.run(endpoint)
```

### `async-service-supervisor-envoy`

Owns the integration between `async-service-supervisor` and Envoy.

Proposed public monitor:

```ruby
Async::Service::Supervisor::Envoy::Monitor
```

Require path:

```ruby
require "async/service/supervisor/envoy/monitor"
```

Responsibilities:

- Run an embedded xDS control plane for Envoy.
- Translate supervisor worker registration/removal into xDS endpoint updates.
- Publish endpoint health to Envoy.
- Expose monitor status through the normal supervisor monitor status API.
- Keep Envoy-specific dependencies out of `async-service-supervisor` core.

Example usage:

```ruby
Async::Service::Supervisor::Envoy::Monitor.new(
	bind: "http://0.0.0.0:18000",
	clusters: true
)
```

Worker state should provide the endpoint metadata:

```ruby
state = {
	name: "myservice",
	endpoint: {
		address: "127.0.0.1",
		port: 50051
	}
}
```

The monitor should map that state to Envoy EDS endpoints.

Workers without `state[:endpoint]` should be ignored by the Envoy monitor. This allows non-network workers, control processes, or workers managed by other routing systems to still participate in supervisor monitoring without being published to Envoy.

The first version should support multiple clusters. By default, workers are grouped by `state[:name]`. The grouping should be configurable so applications can select, rename, or filter clusters:

```ruby
Async::Service::Supervisor::Envoy::Monitor.new(
	cluster: -> controller{controller.state[:name]},
	include: -> controller{controller.state[:endpoint]}
)
```

## Health Model

Start with a conservative default:

- A registered supervisor worker is healthy.
- A removed/disconnected worker is dead and must disappear from EDS.
- A registered worker that fails an explicit health policy can remain in EDS with an unhealthy endpoint status.

Add optional health policy hooks:

```ruby
Async::Service::Supervisor::Envoy::Monitor.new(
	cluster: -> controller{controller.state[:name]},
	health: -> controller{true}
)
```

The monitor should not actively probe worker HTTP/gRPC health. Health should be derived from supervisor state and optional hooks, because the supervisor is already responsible for monitoring workers.

Later health inputs can include:

- Supervisor connection liveness.
- Process monitor state.
- Memory monitor state.
- Utilization monitor state.
- Custom worker RPCs.

## Implementation Plan

1. Add reusable Ruby xDS control-plane support to `async-grpc-xds`.
2. Keep the current Docker compose xDS test suite, but introduce Ruby control-plane coverage alongside the Go fixture.
3. Implement a minimal ADS server with CDS and EDS support.
4. Add resource builders for clusters, cluster load assignments, and endpoints.
5. Add tests for snapshot versioning, endpoint updates, endpoint removal, and ADS reconnect.
6. Scaffold `~/Developer/socketry/async-service-supervisor-envoy`.
7. Implement `Async::Service::Supervisor::Envoy::Monitor`.
8. Add monitor unit tests using existing supervisor monitor patterns.
9. Add Docker compose e2e tests with Envoy, the supervisor monitor, and multiple backend workers.
10. Document the worker state contract and Envoy bootstrap/config examples.
11. Keep generic Envoy xDS bootstrap examples in `async-grpc-xds`.
12. Keep supervisor-specific runnable examples and Docker compose fixtures in `async-service-supervisor-envoy`.

## E2E Coverage

The Docker compose e2e suite for the monitor gem should cover:

- Worker registration adds an Envoy endpoint.
- Workers without `state[:endpoint]` are ignored.
- Multiple workers are exposed as load-balanced endpoints.
- Multiple service names are exposed as separate configurable clusters.
- Worker removal removes the endpoint from EDS.
- Worker recovery restores the endpoint.
- ADS stream reconnect receives the current snapshot.
- Envoy can route traffic through endpoints discovered from the monitor.
