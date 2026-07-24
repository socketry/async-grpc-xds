# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/control_plane"
require "async/grpc/xds/client"
require "async/grpc/xds/resource_builder"
require "async/grpc/xds/server"
require "async/http/endpoint"
require "sus/fixtures/async"
require "socket"

describe Async::GRPC::XDS::ControlPlane do
	include Sus::Fixtures::Async::ReactorContext
	
	let(:control_plane) {subject.new}
	
	it "publishes cluster resources" do
		control_plane.update_cluster("myservice")
		
		response = control_plane.response(
			Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE,
			["myservice"]
		)
		
		expect(response.version_info).to be == "1"
		expect(response.resources.size).to be == 1
		expect(response.resources.first.type_url).to be == Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE
	end
	
	it "publishes endpoint resources" do
		control_plane.update_endpoints(
			"myservice",
			[
				{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true},
				{addresses: [{address: "127.0.0.2", port: 50052}], healthy: false}
			]
		)
		
		response = control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			["myservice"]
		)
		
		expect(response.version_info).to be == "1"
		expect(response.resources.size).to be == 1
		expect(response.resources.first.type_url).to be == Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE
	end
	
	it "increments resource versions" do
		control_plane.update_endpoints("myservice", [{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}])
		control_plane.update_endpoints("myservice", [{addresses: [{address: "127.0.0.2", port: 50052}], healthy: true}])
		
		expect(control_plane.version(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)).to be == "2"
	end
	
	it "serves resources over ADS" do
		control_plane.update_cluster("myservice")
		control_plane.update_endpoints("myservice", [{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}])
		
		port = available_port
		endpoint = Async::HTTP::Endpoint.parse(
			"http://127.0.0.1:#{port}",
			protocol: Async::HTTP::Protocol::HTTP2
		)
		server = Async::GRPC::XDS::Server.new(control_plane)
		server_task = Async{server.run(endpoint)}
		
		client = Async::GRPC::XDS::Client.new("myservice", bootstrap: {
			xds_servers: [
				{
					server_uri: "127.0.0.1:#{port}",
					channel_creds: [{type: "insecure"}]
				}
			],
			node: {id: "test-#{Process.pid}", cluster: "test"}
		})
		
		endpoints = client.resolve_endpoints
		
		expect(endpoints.map(&:authority)).to be == ["127.0.0.1:50051"]
	ensure
		client&.close
		server_task&.stop
	end
	
	def available_port
		server = TCPServer.new("127.0.0.1", 0)
		server.addr[1]
	ensure
		server&.close
	end
end
