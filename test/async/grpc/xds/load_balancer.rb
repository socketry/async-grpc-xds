# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/load_balancer"
require "async/http/endpoint"

describe Async::GRPC::XDS::LoadBalancer do
	let(:endpoint1) {Async::HTTP::Endpoint.parse("http://127.0.0.1:50051", protocol: Async::HTTP::Protocol::HTTP2)}
	let(:endpoint2) {Async::HTTP::Endpoint.parse("http://127.0.0.2:50052", protocol: Async::HTTP::Protocol::HTTP2)}
	let(:endpoint3) {Async::HTTP::Endpoint.parse("http://127.0.0.3:50053", protocol: Async::HTTP::Protocol::HTTP2)}
	
	def cluster(policy, health_checks: [])
		Struct.new(:load_balancer_policy, :health_checks).new(policy, health_checks)
	end
	
	it "picks healthy endpoints using round robin" do
		load_balancer = subject.new(cluster(:ROUND_ROBIN), [endpoint1, endpoint2])
		
		expect(load_balancer.pick).to be == endpoint2
		expect(load_balancer.pick).to be == endpoint1
		expect(load_balancer.pick).to be == endpoint2
	ensure
		load_balancer&.close
	end
	
	it "picks least requested endpoints" do
		load_balancer = subject.new(cluster(:LEAST_REQUEST), [endpoint1, endpoint2])
		
		load_balancer.record_request_start(endpoint1)
		
		expect(load_balancer.pick).to be == endpoint2
		
		load_balancer.record_request_end(endpoint1)
		expect(load_balancer.pick).to be == endpoint1
	ensure
		load_balancer&.close
	end
	
	it "removes endpoint state when endpoints update" do
		load_balancer = subject.new(cluster(:LEAST_REQUEST), [endpoint1, endpoint2])
		
		load_balancer.record_request_start(endpoint1)
		load_balancer.mark_unhealthy(endpoint2)
		load_balancer.update_endpoints([endpoint2, endpoint3])
		
		expect(load_balancer.healthy_endpoints).to be == [endpoint3]
		expect(load_balancer.pick).to be == endpoint3
	ensure
		load_balancer&.close
	end
	
	it "does not pick unhealthy endpoints" do
		load_balancer = subject.new(cluster(:ROUND_ROBIN), [endpoint1, endpoint2])
		
		load_balancer.mark_unhealthy(endpoint2)
		
		expect(load_balancer.healthy_endpoints).to be == [endpoint1]
		expect(load_balancer.pick).to be == endpoint1
	ensure
		load_balancer&.close
	end
	
	it "returns nil when no healthy endpoints are available" do
		load_balancer = subject.new(cluster(:ROUND_ROBIN), [endpoint1])
		
		load_balancer.mark_unhealthy(endpoint1)
		
		expect(load_balancer.pick).to be == nil
	ensure
		load_balancer&.close
	end
	
	it "safely ignores nil request completions" do
		load_balancer = subject.new(cluster(:LEAST_REQUEST), [endpoint1])
		
		load_balancer.record_request_end(nil)
		
		expect(load_balancer.pick).to be == endpoint1
	ensure
		load_balancer&.close
	end
	
	it "picks random endpoints" do
		load_balancer = subject.new(cluster(:RANDOM), [endpoint1])
		
		expect(load_balancer.pick).to be == endpoint1
	ensure
		load_balancer&.close
	end
	
	it "falls back to round robin for ring hash endpoints" do
		load_balancer = subject.new(cluster(:RING_HASH), [endpoint1, endpoint2])
		
		expect(load_balancer.pick).to be == endpoint2
	ensure
		load_balancer&.close
	end
	
	it "falls back to round robin for maglev endpoints" do
		load_balancer = subject.new(cluster(:MAGLEV), [endpoint1, endpoint2])
		
		expect(load_balancer.pick).to be == endpoint2
	ensure
		load_balancer&.close
	end
	
	it "defaults unknown policies to round robin" do
		load_balancer = subject.new(cluster(:UNKNOWN), [endpoint1, endpoint2])
		
		expect(load_balancer.pick).to be == endpoint2
	ensure
		load_balancer&.close
	end
	
	it "falls back to the first healthy endpoint for unknown internal policies" do
		load_balancer = subject.new(cluster(:ROUND_ROBIN), [endpoint1, endpoint2])
		load_balancer.instance_variable_set(:@policy, :unknown)
		
		expect(load_balancer.pick).to be == endpoint1
	ensure
		load_balancer&.close
	end
	
	it "starts and stops health checks when configured" do
		load_balancer = nil
		
		Async do |task|
			load_balancer = subject.new(cluster(:ROUND_ROBIN, health_checks: [{type: :gRPC, interval: 60}]), [endpoint1])
			
			task.yield
			
			expect(load_balancer.instance_variable_get(:@health_check_task)).not.to be == nil
		ensure
			load_balancer&.close
			expect(load_balancer.instance_variable_get(:@health_check_task)).to be == nil if load_balancer
		end
	end
end
