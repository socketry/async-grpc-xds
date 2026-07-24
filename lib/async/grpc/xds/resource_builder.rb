# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "google/protobuf/any_pb"
require "google/protobuf/duration_pb"

require "envoy/config/cluster/v3/cluster_pb"
require "envoy/config/core/v3/address_pb"
require "envoy/config/core/v3/config_source_pb"
require "envoy/config/core/v3/health_check_pb"
require "envoy/config/core/v3/protocol_pb"
require "envoy/config/endpoint/v3/endpoint_pb"
require "envoy/config/endpoint/v3/endpoint_components_pb"

module Async
	module GRPC
		module XDS
			# Builds Envoy xDS resource protobufs.
			module ResourceBuilder
				TYPE_URL_PREFIX = "type.googleapis.com"
				
				CLUSTER_TYPE = "#{TYPE_URL_PREFIX}/envoy.config.cluster.v3.Cluster"
				ENDPOINT_TYPE = "#{TYPE_URL_PREFIX}/envoy.config.endpoint.v3.ClusterLoadAssignment"
				
				def self.pack(resource)
					Google::Protobuf::Any.new(
						type_url: "#{TYPE_URL_PREFIX}/#{resource.class.descriptor.name}",
						value: resource.to_proto
					)
				end
				
				def self.cluster(name, service_name: name, load_balancer_policy: :round_robin, connect_timeout: 5, protocol: :http2)
					options = {
						name: name.to_s,
						type: Envoy::Config::Cluster::V3::Cluster::DiscoveryType::EDS,
						eds_cluster_config: Envoy::Config::Cluster::V3::Cluster::EdsClusterConfig.new(
							service_name: service_name.to_s,
							eds_config: Envoy::Config::Core::V3::ConfigSource.new(
								ads: Envoy::Config::Core::V3::AggregatedConfigSource.new
							)
						),
						connect_timeout: duration(connect_timeout),
						lb_policy: load_balancer_policy_value(load_balancer_policy),
					}
					
					case protocol
					when :http1, "http1", "http/1.1"
						# Envoy uses HTTP/1 by default.
					when :http2, "http2", "h2"
						options[:http2_protocol_options] = Envoy::Config::Core::V3::Http2ProtocolOptions.new
					else
						raise ArgumentError, "Unsupported upstream protocol: #{protocol.inspect}"
					end
					
					Envoy::Config::Cluster::V3::Cluster.new(**options)
				end
				
				def self.cluster_load_assignment(cluster_name, endpoints)
					Envoy::Config::Endpoint::V3::ClusterLoadAssignment.new(
						cluster_name: cluster_name.to_s,
						endpoints: [
							Envoy::Config::Endpoint::V3::LocalityLbEndpoints.new(
								lb_endpoints: endpoints.map{|endpoint| load_balancer_endpoint(endpoint)}
							)
						]
					)
				end
				
				def self.load_balancer_endpoint(endpoint)
					endpoint = normalize_endpoint(endpoint)
					addresses = endpoint.fetch(:addresses)
					address = addresses.first
					
					Envoy::Config::Endpoint::V3::LbEndpoint.new(
						endpoint: Envoy::Config::Endpoint::V3::Endpoint.new(
							address: build_address(address),
							additional_addresses: addresses.drop(1).map do |additional_address|
								Envoy::Config::Endpoint::V3::Endpoint::AdditionalAddress.new(
									address: build_address(additional_address)
								)
							end,
							hostname: endpoint[:hostname].to_s
						),
						health_status: health_status_value(endpoint.fetch(:healthy, true))
					)
				end
				
				def self.normalize_endpoint(endpoint)
					value = Hash.try_convert(endpoint)
					raise ArgumentError, "Invalid endpoint: #{endpoint.inspect}" unless value
					
					{
						addresses: normalize_addresses(value),
						hostname: value[:hostname] || value["hostname"],
						healthy: value.key?(:healthy) ? value[:healthy] : value.fetch("healthy", true)
					}
				end
				
				def self.normalize_addresses(endpoint)
					addresses = if addresses = endpoint[:addresses] || endpoint["addresses"]
						addresses.map{|address| normalize_address(address)}
					else
						[normalize_address(endpoint)]
					end
					
					raise ArgumentError, "An endpoint requires at least one address!" if addresses.empty?
					
					addresses
				end
				
				def self.normalize_address(address)
					if path = address[:path] || address["path"]
						{path: path}
					else
						{
							address: address.fetch(:address){address.fetch("address")},
							port: address.fetch(:port){address.fetch("port")}.to_i,
						}
					end
				end
				
				def self.build_address(address)
					if path = address[:path]
						Envoy::Config::Core::V3::Address.new(
							pipe: Envoy::Config::Core::V3::Pipe.new(path: path)
						)
					else
						Envoy::Config::Core::V3::Address.new(
							socket_address: Envoy::Config::Core::V3::SocketAddress.new(
								protocol: Envoy::Config::Core::V3::SocketAddress::Protocol::TCP,
								address: address[:address],
								port_value: address[:port]
							)
						)
					end
				end
				
				private_class_method :normalize_addresses, :normalize_address, :build_address
				
				def self.duration(seconds)
					whole_seconds = seconds.to_i
					nanos = ((seconds.to_f - whole_seconds) * 1_000_000_000).to_i
					
					Google::Protobuf::Duration.new(seconds: whole_seconds, nanos: nanos)
				end
				
				def self.load_balancer_policy_value(load_balancer_policy)
					case load_balancer_policy
					when :round_robin, :ROUND_ROBIN, "round_robin", "ROUND_ROBIN"
						Envoy::Config::Cluster::V3::Cluster::LbPolicy::ROUND_ROBIN
					when :least_request, :LEAST_REQUEST, "least_request", "LEAST_REQUEST"
						Envoy::Config::Cluster::V3::Cluster::LbPolicy::LEAST_REQUEST
					when :random, :RANDOM, "random", "RANDOM"
						Envoy::Config::Cluster::V3::Cluster::LbPolicy::RANDOM
					else
						load_balancer_policy
					end
				end
				
				def self.health_status_value(healthy)
					case healthy
					when :healthy, :HEALTHY, "healthy", "HEALTHY", true
						Envoy::Config::Core::V3::HealthStatus::HEALTHY
					when :unhealthy, :UNHEALTHY, "unhealthy", "UNHEALTHY", false
						Envoy::Config::Core::V3::HealthStatus::UNHEALTHY
					when :degraded, :DEGRADED, "degraded", "DEGRADED"
						Envoy::Config::Core::V3::HealthStatus::DEGRADED
					else
						Envoy::Config::Core::V3::HealthStatus::UNKNOWN
					end
				end
			end
		end
	end
end
