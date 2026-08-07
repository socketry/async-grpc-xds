# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/cluster"
require "async/grpc/xds/config_source"
require "async/grpc/xds/http_health_check"

describe Async::GRPC::XDS::Cluster do
	it "builds an EDS cluster resource" do
		cluster = subject.build("myservice", service_name: "backend", connect_timeout: 1.25)
		
		expect(cluster.name).to be == "myservice"
		expect(cluster.type).to be == :EDS
		expect(cluster.eds_cluster_config.service_name).to be == "backend"
		expect(cluster.eds_cluster_config.eds_config.ads).not.to be == nil
		expect(cluster.lb_policy).to be == :ROUND_ROBIN
		expect(cluster.connect_timeout.seconds).to be == 1
		expect(cluster.connect_timeout.nanos).to be == 250_000_000
		expect(cluster.http2_protocol_options).not.to be == nil
	end
	
	it "builds an HTTP/1 EDS cluster resource" do
		cluster = subject.build("myservice", protocol: :http1)
		
		expect(cluster.http2_protocol_options).to be == nil
	end
	
	it "uses a dedicated EDS configuration source" do
		eds_config = Async::GRPC::XDS::ConfigSource.grpc("xds_cluster")
		cluster = subject.build("myservice", eds_config: eds_config)
		api_config_source = cluster.eds_cluster_config.eds_config.api_config_source
		
		expect(api_config_source.api_type).to be == :GRPC
		expect(api_config_source.transport_api_version).to be == :V3
		expect(api_config_source.grpc_services.first.envoy_grpc.cluster_name).to be == "xds_cluster"
	end
	
	it "attaches active health checks" do
		health_check = Async::GRPC::XDS::HTTPHealthCheck.build("/services/ping")
		cluster = subject.build("myservice", health_checks: [health_check])
		
		expect(cluster.health_checks).to be == [health_check]
	end
	
	it "rejects unsupported upstream protocols" do
		expect do
			subject.build("myservice", protocol: :http3)
		end.to raise_exception(ArgumentError)
	end
end
