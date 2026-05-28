# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

def ignore_paths
	super + [
		"lib/async/grpc/xds/ads_stream.rb",
		"lib/async/grpc/xds/client.rb",
		"lib/async/grpc/xds/context.rb",
		"lib/async/grpc/xds/discovery_client.rb",
		"lib/envoy/",
		"lib/google/",
		"lib/udpa/",
		"lib/validate/",
		"lib/xds/",
	]
end
