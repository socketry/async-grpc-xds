# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "set"
require "securerandom"

require "async/queue"

require "envoy/config/core/v3/base_pb"
require "envoy/service/discovery/v3/discovery_pb"

require_relative "resource_builder"

module Async
	module GRPC
		module XDS
			# Maintains xDS resource snapshots and notifies ADS streams when resources change.
			class ControlPlane
				CLUSTER_TYPE = ResourceBuilder::CLUSTER_TYPE
				ENDPOINT_TYPE = ResourceBuilder::ENDPOINT_TYPE
				
				def initialize(identifier: "async-grpc-xds")
					@identifier = identifier
					@resources = Hash.new{|hash, type_url| hash[type_url] = {}}
					@versions = Hash.new(0)
					@streams = Set.new.compare_by_identity
					@mutex = Mutex.new
				end
				
				attr :identifier
				
				def update_cluster(name, resource = nil, **options)
					resource ||= ResourceBuilder.cluster(name, **options)
					update_resource(CLUSTER_TYPE, name.to_s, resource)
				end
				
				def update_endpoints(cluster_name, endpoints)
					update_resource(
						ENDPOINT_TYPE,
						cluster_name.to_s,
						ResourceBuilder.cluster_load_assignment(cluster_name, endpoints)
					)
				end
				
				def remove_cluster(name)
					remove_resource(CLUSTER_TYPE, name.to_s)
				end
				
				def remove_endpoints(cluster_name)
					remove_resource(ENDPOINT_TYPE, cluster_name.to_s)
				end
				
				def update_resource(type_url, name, resource)
					notify = false
					
					@mutex.synchronize do
						@resources[type_url][name] = resource
						@versions[type_url] += 1
						notify = true
					end
					
					notify_streams(type_url) if notify
				end
				
				def remove_resource(type_url, name)
					notify = false
					
					@mutex.synchronize do
						if @resources[type_url].delete(name)
							@versions[type_url] += 1
							notify = true
						end
					end
					
					notify_streams(type_url) if notify
				end
				
				def resource_names(type_url)
					@mutex.synchronize do
						@resources[type_url].keys
					end
				end
				
				def resources(type_url, names = nil)
					@mutex.synchronize do
						resources = @resources[type_url]
						
						if names && names.any?
							names.filter_map{|name| resources[name]}
						else
							resources.values
						end
					end
				end
				
				def version(type_url)
					@mutex.synchronize do
						@versions[type_url].to_s
					end
				end
				
				def response(type_url, names = nil)
					resources = self.resources(type_url, names)
					version = self.version(type_url)
					
					Envoy::Service::Discovery::V3::DiscoveryResponse.new(
						version_info: version,
						resources: resources.map{|resource| ResourceBuilder.pack(resource)},
						type_url: type_url,
						nonce: "#{type_url}:#{version}:#{SecureRandom.hex(8)}",
						control_plane: Envoy::Config::Core::V3::ControlPlane.new(identifier: @identifier)
					)
				end
				
				def register_stream(stream)
					@mutex.synchronize do
						@streams.add(stream)
					end
				end
				
				def remove_stream(stream)
					@mutex.synchronize do
						@streams.delete(stream)
					end
				end
				
				private
				
				def notify_streams(type_url)
					streams = @mutex.synchronize{@streams.to_a}
					
					streams.each do |stream|
						stream.changed(type_url)
					rescue => error
						Console.warn(self, "Failed to notify xDS stream.", stream: stream, exception: error)
					end
				end
			end
		end
	end
end
