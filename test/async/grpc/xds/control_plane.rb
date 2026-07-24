# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/control_plane"

describe Async::GRPC::XDS::ControlPlane do
	let(:control_plane) {subject.new(identifier: "test-control-plane")}
	
	it "publishes cluster resources" do
		control_plane.update_cluster("myservice")
		
		response = control_plane.response(
			Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE,
			["myservice"]
		)
		
		expect(response.version_info).to be == "1"
		expect(response.resources.size).to be == 1
		expect(response.resources.first.type_url).to be == Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE
		expect(response.control_plane.identifier).to be == "test-control-plane"
	end
	
	it "publishes endpoint resources" do
		control_plane.update_endpoints("myservice", [{addresses: [{address: "127.0.0.1", port: 50051}]}])
		
		response = control_plane.response(
			Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE,
			["myservice"]
		)
		
		expect(response.version_info).to be == "1"
		expect(response.resources.size).to be == 1
		expect(response.resources.first.type_url).to be == Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE
	end
	
	it "filters response resources by name" do
		control_plane.update_cluster("one")
		control_plane.update_cluster("two")
		
		response = control_plane.response(
			Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE,
			["two"]
		)
		
		expect(response.resources.size).to be == 1
		
		cluster = Envoy::Config::Cluster::V3::Cluster.decode(response.resources.first.value)
		expect(cluster.name).to be == "two"
	end
	
	it "tracks resource names" do
		control_plane.update_cluster("one")
		control_plane.update_cluster("two")
		
		expect(control_plane.resource_names(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE).sort).to be == ["one", "two"]
	end
	
	it "increments versions when resources change" do
		control_plane.update_endpoints("myservice", [{addresses: [{address: "127.0.0.1", port: 50051}]}])
		control_plane.update_endpoints("myservice", [{addresses: [{address: "127.0.0.2", port: 50052}]}])
		
		expect(control_plane.version(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)).to be == "2"
	end
	
	it "increments versions when existing resources are removed" do
		control_plane.update_cluster("myservice")
		control_plane.remove_cluster("myservice")
		
		expect(control_plane.version(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE)).to be == "2"
		expect(control_plane.resources(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE)).to be(:empty?)
	end
	
	it "does not increment versions when missing resources are removed" do
		control_plane.remove_cluster("missing")
		
		expect(control_plane.version(Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE)).to be == "0"
	end
	
	it "removes endpoint resources" do
		control_plane.update_endpoints("myservice", [{addresses: [{address: "127.0.0.1", port: 50051}]}])
		control_plane.remove_endpoints("myservice")
		
		expect(control_plane.resources(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)).to be(:empty?)
		expect(control_plane.version(Async::GRPC::XDS::ControlPlane::ENDPOINT_TYPE)).to be == "2"
	end
	
	it "notifies registered streams about changes" do
		changed = []
		stream = Object.new
		stream.define_singleton_method(:changed){|type_url| changed << type_url}
		
		control_plane.register_stream(stream)
		control_plane.update_cluster("myservice")
		control_plane.remove_stream(stream)
		control_plane.update_cluster("other")
		
		expect(changed).to be == [Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE]
	end
	
	it "continues notifying streams when one stream fails" do
		changed = []
		failing_stream = Object.new
		working_stream = Object.new
		
		failing_stream.define_singleton_method(:changed){|_type_url| raise "failed"}
		working_stream.define_singleton_method(:changed){|type_url| changed << type_url}
		
		control_plane.register_stream(failing_stream)
		control_plane.register_stream(working_stream)
		
		mock(Console) do |mock|
			mock.wrap(:warn) do
				nil
			end
			
			control_plane.update_cluster("myservice")
		end
		
		expect(changed).to be == [Async::GRPC::XDS::ControlPlane::CLUSTER_TYPE]
	end
end
