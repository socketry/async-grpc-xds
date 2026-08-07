# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "envoy/service/discovery/v3/discovery_pb"
require "protocol/grpc/interface"

require_relative "control_plane"
require_relative "discovery_service"

module Async
	module GRPC
		module XDS
			# Serves Endpoint Discovery Service requests from a {ControlPlane}.
			class EndpointDiscoveryService < DiscoveryService
				SERVICE_NAME = "envoy.service.endpoint.v3.EndpointDiscoveryService"
				RESOURCE_TYPE = ControlPlane::ENDPOINT_TYPE
				
				# The gRPC interface for endpoint discovery.
				class Interface < Protocol::GRPC::Interface
					rpc :StreamEndpoints,
						request_class: Envoy::Service::Discovery::V3::DiscoveryRequest,
						response_class: Envoy::Service::Discovery::V3::DiscoveryResponse,
						streaming: :bidirectional
					
					rpc :DeltaEndpoints,
						request_class: Envoy::Service::Discovery::V3::DeltaDiscoveryRequest,
						response_class: Envoy::Service::Discovery::V3::DeltaDiscoveryResponse,
						streaming: :bidirectional
				end
				
				# Initialize an Endpoint Discovery Service.
				# @parameter control_plane [ControlPlane] The control plane that provides endpoint assignments.
				def initialize(control_plane)
					super(Interface, SERVICE_NAME, control_plane, resource_type: RESOURCE_TYPE)
				end
				
				# Serve a state-of-the-world endpoint discovery stream.
				# @parameter input [Enumerable] The stream of discovery requests.
				# @parameter output [Interface(:write)] The discovery response stream.
				# @parameter call [Object] The gRPC call context.
				# @asynchronous
				def stream_endpoints(input, output, call)
					stream_resources(input, output)
				end
				
				# Reject a delta endpoint discovery stream, which is not supported.
				# @raises [Protocol::GRPC::Error] Always raised because delta xDS is not implemented.
				def delta_endpoints(input, output, call)
					delta_resources
				end
			end
		end
	end
end
