# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/endpoint"

describe Async::GRPC::XDS::Endpoint do
	it "builds endpoint assignments from hashes" do
		assignment = subject.build(
			"myservice",
			[
				{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true},
				{addresses: [{address: "127.0.0.2", port: 50052}], healthy: false}
			]
		)
		
		expect(assignment.cluster_name).to be == "myservice"
		
		endpoints = assignment.endpoints.first.lb_endpoints
		expect(endpoints.size).to be == 2
		
		first = endpoints.first
		expect(first.endpoint.address.socket_address.address).to be == "127.0.0.1"
		expect(first.endpoint.address.socket_address.port_value).to be == 50051
		expect(first.health_status).to be == :HEALTHY
		
		second = endpoints.last
		expect(second.endpoint.address.socket_address.address).to be == "127.0.0.2"
		expect(second.endpoint.address.socket_address.port_value).to be == 50052
		expect(second.health_status).to be == :UNHEALTHY
	end
	
	it "builds grouped IP and Unix endpoint addresses" do
		assignment = subject.build("myservice", [{
			addresses: [
				{path: "/tmp/falcon.ipc"},
				{address: "127.0.0.1", port: 9292},
			],
			healthy: true,
		}])
		endpoint = assignment.endpoints.first.lb_endpoints.first.endpoint
		
		expect(endpoint.address.pipe.path).to be == "/tmp/falcon.ipc"
		expect(endpoint.additional_addresses.size).to be == 1
		expect(endpoint.additional_addresses.first.address.socket_address.address).to be == "127.0.0.1"
		expect(endpoint.additional_addresses.first.address.socket_address.port_value).to be == 9292
	end
	
	it "assigns a hostname to an endpoint" do
		assignment = subject.build("myservice", [{
			addresses: [{address: "127.0.0.1", port: 9292}],
			healthy: true,
			hostname: "worker-1",
		}])
		endpoint = assignment.endpoints.first.lb_endpoints.first.endpoint
		
		expect(endpoint.hostname).to be == "worker-1"
	end
	
	it "rejects endpoints without addresses" do
		expect do
			subject.build("myservice", [{addresses: [], healthy: true}])
		end.to raise_exception(ArgumentError)
	end
	
	it "maps health status values" do
		assignment = subject.build("myservice", [
			{addresses: [{address: "127.0.0.1", port: 1}], healthy: :healthy},
			{addresses: [{address: "127.0.0.1", port: 2}], healthy: :unhealthy},
			{addresses: [{address: "127.0.0.1", port: 3}], healthy: :degraded},
			{addresses: [{address: "127.0.0.1", port: 4}], healthy: :other},
		])
		statuses = assignment.endpoints.first.lb_endpoints.map(&:health_status)
		
		expect(statuses).to be == [:HEALTHY, :UNHEALTHY, :DEGRADED, :UNKNOWN]
	end
end
