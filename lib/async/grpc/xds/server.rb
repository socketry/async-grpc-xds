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
				# @parameter options [Hash] Default options forwarded to `Async::HTTP::Server`.
				def initialize(control_plane = ControlPlane.new, **options)
					@control_plane = control_plane
					@dispatcher = Async::GRPC::Dispatcher.new
					@dispatcher.register(Service.new(@control_plane))
					@options = options
				end
				
				attr :control_plane
				attr :dispatcher
				
				# Run the xDS server on an endpoint.
				# @parameter endpoint [Async::HTTP::Endpoint] The endpoint to bind.
				# @parameter options [Hash] Options forwarded to `Async::HTTP::Server`.
				# @returns [void]
				# @asynchronous
				def run(endpoint, **options)
					server = Async::HTTP::Server.new(@dispatcher, endpoint, **@options, **options)
					server.run
				end
			end
		end
	end
end
