# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "envoy/config/core/v3/config_source_pb"
require "envoy/config/core/v3/grpc_service_pb"

module Async
	module GRPC
		module XDS
			# Builds Envoy xDS configuration sources.
			module ConfigSource
				extend self
				
				# Build a configuration source that uses the global ADS server.
				# @returns [Envoy::Config::Core::V3::ConfigSource] The ADS configuration source.
				def ads
					Envoy::Config::Core::V3::ConfigSource.new(
						ads: Envoy::Config::Core::V3::AggregatedConfigSource.new
					)
				end
				
				# Build a configuration source for a dedicated gRPC discovery service.
				# @parameter cluster_name [String] The static Envoy cluster used to reach the management server.
				# @returns [Envoy::Config::Core::V3::ConfigSource] The gRPC API configuration source.
				def grpc(cluster_name)
					Envoy::Config::Core::V3::ConfigSource.new(
						resource_api_version: :V3,
						api_config_source: Envoy::Config::Core::V3::ApiConfigSource.new(
							api_type: :GRPC,
							transport_api_version: :V3,
							grpc_services: [
								Envoy::Config::Core::V3::GrpcService.new(
									envoy_grpc: Envoy::Config::Core::V3::GrpcService::EnvoyGrpc.new(
										cluster_name: cluster_name.to_s
									)
								)
							]
						)
					)
				end
			end
		end
	end
end
