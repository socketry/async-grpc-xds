# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/cluster_discovery_service"
require "async/grpc/xds/endpoint_discovery_service"
require "async/grpc/xds/server"
require "async/grpc/xds/service"
require "envoy/config/cluster/v3/cluster_pb"
require "envoy/config/endpoint/v3/endpoint_pb"
require "google/rpc/status_pb"

describe Async::GRPC::XDS::DiscoveryService do
	let(:control_plane) {Async::GRPC::XDS::ControlPlane.new}
	
	def output
		[].tap do |responses|
			responses.define_singleton_method(:write){|response| self << response}
		end
	end
	
	def request(type_url: nil, resource_names: ["myservice"])
		Envoy::Service::Discovery::V3::DiscoveryRequest.new(
			type_url: type_url,
			resource_names: resource_names
		)
	end
	
	def stream_for(resource_type, output)
		subject::Stream.new(control_plane, output, resource_type: resource_type)
	end
	
	it "serves clusters with an explicit resource type" do
		control_plane.update_cluster("myservice")
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE, responses)
		
		stream.request(request(type_url: Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE))
		stream.flush(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE)
		
		cluster = Envoy::Config::Cluster::V3::Cluster.decode(responses.first.resources.first.value)
		expect(cluster.name).to be == "myservice"
	ensure
		stream&.close
	end
	
	it "uses the implied endpoint resource type when omitted" do
		control_plane.update_endpoints("myservice", [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}
		])
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		
		stream.request(request)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		assignment = Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(responses.first.resources.first.value)
		expect(assignment.cluster_name).to be == "myservice"
	ensure
		stream&.close
	end
	
	it "requires a resource type for aggregated streams" do
		responses = output
		stream = subject::Stream.new(control_plane, responses)
		
		stream.request(request)
		
		expect(responses).to be(:empty?)
	ensure
		stream&.close
	end
	
	it "subscribes to every resource when no names are specified" do
		control_plane.update_endpoints("myservice", [])
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		
		stream.request(request(resource_names: []))
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		expect(responses.first.resources.size).to be == 1
	ensure
		stream&.close
	end
	
	it "logs and ignores a NACK" do
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, output)
		nack = request
		nack.error_detail = Google::Rpc::Status.new(message: "invalid resource")
		
		stream.request(nack)
		
		expect(stream).not.to be_nil
	ensure
		stream&.close
	end
	
	it "rejects a resource type that does not belong to the service" do
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, output)
		
		expect do
			stream.request(request(type_url: Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE))
		end.to raise_exception(Protocol::GRPC::Error)
	ensure
		stream&.close
	end
	
	it "ignores changes for resource types that do not belong to the service" do
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		stream.request(request)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		stream.changed(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		expect(responses.size).to be == 1
	ensure
		stream&.close
	end
	
	it "accepts changes for its resource type" do
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, output)
		
		stream.changed(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		expect(stream).not.to be_nil
	ensure
		stream&.close
	end
	
	it "delivers queued resource changes" do
		control_plane.update_endpoints("myservice", [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}
		])
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		stream.request(request)
		
		responses.define_singleton_method(:write) do |response|
			self << response
			stream.close
		end
		
		stream.run
		
		expect(responses.first.type_url).to be == Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE
	ensure
		stream&.close
	end
	
	it "coordinates endpoint discovery stream tasks" do
		service = Async::GRPC::XDS::EndpointDiscoveryService.new(control_plane)
		input = [request]
		output = Object.new
		events = []
		stream = Object.new
		stream.define_singleton_method(:request){|request| events << [:request, request]}
		stream.define_singleton_method(:run){events << :run}
		stream.define_singleton_method(:close){events << :close}
		
		task = Object.new
		task.define_singleton_method(:async) do |&block|
			block.call
			
			Object.new.tap do |handle|
				handle.define_singleton_method(:wait){events << :wait}
				handle.define_singleton_method(:stop){events << :stop}
			end
		end
		
		mock(subject::Stream) do |stream_mock|
			stream_mock.replace(:new) do |given_control_plane, given_output, resource_type:|
				expect(given_control_plane).to be == control_plane
				expect(given_output).to be == output
				expect(resource_type).to be == Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE
				stream
			end
			
			mock(Async::Task) do |task_mock|
				task_mock.replace(:current){task}
				service.stream_endpoints(input, output, nil)
			end
		end
		
		expect(events).to be == [
			[:request, input.first],
			:run,
			:wait,
			:close,
			:stop,
			:stop,
		]
	end
	
	it "delegates cluster requests to the discovery stream" do
		service = Async::GRPC::XDS::ClusterDiscoveryService.new(control_plane)
		input = Object.new
		output = Object.new
		arguments = nil
		service.define_singleton_method(:stream_resources) do |*given|
			arguments = given
		end
		
		service.stream_clusters(input, output, nil)
		
		expect(arguments).to be == [input, output]
	end
	
	it "delegates aggregated requests to the discovery stream" do
		service = Async::GRPC::XDS::Service.new(control_plane)
		input = Object.new
		output = Object.new
		arguments = nil
		service.define_singleton_method(:stream_resources) do |*given|
			arguments = given
		end
		
		service.stream_aggregated_resources(input, output, nil)
		
		expect(arguments).to be == [input, output]
	end
	
	it "configures a server with dedicated cluster and endpoint services" do
		server = Async::GRPC::XDS::Server.new(
			control_plane,
			services: [
				Async::GRPC::XDS::ClusterDiscoveryService,
				Async::GRPC::XDS::EndpointDiscoveryService,
			]
		)
		
		expect(server.services.map(&:service_name)).to be == [
			"envoy.service.cluster.v3.ClusterDiscoveryService",
			"envoy.service.endpoint.v3.EndpointDiscoveryService",
		]
	end
	
	it "runs the configured HTTP server" do
		http_server = Object.new
		http_server.define_singleton_method(:run){:result}
		server = Async::GRPC::XDS::Server.new(control_plane, timeout: 1)
		
		mock(Async::HTTP::Server) do |mock|
			mock.replace(:new) do |dispatcher, endpoint, **options|
				expect(dispatcher).to be == server.dispatcher
				expect(endpoint).to be == :endpoint
				expect(options).to be == {timeout: 1, reuse_port: true}
				http_server
			end
		end
		
		expect(server.run(:endpoint, reuse_port: true)).to be == :result
	end
	
	it "rejects delta discovery" do
		service = Async::GRPC::XDS::EndpointDiscoveryService.new(control_plane)
		
		expect do
			service.delta_endpoints(nil, nil, nil)
		end.to raise_exception(Protocol::GRPC::Error)
		
		cluster_service = Async::GRPC::XDS::ClusterDiscoveryService.new(control_plane)
		expect do
			cluster_service.delta_clusters(nil, nil, nil)
		end.to raise_exception(Protocol::GRPC::Error)
		
		aggregated_service = Async::GRPC::XDS::Service.new(control_plane)
		expect do
			aggregated_service.delta_aggregated_resources(nil, nil, nil)
		end.to raise_exception(Protocol::GRPC::Error)
	end
end
