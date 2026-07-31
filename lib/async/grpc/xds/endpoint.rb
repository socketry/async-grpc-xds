# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "envoy/config/core/v3/address_pb"
require "envoy/config/endpoint/v3/endpoint_pb"
require "envoy/config/endpoint/v3/endpoint_components_pb"

module Async
	module GRPC
		module XDS
			# Builds Envoy endpoint resources.
			module Endpoint
				extend self
				
				TYPE_URL = "type.googleapis.com/envoy.config.endpoint.v3.ClusterLoadAssignment"
				
				# Build an EDS cluster load assignment from normalized endpoint state.
				# @parameter cluster_name [String] The cluster name.
				# @parameter endpoints [Array(Hash)] The endpoints, each containing `:addresses` and `:healthy`.
				# @returns [Envoy::Config::Endpoint::V3::ClusterLoadAssignment] The generated endpoint resource.
				def build(cluster_name, endpoints)
					Envoy::Config::Endpoint::V3::ClusterLoadAssignment.new(
						cluster_name: cluster_name.to_s,
						endpoints: [
							Envoy::Config::Endpoint::V3::LocalityLbEndpoints.new(
								lb_endpoints: endpoints.map{|endpoint| load_balancer_endpoint(endpoint)}
							)
						]
					)
				end
				
				private
				
				# Build an Envoy load-balancer endpoint from normalized endpoint state.
				# @parameter endpoint [Hash] The endpoint containing `:addresses` and `:healthy`.
				# @returns [Envoy::Config::Endpoint::V3::LbEndpoint] The generated load-balancer endpoint.
				# @raises [KeyError] If required endpoint state is missing.
				# @raises [ArgumentError] If the endpoint has no addresses.
				# @private
				def load_balancer_endpoint(endpoint)
					addresses, healthy = endpoint.fetch_values(:addresses, :healthy)
					raise ArgumentError, "An endpoint requires at least one address!" if addresses.empty?
					
					address, *additional_addresses = addresses
					
					Envoy::Config::Endpoint::V3::LbEndpoint.new(
						endpoint: Envoy::Config::Endpoint::V3::Endpoint.new(
							address: build_address(address),
							hostname: endpoint[:hostname],
							additional_addresses: additional_addresses.map do |additional_address|
								Envoy::Config::Endpoint::V3::Endpoint::AdditionalAddress.new(
									address: build_address(additional_address)
								)
							end
						),
						health_status: health_status_value(healthy)
					)
				end
				
				# Build an Envoy address from a normalized IP or Unix address.
				# @parameter address [Hash] An IP `:address` and `:port`, or a Unix `:path`.
				# @returns [Envoy::Config::Core::V3::Address] The generated Envoy address.
				# @raises [KeyError] If required IP address state is missing.
				# @private
				def build_address(address)
					if path = address[:path]
						Envoy::Config::Core::V3::Address.new(
							pipe: Envoy::Config::Core::V3::Pipe.new(path: path)
						)
					else
						Envoy::Config::Core::V3::Address.new(
							socket_address: Envoy::Config::Core::V3::SocketAddress.new(
								protocol: Envoy::Config::Core::V3::SocketAddress::Protocol::TCP,
								address: address.fetch(:address),
								port_value: address.fetch(:port)
							)
						)
					end
				end
				
				# Convert an endpoint health status to its Envoy enum value.
				# @parameter healthy [Boolean | Symbol | String] The normalized health status.
				# @returns [Integer] The Envoy health-status enum value.
				# @private
				def health_status_value(healthy)
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
