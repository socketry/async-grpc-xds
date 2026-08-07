# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/dispatcher"
require "async/http/server"

require_relative "control_plane"
require_relative "service"

module Async
	module GRPC
		module XDS
			# Convenience wrapper for serving an xDS control plane over gRPC.
			class Server
				# Initialize an xDS server.
				# @parameter control_plane [ControlPlane] The control plane to serve.
				# @parameter services [Array(Class)] The discovery service classes to register.
				# @parameter options [Hash] Default options forwarded to `Async::HTTP::Server`.
				def initialize(control_plane = ControlPlane.new, services: [Service], **options)
					@control_plane = control_plane
					@dispatcher = Async::GRPC::Dispatcher.new
					@services = services.map do |service|
						service.new(@control_plane).tap do |instance|
							@dispatcher.register(instance)
						end
					end
					@options = options
				end
				
				attr :control_plane
				attr :dispatcher
				attr :services
				
				# Run the xDS server on an endpoint.
				# @parameter endpoint [Async::HTTP::Endpoint] The endpoint to bind.
				# @parameter options [Hash] Options forwarded to `Async::HTTP::Server`.
				# @asynchronous
				def run(endpoint, **options)
					server = Async::HTTP::Server.new(@dispatcher, endpoint, **@options, **options)
					server.run
				end
			end
		end
	end
end
