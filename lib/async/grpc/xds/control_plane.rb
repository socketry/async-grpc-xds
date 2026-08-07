# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "set"
require "securerandom"

require "async/queue"

require "envoy/config/core/v3/base_pb"
require "envoy/service/discovery/v3/discovery_pb"
require "google/protobuf/any_pb"
require "google/protobuf/well_known_types"

require_relative "cluster"
require_relative "endpoint"

module Async
	module GRPC
		module XDS
			# Maintains xDS resource snapshots and notifies discovery streams when resources change.
			class ControlPlane
				CLUSTER_TYPE = Cluster::TYPE_URL
				ENDPOINT_TYPE = Endpoint::TYPE_URL
				
				# Initialize an empty control plane.
				# @parameter identifier [String] The identifier reported in discovery responses.
				def initialize(identifier: "async-grpc-xds")
					@identifier = identifier
					@resources = Hash.new{|hash, type_url| hash[type_url] = {}}
					@versions = Hash.new(0)
					@streams = Set.new.compare_by_identity
					@mutex = Mutex.new
				end
				
				attr :identifier
				
				# Add or replace a cluster resource.
				# @parameter name [String] The cluster name.
				# @parameter resource [Envoy::Config::Cluster::V3::Cluster | Nil] An existing cluster resource, or `nil` to build one from `options`.
				# @parameter options [Hash] Options forwarded to {Cluster.build}.
				def update_cluster(name, resource = nil, **options)
					resource ||= Cluster.build(name, **options)
					update_resource(CLUSTER_TYPE, name.to_s, resource)
				end
				
				# Add or replace the endpoint assignment for a cluster.
				# @parameter cluster_name [String] The cluster name.
				# @parameter endpoints [Array(Hash)] The normalized endpoint states.
				def update_endpoints(cluster_name, endpoints)
					update_resource(
						ENDPOINT_TYPE,
						cluster_name.to_s,
						Endpoint.build(cluster_name, endpoints)
					)
				end
				
				# Remove a cluster resource.
				# @parameter name [String] The cluster name.
				def remove_cluster(name)
					remove_resource(CLUSTER_TYPE, name.to_s)
				end
				
				# Remove the endpoint assignment for a cluster.
				# @parameter cluster_name [String] The cluster name.
				def remove_endpoints(cluster_name)
					remove_resource(ENDPOINT_TYPE, cluster_name.to_s)
				end
				
				# Add or replace an xDS resource and notify subscribed streams.
				# @parameter type_url [String] The xDS resource type URL.
				# @parameter name [String] The resource name.
				# @parameter resource [Google::Protobuf::MessageExts] The protobuf resource.
				def update_resource(type_url, name, resource)
					notify = false
					
					@mutex.synchronize do
						@resources[type_url][name] = resource
						@versions[type_url] += 1
						notify = true
					end
					
					notify_streams(type_url) if notify
				end
				
				# Remove an xDS resource and notify subscribed streams.
				# @parameter type_url [String] The xDS resource type URL.
				# @parameter name [String] The resource name.
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
				
				# Get the available resource names for a type.
				# @parameter type_url [String] The xDS resource type URL.
				# @returns [Array(String)] The resource names.
				def resource_names(type_url)
					@mutex.synchronize do
						@resources[type_url].keys
					end
				end
				
				# Get resources of a given type.
				# @parameter type_url [String] The xDS resource type URL.
				# @parameter names [Array(String) | Nil] The requested resource names, or `nil` for all resources.
				# @returns [Array(Google::Protobuf::MessageExts)] The matching resources.
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
				
				# Get the current version for a resource type.
				# @parameter type_url [String] The xDS resource type URL.
				# @returns [String] The monotonically increasing version.
				def version(type_url)
					@mutex.synchronize do
						@versions[type_url].to_s
					end
				end
				
				# Build a discovery response for a resource type.
				# @parameter type_url [String] The xDS resource type URL.
				# @parameter names [Array(String) | Nil] The requested resource names, or `nil` for all resources.
				# @returns [Envoy::Service::Discovery::V3::DiscoveryResponse] The current discovery response.
				def response(type_url, names = nil)
					resources = self.resources(type_url, names)
					version = self.version(type_url)
					
					Envoy::Service::Discovery::V3::DiscoveryResponse.new(
						version_info: version,
						resources: resources.map{|resource| Google::Protobuf::Any.pack(resource)},
						type_url: type_url,
						nonce: "#{type_url}:#{version}:#{SecureRandom.hex(8)}",
						control_plane: Envoy::Config::Core::V3::ControlPlane.new(identifier: @identifier)
					)
				end
				
				# Register a stream to receive resource-change notifications.
				# @parameter stream [Stream] The stream to register.
				def register_stream(stream)
					@mutex.synchronize do
						@streams.add(stream)
					end
				end
				
				# Remove a registered stream.
				# @parameter stream [Stream] The stream to remove.
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
