# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/stream"
require "async/grpc/xds/control_plane"
require "envoy/config/cluster/v3/cluster_pb"
require "envoy/config/endpoint/v3/endpoint_pb"
require "google/rpc/status_pb"

describe Async::GRPC::XDS::Stream do
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
		subject.new(control_plane, output, resource_type: resource_type)
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
		stream = subject.new(control_plane, responses)
		
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
	
	it "does not publish resources before subscribing" do
		control_plane.update_endpoints("myservice", [])
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		
		stream.changed(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		expect(responses).to be(:empty?)
	ensure
		stream&.close
	end
	
	it "replaces subscriptions and responds without a resource change" do
		control_plane.update_endpoints("first", [])
		control_plane.update_endpoints("second", [])
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		
		stream.request(request(resource_names: ["first"]))
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		stream.request(request(resource_names: ["second"]))
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		assignments = responses.map do |response|
			response.resources.map do |resource|
				Envoy::Config::Endpoint::V3::ClusterLoadAssignment.decode(resource.value).cluster_name
			end
		end
		
		expect(assignments).to be == [["first"], ["second"]]
	ensure
		stream&.close
	end
	
	it "does not respond again when an acknowledgement keeps the same subscription" do
		control_plane.update_endpoints("myservice", [])
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		
		stream.request(request)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		stream.request(request)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		expect(responses.size).to be == 1
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
	
	it "publishes resource changes after subscribing" do
		control_plane.update_endpoints("myservice", [])
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		stream.request(request)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		control_plane.update_endpoints("myservice", [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}
		])
		stream.changed(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		
		expect(responses.size).to be == 2
	ensure
		stream&.close
	end
	
	it "ignores resource changes after closing" do
		control_plane.update_endpoints("myservice", [])
		responses = output
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, responses)
		stream.request(request)
		stream.flush(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		stream.close
		
		control_plane.update_endpoints("myservice", [
			{addresses: [{address: "127.0.0.1", port: 50051}], healthy: true}
		])
		stream.changed(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)
		stream.run
		
		expect(responses.size).to be == 1
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
	
	it "unblocks a running stream when closed" do
		stream = stream_for(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE, output)
		finished = false
		
		Sync do |task|
			runner = task.async do
				stream.run
				finished = true
			end
			
			task.yield
			stream.close
			runner.wait
		end
		
		expect(finished).to be == true
	ensure
		stream&.close
	end
end
