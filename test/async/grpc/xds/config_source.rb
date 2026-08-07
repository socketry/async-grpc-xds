# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/config_source"

describe Async::GRPC::XDS::ConfigSource do
	it "builds an ADS configuration source" do
		config_source = subject.ads
		
		expect(config_source.ads).not.to be_nil
	end
	
	it "builds a dedicated gRPC configuration source" do
		config_source = subject.grpc(:xds_cluster)
		api_config_source = config_source.api_config_source
		
		expect(config_source.resource_api_version).to be == :V3
		expect(api_config_source.api_type).to be == :GRPC
		expect(api_config_source.transport_api_version).to be == :V3
		expect(api_config_source.grpc_services.first.envoy_grpc.cluster_name).to be == "xds_cluster"
	end
end
