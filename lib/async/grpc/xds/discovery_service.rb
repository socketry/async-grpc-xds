# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "async/grpc/service"
require "protocol/grpc/error"
require "protocol/grpc/status"

require_relative "control_plane"
require_relative "stream"

module Async
	module GRPC
		module XDS
			# Shared implementation for state-of-the-world xDS discovery services.
			class DiscoveryService < Async::GRPC::Service
				# Initialize a discovery service.
				# @parameter interface [Class] The gRPC service interface.
				# @parameter service_name [String] The fully qualified gRPC service name.
				# @parameter control_plane [ControlPlane] The control plane that provides resources.
				# @parameter resource_type [String | Nil] The fixed resource type, or `nil` for aggregated discovery.
				def initialize(interface, service_name, control_plane, resource_type: nil)
					super(interface, service_name)
					
					@control_plane = control_plane
					@resource_type = resource_type
				end
				
				# Serve a state-of-the-world discovery stream.
				# @parameter input [Enumerable] The stream of discovery requests.
				# @parameter output [Interface(:write)] The discovery response stream.
				# @asynchronous
				def stream_resources(input, output)
					stream = Stream.new(@control_plane, output, resource_type: @resource_type)
					@control_plane.register_stream(stream)
					
					reader = Async::Task.current.async do
						input.each do |request|
							stream.request(request)
						end
					end
					
					writer = Async::Task.current.async do
						stream.run
					end
					
					reader.wait
				ensure
					stream&.close
					reader&.stop
					writer&.stop
					@control_plane.remove_stream(stream) if stream
				end
				
				# Reject a delta discovery stream, which is not supported.
				# @raises [Protocol::GRPC::Error] Always raised because delta xDS is not implemented.
				def delta_resources
					raise Protocol::GRPC::Error.new(
						Protocol::GRPC::Status::UNIMPLEMENTED,
						"Delta xDS is not implemented."
					)
				end
				
			end
		end
	end
end
