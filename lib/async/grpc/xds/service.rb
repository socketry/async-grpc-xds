# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "envoy/service/discovery/v3/aggregated_discovery_service"

require_relative "discovery_service"

module Async
	module GRPC
		module XDS
			# Serves Envoy Aggregated Discovery Service requests from a {ControlPlane}.
			class Service < DiscoveryService
				SERVICE_NAME = "envoy.service.discovery.v3.AggregatedDiscoveryService"
				
				# Initialize an Aggregated Discovery Service.
				# @parameter control_plane [ControlPlane] The control plane that provides resources.
				def initialize(control_plane)
					super(Envoy::Service::Discovery::V3::AggregatedDiscoveryService, SERVICE_NAME, control_plane)
				end
				
				# Serve a state-of-the-world Aggregated Discovery Service stream.
				# @parameter input [Enumerable] The stream of discovery requests.
				# @parameter output [Interface(:write)] The discovery response stream.
				# @parameter call [Object] The gRPC call context.
				# @asynchronous
				def stream_aggregated_resources(input, output, call)
					stream_resources(input, output)
				end
				
				# Reject a delta Aggregated Discovery Service stream, which is not supported.
				# @parameter input [Enumerable] The stream of delta discovery requests.
				# @parameter output [Interface(:write)] The delta discovery response stream.
				# @parameter call [Object] The gRPC call context.
				# @raises [Protocol::GRPC::Error] Always raised because delta xDS is not implemented.
				def delta_aggregated_resources(input, output, call)
					delta_resources
				end
			end
		end
	end
end
