# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "google/protobuf/duration_pb"
require "google/protobuf/wrappers_pb"

require "envoy/config/core/v3/health_check_pb"

module Async
	module GRPC
		module XDS
			# Builds Envoy HTTP active health checks.
			module HTTPHealthCheck
				extend self
				
				# Build an HTTP active health check.
				# @parameter path [String] The request path used to check each endpoint.
				# @parameter interval [Numeric] The interval between checks in seconds.
				# @parameter timeout [Numeric] The check timeout in seconds.
				# @parameter unhealthy_threshold [Integer] The consecutive failures required to mark an endpoint unhealthy.
				# @parameter healthy_threshold [Integer] The consecutive successes required to mark an endpoint healthy.
				# @returns [Envoy::Config::Core::V3::HealthCheck] The generated health check.
				def build(path, interval: 1, timeout: 1, unhealthy_threshold: 2, healthy_threshold: 1)
					Envoy::Config::Core::V3::HealthCheck.new(
						timeout: duration(timeout),
						interval: duration(interval),
						unhealthy_threshold: Google::Protobuf::UInt32Value.new(value: Integer(unhealthy_threshold)),
						healthy_threshold: Google::Protobuf::UInt32Value.new(value: Integer(healthy_threshold)),
						http_health_check: Envoy::Config::Core::V3::HealthCheck::HttpHealthCheck.new(path: path.to_s)
					)
				end
				
				private
				
				def duration(value)
					seconds = value.to_i
					
					Google::Protobuf::Duration.new(
						seconds: seconds,
						nanos: ((value.to_f - seconds) * 1_000_000_000).to_i
					)
				end
			end
		end
	end
end
