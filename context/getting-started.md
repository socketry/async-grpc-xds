# Getting Started

This guide explains how to use `async-grpc-xds` to publish CDS and EDS resources to Envoy, or to discover gRPC backends from Ruby using xDS.

## Installation

Add the gem to your project:

~~~ bash
$ bundle add async-grpc-xds
~~~

The gem provides both sides of an xDS integration:

  - A control-plane server which publishes in-memory resources to Envoy over ADS or dedicated discovery services.
  - An experimental Ruby gRPC client which discovers clusters and endpoints from an ADS server.

## Core Concepts

xDS separates logical proxy configuration from the concrete destinations which currently provide it:

| API | Resource | Purpose |
| --- | --- | --- |
| CDS | `Cluster` | Describes an upstream service, protocol, health checks, load-balancing policy, and how to discover its endpoints. |
| EDS | `ClusterLoadAssignment` | Supplies the concrete IP or Unix-socket endpoints for a cluster. |
| RDS | `RouteConfiguration` | Maps incoming requests to clusters. |
| LDS | `Listener` | Describes the addresses and network filters where Envoy accepts traffic. |

`async-grpc-xds` currently builds and serves CDS and EDS resources. Routes and listeners normally remain in Envoy's bootstrap configuration or come from another control plane.

Three names connect the configuration:

  - The **management cluster** is a static Envoy cluster, such as `xds_cluster`, which reaches the Ruby xDS server.
  - The **application cluster** is the logical upstream service, such as `application`.
  - The EDS `service_name` and `ClusterLoadAssignment#cluster_name` identify the endpoint assignment used by that application cluster. They default to the application cluster name.

The following diagram shows the dedicated CDS and EDS arrangement used throughout this guide:

``` mermaid
flowchart LR
	Bootstrap[Envoy bootstrap] --> Management[xds_cluster]
	Management -->|CDS stream| ControlPlane[Ruby control plane]
	Management -->|EDS stream| ControlPlane
	ControlPlane -->|Cluster| Application[application cluster]
	ControlPlane -->|ClusterLoadAssignment| Workers[worker endpoints]
	Traffic[Application traffic] --> Envoy
	Envoy --> Application
	Application --> Workers
```

## Serving Dedicated CDS and EDS

Dedicated discovery services are a good fit when this control plane owns application clusters and their local workers, but should not claim Envoy's single ADS connection. Another control plane can then use ADS for coordinated listener, route, or other configuration.

Create a control plane, publish an application cluster and its initial workers, then serve the dedicated CDS and EDS interfaces:

``` ruby
require "async"
require "async/grpc/xds"
require "async/http/endpoint"

control_plane = Async::GRPC::XDS::ControlPlane.new(identifier: "application-supervisor")
eds_config = Async::GRPC::XDS::ConfigSource.grpc("xds_cluster")
health_check = Async::GRPC::XDS::HTTPHealthCheck.build(
	"/health",
	interval: 2,
	timeout: 1
)

control_plane.update_cluster(
	"application",
	protocol: :http1,
	eds_config: eds_config,
	health_checks: [health_check]
)

control_plane.update_endpoints("application", [
	{
		hostname: "worker-1",
		addresses: [{address: "127.0.0.1", port: 9292}],
		healthy: true,
	},
	{
		hostname: "worker-2",
		addresses: [{address: "127.0.0.1", port: 9293}],
		healthy: true,
	},
])

server = Async::GRPC::XDS::Server.new(
	control_plane,
	services: [
		Async::GRPC::XDS::ClusterDiscoveryService,
		Async::GRPC::XDS::EndpointDiscoveryService,
	]
)

endpoint = Async::HTTP::Endpoint.parse(
	"http://0.0.0.0:18000",
	protocol: Async::HTTP::Protocol::HTTP2
)

Sync do
	server.run(endpoint)
end
```

The management endpoint uses HTTP/2 because xDS is a gRPC protocol. This example uses plaintext HTTP/2 within a trusted local network; deployments can instead configure TLS on the endpoint.

### Envoy Bootstrap

Envoy must know how to reach the management server before it can discover anything else. Define `xds_cluster` statically and configure CDS to use it:

``` yaml
node:
  id: application-proxy-1
  cluster: application-proxies

admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 19000

dynamic_resources:
  cds_config:
    resource_api_version: V3
    api_config_source:
      api_type: GRPC
      transport_api_version: V3
      grpc_services:
        - envoy_grpc:
            cluster_name: xds_cluster

static_resources:
  listeners:
    - name: ingress
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 8080
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress_http
                route_config:
                  name: local_route
                  validate_clusters: false
                  virtual_hosts:
                    - name: application
                      domains: ["*"]
                      routes:
                        - match:
                            prefix: "/"
                          route:
                            cluster: application
                http_filters:
                  - name: envoy.filters.http.router
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
    - name: xds_cluster
      connect_timeout: 1s
      type: STATIC
      typed_extension_protocol_options:
        envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
          "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
          explicit_http_config:
            http2_protocol_options: {}
      load_assignment:
        cluster_name: xds_cluster
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: 127.0.0.1
                      port_value: 18000
```

The static route names `application` before CDS has delivered that cluster, so `validate_clusters: false` allows the bootstrap configuration to load. Envoy keeps the discovered cluster warming until its EDS assignment arrives.

The `xds_cluster` name must match the name passed to {ruby Async::GRPC::XDS::ConfigSource.grpc}. The generated application cluster then opens its dedicated EDS stream through the same management cluster.

## Publishing Endpoint Changes

The control plane is thread-safe and immediately notifies connected discovery streams after a resource changes. Publish the complete current endpoint assignment whenever workers start, stop, or change health:

``` ruby
control_plane.update_endpoints("application", [
	{
		hostname: "worker-2",
		addresses: [{address: "127.0.0.1", port: 9293}],
		healthy: true,
	},
])
```

This implementation uses state-of-the-world discovery: each EDS response contains the complete assignment requested by Envoy. It does not currently implement the delta discovery RPCs.

Every call to `update_cluster` or `update_endpoints` increments the version for that resource type, even if the generated resource is unchanged. Producers should therefore avoid publishing redundant updates.

To remove a service completely, remove both resources:

``` ruby
control_plane.remove_endpoints("application")
control_plane.remove_cluster("application")
```

### IP and Unix-Socket Addresses

An endpoint must contain one or more addresses. An IP address uses `:address` and `:port`:

``` ruby
{
	addresses: [{address: "127.0.0.1", port: 9292}],
	healthy: true,
}
```

A Unix domain socket uses `:path`:

``` ruby
{
	addresses: [{path: "/run/application/worker-1.ipc"}],
	healthy: true,
}
```

Several addresses in one `:addresses` array describe alternative addresses for one logical load-balancer endpoint. The first becomes Envoy's primary address and the remainder become `additional_addresses`; they do not represent additional workers.

### Health

The `:healthy` value sets the EDS `health_status` for an endpoint. It accepts healthy, unhealthy, degraded, or unknown states; booleans map to healthy and unhealthy.

This reported state is separate from active health checks. Adding a health check to the cluster tells Envoy to probe every published endpoint itself:

``` ruby
health_check = Async::GRPC::XDS::HTTPHealthCheck.build(
	"/health",
	interval: 2,
	timeout: 1,
	unhealthy_threshold: 2,
	healthy_threshold: 1
)

control_plane.update_cluster(
	"application",
	protocol: :http1,
	eds_config: Async::GRPC::XDS::ConfigSource.grpc("xds_cluster"),
	health_checks: [health_check]
)
```

Use reported health for information already known by the resource owner, such as whether a worker remains registered. Use active health checks when Envoy should independently verify that it can send application traffic to the endpoint.

## ADS or Dedicated Services

Both transports carry the same `DiscoveryRequest` and `DiscoveryResponse` messages. The difference is how Envoy organizes its streams and management servers:

| | ADS | Dedicated CDS and EDS |
| --- | --- | --- |
| Streams | One aggregated stream for several resource types. | One stream per resource type. |
| Coordination | Provides ordering across related resource types from one control plane. | Each resource type progresses independently. |
| Ownership | Envoy has one ADS management server. | Each resource type can use its own configuration source. |
| Best fit | One control plane owns coordinated proxy configuration. | A focused control plane owns only clusters or endpoints. |

The default server exposes ADS:

``` ruby
control_plane = Async::GRPC::XDS::ControlPlane.new
control_plane.update_cluster("application", protocol: :http1)
control_plane.update_endpoints("application", endpoints)

server = Async::GRPC::XDS::Server.new(control_plane)
```

{ruby Async::GRPC::XDS::Cluster.build} uses ADS for EDS by default, so no explicit `eds_config` is needed in this mode. Configure Envoy accordingly:

``` yaml
dynamic_resources:
  ads_config:
    api_type: GRPC
    transport_api_version: V3
    grpc_services:
      - envoy_grpc:
          cluster_name: xds_cluster
  cds_config:
    resource_api_version: V3
    ads: {}
```

Do not use the default ADS EDS source when serving dedicated CDS and EDS. In that arrangement, pass `ConfigSource.grpc("xds_cluster")` while building or updating every application cluster.

## Using the Ruby xDS Client

{ruby Async::GRPC::XDS::Client} is an experimental gRPC client which discovers a named cluster and its healthy endpoints over ADS, then load-balances RPC calls between them.

Supply bootstrap configuration directly:

``` ruby
bootstrap = {
	xds_servers: [
		{
			server_uri: "127.0.0.1:18000",
			channel_creds: [{type: "insecure"}],
		}
	],
	node: {
		id: "orders-client-1",
		cluster: "orders-clients",
	}
}

Sync do
	client = Async::GRPC::XDS::Client.new("application", bootstrap: bootstrap)
	
	begin
		stub = client.stub(Greeter::Interface, "example.Greeter")
		response = stub.say_hello(Greeter::Request.new(name: "World"))
	ensure
		client.close
	end
end
```

Alternatively, pass the path to a JSON bootstrap file. When `bootstrap` is omitted, the client checks `GRPC_XDS_BOOTSTRAP` and then `~/.config/grpc/bootstrap.json`.

The Ruby client currently consumes ADS, supports CDS and EDS, filters endpoints by reported health, and provides basic client-side load balancing and retry behavior. Dedicated CDS and EDS client streams are not yet implemented.

## Operational Checks

Envoy's admin interface shows whether it accepted the resources and whether the application cluster has usable members:

~~~ bash
$ curl -s http://127.0.0.1:19000/config_dump
$ curl -s http://127.0.0.1:19000/clusters
$ curl -s http://127.0.0.1:19000/stats | grep -E 'cluster\.application\.(warming|membership_healthy|update_rejected)'
~~~

When a cluster remains in `warming`, check:

  - The `xds_cluster` address and port reach the Ruby server using HTTP/2.
  - The management cluster name matches the name in every gRPC configuration source.
  - The CDS cluster name, EDS service name, and `ClusterLoadAssignment#cluster_name` agree.
  - A dedicated CDS cluster uses a dedicated EDS configuration source rather than `ads: {}`.
  - Envoy has not incremented `update_rejected`; rejected responses are also returned to the control plane as NACKs and logged.

## Current Scope

`async-grpc-xds` currently provides:

  - xDS v3 protobuf definitions.
  - State-of-the-world ADS, CDS, and EDS server streams.
  - In-memory cluster and endpoint resources with per-type versions.
  - HTTP/1 and HTTP/2 upstream cluster configuration.
  - IP, Unix-socket, health-status, active HTTP health-check, and out-of-band ORCA policy resource builders.
  - An experimental ADS-based Ruby gRPC client.

Delta discovery, complete NACK recovery, persistent resource storage, LDS/RDS serving, locality weighting, and complete routing semantics are not implemented yet.
