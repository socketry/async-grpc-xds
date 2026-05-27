# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "async/queue"
require "async/grpc/service"
require "protocol/grpc/error"
require "protocol/grpc/status"
require "set"

require "envoy/service/discovery/v3/aggregated_discovery_service"

require_relative "control_plane"

module Async
	module GRPC
		module XDS
			# Serves Envoy Aggregated Discovery Service requests from a {ControlPlane}.
			class Service < Async::GRPC::Service
				SERVICE_NAME = "envoy.service.discovery.v3.AggregatedDiscoveryService"
				
				def initialize(control_plane)
					super(Envoy::Service::Discovery::V3::AggregatedDiscoveryService, SERVICE_NAME)
					@control_plane = control_plane
				end
				
				def stream_aggregated_resources(input, output, call)
					stream = Stream.new(@control_plane, output)
					@control_plane.register_stream(stream)
					
					reader = Async do
						input.each do |request|
							stream.request(request)
						end
					end
					
					writer = Async do
						stream.run
					end
					
					reader.wait
				ensure
					stream&.close
					reader&.stop
					writer&.stop
					@control_plane.remove_stream(stream) if stream
				end
				
				def delta_aggregated_resources(input, output, call)
					raise Protocol::GRPC::Error.new(
						Protocol::GRPC::Status::UNIMPLEMENTED,
						"Delta xDS is not implemented."
					)
				end
				
				# Represents one ADS stream and its subscribed resources.
				class Stream
					def initialize(control_plane, output)
						@control_plane = control_plane
						@output = output
						@subscriptions = Hash.new{|hash, type_url| hash[type_url] = Set.new}
						@versions = {}
						@queue = Async::Queue.new
						@closed = false
					end
					
					def request(request)
						return if request.type_url.nil? || request.type_url.empty?
						
						if request.error_detail
							Console.warn(self, "Received xDS NACK.", type_url: request.type_url, error_detail: request.error_detail)
							return
						end
						
						if request.resource_names.any?
							@subscriptions[request.type_url].merge(request.resource_names)
						else
							@subscriptions[request.type_url]
						end
						
						@queue << request.type_url
					end
					
					def changed(type_url)
						@queue << type_url unless @closed
					end
					
					def run
						until @closed
							type_url = @queue.dequeue
							flush(type_url)
						end
					end
					
					def flush(type_url)
						names = @subscriptions[type_url]
						return unless names
						
						version = @control_plane.version(type_url)
						return if @versions[type_url] == version
						
						response = @control_plane.response(type_url, names)
						@output.write(response)
						@versions[type_url] = version
					end
					
					def close
						@closed = true
						@queue.close
					end
				end
			end
		end
	end
end
