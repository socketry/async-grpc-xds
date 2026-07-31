# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/resource_builder"

describe Async::GRPC::XDS::ResourceBuilder do
	it "builds an EDS cluster resource" do
		cluster = subject.cluster("myservice", service_name: "backend", connect_timeout: 1.25)
		
		expect(cluster.name).to be == "myservice"
		expect(cluster.type).to be == :EDS
		expect(cluster.eds_cluster_config.service_name).to be == "backend"
		expect(cluster.eds_cluster_config.eds_config.ads).not.to be == nil
		expect(cluster.lb_policy).to be == :ROUND_ROBIN
		expect(cluster.connect_timeout.seconds).to be == 1
		expect(cluster.connect_timeout.nanos).to be == 250_000_000
		expect(cluster.http2_protocol_options).not.to be == nil
	end
	
	it "builds an HTTP/1 EDS cluster resource" do
		cluster = subject.cluster("myservice", protocol: :http1)
		
		expect(cluster.http2_protocol_options).to be == nil
	end
	
	it "builds a client-side weighted-round-robin cluster" do
		policy = subject.client_side_weighted_round_robin(18000, reporting_period: 2.5)
		cluster = subject.cluster("myservice", load_balancing_policy: policy)
		
		typed_configuration = cluster.load_balancing_policy.policies.first.typed_extension_config
		configuration = Envoy::Extensions::LoadBalancingPolicies::ClientSideWeightedRoundRobin::V3::ClientSideWeightedRoundRobin.decode(
			typed_configuration.typed_config.value
		)
		
		expect(cluster.lb_policy).to be == :ROUND_ROBIN
		expect(typed_configuration.name).to be == "envoy.load_balancing_policies.client_side_weighted_round_robin"
		expect(configuration.enable_oob_load_report.value).to be == true
		expect(configuration.oob_reporting_period.seconds).to be == 2
		expect(configuration.oob_reporting_period.nanos).to be == 500_000_000
		expect(configuration.oob_reporting_config.port_value).to be == 18000
	end
	
	it "packs resources using their protobuf type URL" do
		cluster = subject.cluster("myservice")
		resource = subject.pack(cluster)
		
		expect(resource.type_url).to be == "type.googleapis.com/envoy.config.cluster.v3.Cluster"
		expect(resource.value).to be == cluster.to_proto
	end
	
	it "builds endpoint assignments from hashes" do
		assignment = subject.cluster_load_assignment(
			"myservice",
			[
				{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true},
				{addresses: [{address: "127.0.0.2", port: 50052}], healthy: false}
			]
		)
		
		expect(assignment.cluster_name).to be == "myservice"
		
		endpoints = assignment.endpoints.first.lb_endpoints
		expect(endpoints.size).to be == 2
		
		first = endpoints.first
		expect(first.endpoint.address.socket_address.address).to be == "127.0.0.1"
		expect(first.endpoint.address.socket_address.port_value).to be == 50051
		expect(first.health_status).to be == :HEALTHY
		
		second = endpoints.last
		expect(second.endpoint.address.socket_address.address).to be == "127.0.0.2"
		expect(second.endpoint.address.socket_address.port_value).to be == 50052
		expect(second.health_status).to be == :UNHEALTHY
	end
	
	it "builds grouped IP and Unix endpoint addresses" do
		load_balancer_endpoint = subject.load_balancer_endpoint({
			addresses: [
				{path: "/tmp/falcon.ipc"},
				{address: "127.0.0.1", port: 9292},
			],
			healthy: true,
		})
		endpoint = load_balancer_endpoint.endpoint
		
		expect(endpoint.address.pipe.path).to be == "/tmp/falcon.ipc"
		expect(endpoint.additional_addresses.size).to be == 1
		expect(endpoint.additional_addresses.first.address.socket_address.address).to be == "127.0.0.1"
		expect(endpoint.additional_addresses.first.address.socket_address.port_value).to be == 9292
	end
	
	it "assigns a hostname to an endpoint" do
		load_balancer_endpoint = subject.load_balancer_endpoint({
			addresses: [{address: "127.0.0.1", port: 9292}],
			healthy: true,
			hostname: "worker-1",
		})
		
		expect(load_balancer_endpoint.endpoint.hostname).to be == "worker-1"
	end
	
	it "rejects unsupported upstream protocols" do
		expect do
			subject.cluster("myservice", protocol: :http3)
		end.to raise_exception(ArgumentError)
	end
	
	it "rejects endpoints without addresses" do
		expect do
			subject.load_balancer_endpoint(addresses: [], healthy: true)
		end.to raise_exception(ArgumentError)
	end
	
	it "maps health status values" do
		expect(subject.health_status_value(true)).to be == Envoy::Config::Core::V3::HealthStatus::HEALTHY
		expect(subject.health_status_value(false)).to be == Envoy::Config::Core::V3::HealthStatus::UNHEALTHY
		expect(subject.health_status_value(:degraded)).to be == Envoy::Config::Core::V3::HealthStatus::DEGRADED
		expect(subject.health_status_value(:other)).to be == Envoy::Config::Core::V3::HealthStatus::UNKNOWN
	end
end
