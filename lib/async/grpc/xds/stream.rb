# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/queue"
require "protocol/grpc/error"
require "protocol/grpc/status"
require "set"

module Async
	module GRPC
		module XDS
			# Represents one discovery stream and its subscribed resources.
			class Stream
				# Initialize a discovery stream.
				# @parameter control_plane [ControlPlane] The control plane that provides resources.
				# @parameter output [Interface(:write)] The discovery response stream.
				# @parameter resource_type [String | Nil] The fixed resource type, or `nil` for aggregated discovery.
				def initialize(control_plane, output, resource_type: nil)
					@control_plane = control_plane
					@output = output
					@resource_type = resource_type
					@subscriptions = {}
					@versions = {}
					@queue = Async::Queue.new
					@closed = false
				end
				
				# Process a discovery request and update the stream's subscriptions.
				# @parameter request [Envoy::Service::Discovery::V3::DiscoveryRequest] The discovery request.
				def request(request)
					type_url = request.type_url
					
					if @resource_type
						if type_url.nil? || type_url.empty?
							type_url = @resource_type
						elsif type_url != @resource_type
							raise Protocol::GRPC::Error.new(
								Protocol::GRPC::Status::INVALID_ARGUMENT,
								"Expected resource type #{@resource_type.inspect}, but received #{type_url.inspect}."
							)
						end
					elsif type_url.nil? || type_url.empty?
						return
					end
					
					if request.error_detail
						Console.warn(self, "Received xDS NACK.", type_url: type_url, error_detail: request.error_detail)
						return
					end
					
					names = Set.new(request.resource_names)
					if @subscriptions[type_url] != names
						@subscriptions[type_url] = names
						@versions.delete(type_url)
					end
					
					@queue << type_url
				end
				
				# Schedule a resource type for delivery after it changes.
				# @parameter type_url [String] The changed xDS resource type URL.
				def changed(type_url)
					return if @resource_type && type_url != @resource_type
					return unless @subscriptions.key?(type_url)
					
					@queue << type_url unless @closed
				end
				
				# Deliver scheduled resource updates until the stream closes.
				# @asynchronous
				def run
					until @closed
						type_url = @queue.dequeue
						flush(type_url)
					end
				end
				
				# Deliver the latest resource version for a subscribed type.
				# @parameter type_url [String] The xDS resource type URL.
				def flush(type_url)
					names = @subscriptions[type_url]
					return unless names
					
					version = @control_plane.version(type_url)
					return if @versions[type_url] == version
					
					response = @control_plane.response(type_url, names)
					@output.write(response)
					@versions[type_url] = version
				end
				
				# Close the stream and stop waiting for changes.
				def close
					@closed = true
					@queue.close
				end
			end
		end
	end
end
