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
				def initialize(control_plane = ControlPlane.new, **options)
					@control_plane = control_plane
					@dispatcher = Async::GRPC::Dispatcher.new
					@dispatcher.register(Service.new(@control_plane))
					@options = options
				end
				
				attr :control_plane
				attr :dispatcher
				
				def run(endpoint, **options)
					server = Async::HTTP::Server.new(@dispatcher, endpoint, **@options, **options)
					server.run
				end
			end
		end
	end
end
