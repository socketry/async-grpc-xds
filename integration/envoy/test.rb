# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/cluster_discovery_service"
require "async/grpc/xds/config_source"
require "async/grpc/xds/control_plane"
require "async/grpc/xds/endpoint_discovery_service"
require "async/grpc/xds/server"
require "async/http/endpoint"
require "async/http/internet"
require "async/http/server"
require "json"
require "protocol/http/response"
require "sus/fixtures/async"

describe "dedicated discovery services with Envoy" do
	include Sus::Fixtures::Async::ReactorContext
	
	let(:admin_uri) {ENV["ENVOY_ADMIN_URI"]}
	let(:bind_uri) {ENV["XDS_BIND"] || "http://0.0.0.0:18000"}
	let(:readiness_uri) {ENV["READINESS_BIND"] || "http://0.0.0.0:18001"}
	let(:cluster_name) {"application"}
	let(:internet) {Async::HTTP::Internet.new}
	
	def get_admin(path)
		response = internet.get("#{admin_uri}#{path}")
		raise "Envoy admin request failed: #{response.status}" unless response.success?
		
		JSON.parse(response.read)
	ensure
		response&.close
	end
	
	def eventually(timeout: 15, interval: 0.1)
		deadline = Time.now + timeout
		last_error = nil
		
		while Time.now < deadline
			begin
				if result = yield
					return result
				end
			rescue => error
				last_error = error
			end
			
			sleep(interval)
		end
		
		raise last_error if last_error
		raise "Timed out waiting for condition"
	end
	
	def cluster_status
		get_admin("/clusters?format=json").fetch("cluster_statuses").find do |status|
			status["name"] == cluster_name
		end
	end
	
	def addresses(status)
		status.fetch("host_statuses", []).map do |host|
			socket_address = host.fetch("address").fetch("socket_address")
			[socket_address.fetch("address"), socket_address.fetch("port_value")]
		end
	end
	
	def stats
		get_admin("/stats?format=json").fetch("stats").filter_map do |stat|
			[stat.fetch("name"), stat.fetch("value")] if stat.key?("name")
		end.to_h
	end
	
	it "applies CDS and EDS updates from the Ruby control plane" do
		skip "Requires Envoy (ENVOY_ADMIN_URI)" unless admin_uri
		
		control_plane = Async::GRPC::XDS::ControlPlane.new
		control_plane.update_cluster(
			cluster_name,
			eds_config: Async::GRPC::XDS::ConfigSource.grpc("xds_cluster"),
			protocol: :http1
		)
		control_plane.update_endpoints(cluster_name, [
			{addresses: [{address: "192.0.2.1", port: 8001}], healthy: true}
		])
		
		server = Async::GRPC::XDS::Server.new(
			control_plane,
			services: [
				Async::GRPC::XDS::ClusterDiscoveryService,
				Async::GRPC::XDS::EndpointDiscoveryService
			]
		)
		endpoint = Async::HTTP::Endpoint.parse(
			bind_uri,
			protocol: Async::HTTP::Protocol::HTTP2
		)
		server_task = Async{server.run(endpoint)}
		readiness_endpoint = Async::HTTP::Endpoint.parse(readiness_uri)
		readiness_server = Async::HTTP::Server.new(
			->(_request){Protocol::HTTP::Response[200, {}, []]},
			readiness_endpoint
		)
		readiness_task = Async{readiness_server.run}
		
		status = eventually do
			status = cluster_status
			status if status && addresses(status) == [["192.0.2.1", 8001]]
		end
		
		expect(status["added_via_api"]).to be == true
		
		control_plane.update_endpoints(cluster_name, [
			{addresses: [{address: "192.0.2.2", port: 8002}], healthy: true}
		])
		
		status = eventually do
			status = cluster_status
			status if status && addresses(status) == [["192.0.2.2", 8002]]
		end
		
		expect(addresses(status)).to be == [["192.0.2.2", 8002]]
		
		stats = self.stats
		expect(stats.fetch("cluster_manager.cds.update_success")).to be >= 1
		expect(stats.fetch("cluster_manager.cds.update_rejected")).to be == 0
		expect(stats.fetch("cluster.#{cluster_name}.update_success")).to be >= 2
		expect(stats.fetch("cluster.#{cluster_name}.update_rejected")).to be == 0
	ensure
		internet.close
		readiness_task&.stop
		server_task&.stop
	end
end
