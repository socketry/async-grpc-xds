# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/resource_builder"
require "async/grpc/xds/resources"

describe Async::GRPC::XDS::Resources::Cluster do
	it "parses hash cluster data" do
		cluster = subject.new(
			name: "myservice",
			type: "EDS",
			load_balancer_policy: "LEAST_REQUEST",
			health_checks: [
				{type: :HTTP, interval: 5, timeout: 1, http_health_check: {path: "/ready"}}
			]
		)
		
		expect(cluster.name).to be == "myservice"
		expect(cluster.type).to be == :EDS
		expect(cluster.load_balancer_policy).to be == :LEAST_REQUEST
		expect(cluster).to be(:eds_cluster?)
		expect(cluster.health_checks).to be == [
			{type: :HTTP, timeout: 1, interval: 5, path: "/ready"}
		]
	end
	
	it "parses cluster type and load balancer policy variants" do
		expect(subject.new(name: "static", type: :STATIC).type).to be == :STATIC
		expect(subject.new(name: "logical", type: :LOGICAL_DNS).type).to be == :LOGICAL_DNS
		expect(subject.new(name: "strict", type: :STRICT_DNS).type).to be == :STRICT_DNS
		expect(subject.new(name: "unknown", type: :UNKNOWN).type).to be == :EDS
		
		expect(subject.new(name: "round-robin", lb_policy: :ROUND_ROBIN).load_balancer_policy).to be == :ROUND_ROBIN
		expect(subject.new(name: "ring-hash", lb_policy: :RING_HASH).load_balancer_policy).to be == :RING_HASH
		expect(subject.new(name: "maglev", lb_policy: :MAGLEV).load_balancer_policy).to be == :MAGLEV
		expect(subject.new(name: "unknown-policy", lb_policy: :UNKNOWN).load_balancer_policy).to be == :ROUND_ROBIN
	end
	
	it "parses hash health check variants" do
		cluster = subject.new(
			name: "myservice",
			health_checks: [
				{health_checker: {type: :HTTP}},
				{health_checker: {type: :gRPC}, interval: "5.5", timeout: nil},
				{health_checker: {type: :TCP}},
				{health_checker: {type: :unknown}}
			]
		)
		
		expect(cluster.health_checks[0][:type]).to be == :HTTP
		expect(cluster.health_checks[1]).to be == {type: :gRPC, timeout: nil, interval: 5.5, path: "/health"}
		expect(cluster.health_checks[2][:type]).to be == :TCP
		expect(cluster.health_checks[3][:type]).to be == :HTTP
	end
	
	it "parses legacy hash load balancer policy names" do
		cluster = subject.new(name: "myservice", type: :EDS, lb_policy: :RANDOM)
		
		expect(cluster.load_balancer_policy).to be == :RANDOM
	end
	
	it "parses protobuf cluster data" do
		protobuf = Async::GRPC::XDS::ResourceBuilder.cluster("myservice", load_balancer_policy: :least_request)
		cluster = subject.from_proto(protobuf)
		
		expect(cluster.name).to be == "myservice"
		expect(cluster.type).to be == :EDS
		expect(cluster.load_balancer_policy).to be == :LEAST_REQUEST
		expect(cluster).to be(:eds_cluster?)
	end
	
	it "parses protobuf health checks" do
		protobuf = Async::GRPC::XDS::ResourceBuilder.cluster("myservice")
		protobuf.health_checks << Envoy::Config::Core::V3::HealthCheck.new(
			timeout: Google::Protobuf::Duration.new(seconds: 1, nanos: 500_000_000),
			interval: Google::Protobuf::Duration.new(seconds: 10),
			http_health_check: Envoy::Config::Core::V3::HealthCheck::HttpHealthCheck.new(path: "/healthz")
		)
		
		cluster = subject.from_proto(protobuf)
		
		expect(cluster.health_checks).to be == [
			{type: :HTTP, timeout: 1.5, interval: 10.0, path: "/healthz"}
		]
	end
	
	it "parses protobuf gRPC and TCP health checks" do
		protobuf = Async::GRPC::XDS::ResourceBuilder.cluster("myservice")
		protobuf.health_checks << Envoy::Config::Core::V3::HealthCheck.new(
			grpc_health_check: Envoy::Config::Core::V3::HealthCheck::GrpcHealthCheck.new
		)
		protobuf.health_checks << Envoy::Config::Core::V3::HealthCheck.new(
			tcp_health_check: Envoy::Config::Core::V3::HealthCheck::TcpHealthCheck.new
		)
		
		cluster = subject.from_proto(protobuf)
		
		expect(cluster.health_checks.map{|health_check| health_check[:type]}).to be == [:gRPC, :TCP]
	end
	
	it "parses object-style health check oneof values" do
		health_checker = Object.new
		health_checker.define_singleton_method(:http_health_check) do
			Struct.new(:path).new("/object")
		end
		
		check = Struct.new(:health_checker, :timeout, :interval) do
			def http_health_check
				Struct.new(:path).new("/object")
			end
		end.new(health_checker, 1, 2)
		
		cluster = subject.new(name: "myservice", health_checks: [check])
		
		expect(cluster.health_checks).to be == [
			{type: :HTTP, timeout: 1, interval: 2, path: "/object"}
		]
	end
	
	it "parses object-style gRPC and TCP health check oneof values" do
		grpc_health_checker = Object.new
		grpc_health_checker.define_singleton_method(:grpc_health_check){Object.new}
		tcp_health_checker = Object.new
		tcp_health_checker.define_singleton_method(:tcp_health_check){Object.new}
		
		grpc_check = Struct.new(:health_checker, :timeout, :interval) do
		end.new(grpc_health_checker, nil, nil)
		tcp_check = Struct.new(:health_checker, :timeout, :interval) do
		end.new(tcp_health_checker, nil, nil)
		
		cluster = subject.new(name: "myservice", health_checks: [grpc_check, tcp_check])
		
		expect(cluster.health_checks.map{|health_check| health_check[:type]}).to be == [:gRPC, :TCP]
	end
end

describe Async::GRPC::XDS::Resources::ClusterLoadAssignment do
	it "parses hash endpoint assignments" do
		assignment = subject.new(
			cluster_name: "myservice",
			endpoints: [
				{
					lb_endpoints: [
						{
							endpoint: {
								address: {
									socket_address: {
										address: "127.0.0.1",
										port_value: 50051
									}
								}
							},
							health_status: :HEALTHY
						}
					]
				}
			]
		)
		
		expect(assignment.cluster_name).to be == "myservice"
		expect(assignment.endpoints.size).to be == 1
		
		endpoint = assignment.endpoints.first
		expect(endpoint.address).to be == "127.0.0.1"
		expect(endpoint.port).to be == 50051
		expect(endpoint).to be(:healthy?)
		expect(endpoint.uri).to be == "http://127.0.0.1:50051"
	end
	
	it "parses protobuf endpoint assignments" do
		protobuf = Async::GRPC::XDS::ResourceBuilder.cluster_load_assignment(
			"myservice",
			[
				{address: "127.0.0.1", port: 50051},
				{address: "127.0.0.2", port: 50052, healthy: false}
			]
		)
		assignment = subject.from_proto(protobuf)
		
		expect(assignment.cluster_name).to be == "myservice"
		expect(assignment.endpoints.map(&:address)).to be == ["127.0.0.1", "127.0.0.2"]
		expect(assignment.endpoints.map(&:port)).to be == [50051, 50052]
		expect(assignment.endpoints.map(&:healthy?)).to be == [true, false]
	end
end

describe Async::GRPC::XDS::Resources::Endpoint do
	it "treats unknown endpoints as healthy" do
		endpoint = subject.new(
			endpoint: {
				address: {
					socket_address: {
						address: "127.0.0.1",
						port_value: 50051
					}
				}
			}
		)
		
		expect(endpoint.health_status).to be == :UNKNOWN
		expect(endpoint).to be(:healthy?)
	end
	
	it "uses the configured endpoint scheme" do
		previous = ENV["XDS_ENDPOINT_SCHEME"]
		ENV["XDS_ENDPOINT_SCHEME"] = "https"
		
		endpoint = subject.new(
			endpoint: {
				address: {
					socket_address: {
						address: "example.com",
						port_value: 443
					}
				}
			}
		)
		
		expect(endpoint.uri).to be == "https://example.com:443"
	ensure
		ENV["XDS_ENDPOINT_SCHEME"] = previous
	end
	
	it "parses degraded endpoints as unhealthy" do
		endpoint = subject.new(
			endpoint: {
				address: {
					socket_address: {
						address: "127.0.0.1",
						port_value: 50051
					}
				}
			},
			health_status: :DEGRADED
		)
		
		expect(endpoint.health_status).to be == :DEGRADED
		expect(endpoint).not.to be(:healthy?)
	end
	
	it "falls back to unknown for unsupported health status values" do
		endpoint = subject.new(
			endpoint: {
				address: {
					socket_address: {
						address: "127.0.0.1",
						port_value: 50051
					}
				}
			},
			health_status: :DRAINING
		)
		
		expect(endpoint.health_status).to be == :UNKNOWN
	end
end





