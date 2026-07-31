# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "google/protobuf/any_pb"
require "google/protobuf/duration_pb"
require "google/protobuf/wrappers_pb"

require "envoy/config/cluster/v3/cluster_pb"
require "envoy/extensions/load_balancing_policies/client_side_weighted_round_robin/v3/client_side_weighted_round_robin_pb"

module Async
	module GRPC
		module XDS
			# Builds Envoy's client-side weighted-round-robin policy with out-of-band ORCA reporting.
			module ClientSideWeightedRoundRobin
				# Build the typed load-balancing policy.
				# @parameter port [Integer] The alternative TCP port hosting the ORCA service.
				# @parameter reporting_period [Numeric] The requested ORCA reporting interval in seconds.
				# @returns [Envoy::Config::Cluster::V3::LoadBalancingPolicy] The typed load-balancing policy.
				def self.build(port, reporting_period: 1)
					seconds = reporting_period.to_i
					duration = Google::Protobuf::Duration.new(
						seconds: seconds,
						nanos: ((reporting_period.to_f - seconds) * 1_000_000_000).to_i
					)
					configuration = Envoy::Extensions::LoadBalancingPolicies::ClientSideWeightedRoundRobin::V3::ClientSideWeightedRoundRobin.new(
						enable_oob_load_report: Google::Protobuf::BoolValue.new(value: true),
						oob_reporting_period: duration,
						oob_reporting_config: Envoy::Extensions::LoadBalancingPolicies::Common::V3::OrcaOobReportingConfig.new(
							port_value: Integer(port)
						)
					)
					
					Envoy::Config::Cluster::V3::LoadBalancingPolicy.new(
						policies: [
							Envoy::Config::Cluster::V3::LoadBalancingPolicy::Policy.new(
								typed_extension_config: Envoy::Config::Core::V3::TypedExtensionConfig.new(
									name: "envoy.load_balancing_policies.client_side_weighted_round_robin",
									typed_config: Google::Protobuf::Any.new(
										type_url: "type.googleapis.com/#{configuration.class.descriptor.name}",
										value: configuration.to_proto
									)
								)
							)
						]
					)
				end
			end
		end
	end
end
