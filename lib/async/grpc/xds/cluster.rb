# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "google/protobuf/duration_pb"

require "envoy/config/cluster/v3/cluster_pb"
require "envoy/config/core/v3/protocol_pb"

require_relative "config_source"

module Async
	module GRPC
		module XDS
			# Builds Envoy cluster resources.
			module Cluster
				extend self
				
				TYPE_URL = "type.googleapis.com/envoy.config.cluster.v3.Cluster"
				
				# Build an EDS cluster resource.
				# @parameter name [String] The cluster name.
				# @parameter service_name [String] The EDS service name.
				# @parameter eds_config [Envoy::Config::Core::V3::ConfigSource] The source used to discover endpoint assignments.
				# @parameter load_balancing_policy [Envoy::Config::Cluster::V3::LoadBalancingPolicy | Nil] The typed Envoy load-balancing policy.
				# @parameter health_checks [Array(Envoy::Config::Core::V3::HealthCheck)] The active health checks applied to cluster endpoints.
				# @parameter connect_timeout [Numeric] The upstream connection timeout in seconds.
				# @parameter protocol [Symbol] The canonical upstream protocol, either `:http1` or `:http2`.
				# @returns [Envoy::Config::Cluster::V3::Cluster] The generated cluster resource.
				# @raises [ArgumentError] If the upstream protocol is unsupported.
				def build(name, service_name: name, eds_config: ConfigSource.ads, load_balancing_policy: nil, health_checks: [], connect_timeout: 5, protocol: :http2)
					options = {
						name: name.to_s,
						type: Envoy::Config::Cluster::V3::Cluster::DiscoveryType::EDS,
						eds_cluster_config: Envoy::Config::Cluster::V3::Cluster::EdsClusterConfig.new(
							service_name: service_name.to_s,
							eds_config: eds_config
						),
						connect_timeout: duration(connect_timeout),
						health_checks: health_checks,
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
				
				private
				
				# Convert seconds to a protobuf duration.
				# @parameter seconds [Numeric] The duration in seconds.
				# @returns [Google::Protobuf::Duration] The protobuf duration.
				# @private
				def duration(seconds)
					whole_seconds = seconds.to_i
					nanos = ((seconds.to_f - whole_seconds) * 1_000_000_000).to_i
					
					Google::Protobuf::Duration.new(seconds: whole_seconds, nanos: nanos)
				end
			end
		end
	end
end
