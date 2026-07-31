# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "google/protobuf/any_pb"
require "google/protobuf/duration_pb"
require "google/protobuf/wrappers_pb"

require "envoy/config/cluster/v3/cluster_pb"
require "envoy/config/core/v3/address_pb"
require "envoy/config/core/v3/config_source_pb"
require "envoy/config/core/v3/health_check_pb"
require "envoy/config/core/v3/protocol_pb"
require "envoy/config/endpoint/v3/endpoint_pb"
require "envoy/config/endpoint/v3/endpoint_components_pb"
require "envoy/extensions/load_balancing_policies/client_side_weighted_round_robin/v3/client_side_weighted_round_robin_pb"

module Async
	module GRPC
		module XDS
			# Builds Envoy xDS resource protobufs.
			module ResourceBuilder
				TYPE_URL_PREFIX = "type.googleapis.com"
				
				CLUSTER_TYPE = "#{TYPE_URL_PREFIX}/envoy.config.cluster.v3.Cluster"
				ENDPOINT_TYPE = "#{TYPE_URL_PREFIX}/envoy.config.endpoint.v3.ClusterLoadAssignment"
				
				# Pack a protobuf resource into a `google.protobuf.Any` message.
				# @parameter resource [Google::Protobuf::MessageExts] The protobuf resource to pack.
				# @returns [Google::Protobuf::Any] The packed resource.
				def self.pack(resource)
					Google::Protobuf::Any.new(
						type_url: "#{TYPE_URL_PREFIX}/#{resource.class.descriptor.name}",
						value: resource.to_proto
					)
				end
				
				# Build an EDS cluster resource.
				# @parameter name [String] The cluster name.
				# @parameter service_name [String] The EDS service name.
				# @parameter load_balancing_policy [Envoy::Config::Cluster::V3::LoadBalancingPolicy | Nil] The typed Envoy load-balancing policy.
				# @parameter connect_timeout [Numeric] The upstream connection timeout in seconds.
				# @parameter protocol [Symbol] The canonical upstream protocol, either `:http1` or `:http2`.
				# @returns [Envoy::Config::Cluster::V3::Cluster] The generated cluster resource.
				# @raises [ArgumentError] If the upstream protocol is unsupported.
				def self.cluster(name, service_name: name, load_balancing_policy: nil, connect_timeout: 5, protocol: :http2)
					options = {
						name: name.to_s,
						type: Envoy::Config::Cluster::V3::Cluster::DiscoveryType::EDS,
						eds_cluster_config: Envoy::Config::Cluster::V3::Cluster::EdsClusterConfig.new(
							service_name: service_name.to_s,
							eds_config: Envoy::Config::Core::V3::ConfigSource.new(
								ads: Envoy::Config::Core::V3::AggregatedConfigSource.new
							)
						),
						connect_timeout: duration(connect_timeout),
					}
					
					options[:load_balancing_policy] = load_balancing_policy if load_balancing_policy
					
					case protocol
					when :http1
						# Envoy uses HTTP/1 by default.
					when :http2
						options[:http2_protocol_options] = Envoy::Config::Core::V3::Http2ProtocolOptions.new
					else
						raise ArgumentError, "Unsupported upstream protocol: #{protocol.inspect}"
					end
					
					Envoy::Config::Cluster::V3::Cluster.new(**options)
				end
				
				# Build the Envoy client-side weighted-round-robin policy with out-of-band ORCA reporting.
				# @parameter port [Integer] The alternative TCP port hosting the ORCA service.
				# @parameter reporting_period [Numeric] The requested ORCA reporting interval in seconds.
				# @returns [Envoy::Config::Cluster::V3::LoadBalancingPolicy] The typed load-balancing policy.
				def self.client_side_weighted_round_robin(port, reporting_period: 1)
					configuration = Envoy::Extensions::LoadBalancingPolicies::ClientSideWeightedRoundRobin::V3::ClientSideWeightedRoundRobin.new(
						enable_oob_load_report: Google::Protobuf::BoolValue.new(value: true),
						oob_reporting_period: duration(reporting_period),
						oob_reporting_config: Envoy::Extensions::LoadBalancingPolicies::Common::V3::OrcaOobReportingConfig.new(
							port_value: Integer(port)
						)
					)
					
					Envoy::Config::Cluster::V3::LoadBalancingPolicy.new(
						policies: [
							Envoy::Config::Cluster::V3::LoadBalancingPolicy::Policy.new(
								typed_extension_config: Envoy::Config::Core::V3::TypedExtensionConfig.new(
									name: "envoy.load_balancing_policies.client_side_weighted_round_robin",
									typed_config: pack(configuration)
								)
							)
						]
					)
				end
				
				# Build an EDS cluster load assignment from normalized endpoint state.
				# @parameter cluster_name [String] The cluster name.
				# @parameter endpoints [Array(Hash)] The endpoints, each containing `:addresses` and `:healthy`.
				# @returns [Envoy::Config::Endpoint::V3::ClusterLoadAssignment] The generated load assignment.
				def self.cluster_load_assignment(cluster_name, endpoints)
					Envoy::Config::Endpoint::V3::ClusterLoadAssignment.new(
						cluster_name: cluster_name.to_s,
						endpoints: [
							Envoy::Config::Endpoint::V3::LocalityLbEndpoints.new(
								lb_endpoints: endpoints.map{|endpoint| load_balancer_endpoint(endpoint)}
							)
						]
					)
				end
				
				# Build an Envoy load-balancer endpoint from normalized endpoint state.
				# @parameter endpoint [Hash] The endpoint containing `:addresses` and `:healthy`.
				# @returns [Envoy::Config::Endpoint::V3::LbEndpoint] The generated load-balancer endpoint.
				# @raises [KeyError] If required endpoint state is missing.
				# @raises [ArgumentError] If the endpoint has no addresses.
				def self.load_balancer_endpoint(endpoint)
					addresses, healthy = endpoint.fetch_values(:addresses, :healthy)
					raise ArgumentError, "An endpoint requires at least one address!" if addresses.empty?
					
					address, *additional_addresses = addresses
					
					Envoy::Config::Endpoint::V3::LbEndpoint.new(
						endpoint: Envoy::Config::Endpoint::V3::Endpoint.new(
							address: build_address(address),
							hostname: endpoint[:hostname],
							additional_addresses: additional_addresses.map do |additional_address|
								Envoy::Config::Endpoint::V3::Endpoint::AdditionalAddress.new(
									address: build_address(additional_address)
								)
							end
						),
						health_status: health_status_value(healthy)
					)
				end
				
				# Build an Envoy address from a normalized IP or Unix address.
				# @parameter address [Hash] An IP `:address` and `:port`, or a Unix `:path`.
				# @returns [Envoy::Config::Core::V3::Address] The generated Envoy address.
				# @raises [KeyError] If required IP address state is missing.
				# @private
				def self.build_address(address)
					if path = address[:path]
						Envoy::Config::Core::V3::Address.new(
							pipe: Envoy::Config::Core::V3::Pipe.new(path: path)
						)
					else
						Envoy::Config::Core::V3::Address.new(
							socket_address: Envoy::Config::Core::V3::SocketAddress.new(
								protocol: Envoy::Config::Core::V3::SocketAddress::Protocol::TCP,
								address: address.fetch(:address),
								port_value: address.fetch(:port)
							)
						)
					end
				end
				
				private_class_method :build_address
				
				# Convert seconds to a protobuf duration.
				# @parameter seconds [Numeric] The duration in seconds.
				# @returns [Google::Protobuf::Duration] The protobuf duration.
				def self.duration(seconds)
					whole_seconds = seconds.to_i
					nanos = ((seconds.to_f - whole_seconds) * 1_000_000_000).to_i
					
					Google::Protobuf::Duration.new(seconds: whole_seconds, nanos: nanos)
				end
				
				# Convert an endpoint health status to its Envoy enum value.
				# @parameter healthy [Boolean | Symbol | String] The normalized health status.
				# @returns [Integer] The Envoy health-status enum value.
				def self.health_status_value(healthy)
					case healthy
					when :healthy, :HEALTHY, "healthy", "HEALTHY", true
						Envoy::Config::Core::V3::HealthStatus::HEALTHY
					when :unhealthy, :UNHEALTHY, "unhealthy", "UNHEALTHY", false
						Envoy::Config::Core::V3::HealthStatus::UNHEALTHY
					when :degraded, :DEGRADED, "degraded", "DEGRADED"
						Envoy::Config::Core::V3::HealthStatus::DEGRADED
					else
						Envoy::Config::Core::V3::HealthStatus::UNKNOWN
					end
				end
			end
		end
	end
end
