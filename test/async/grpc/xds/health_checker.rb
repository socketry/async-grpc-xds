# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/health_checker"
require "async/http/endpoint"
require "protocol/http/response"
require "sus/fixtures/async/http"

describe Async::GRPC::XDS::HealthChecker do
	let(:endpoint) {Async::HTTP::Endpoint.parse("http://127.0.0.1:50051", protocol: Async::HTTP::Protocol::HTTP2)}
	
	it "returns unknown without a health check" do
		health_checker = subject.new([])
		
		expect(health_checker.check(endpoint)).to be == :unknown
	end
	
	it "caches health check results" do
		health_checker = subject.new([{type: :gRPC}])
		
		expect(health_checker.check(endpoint)).to be == :unknown
		expect(health_checker.check(endpoint)).to be == :unknown
	end
	
	it "clears removed endpoint cache entries" do
		health_checker = subject.new([{type: :gRPC}])
		health_checker.update_endpoints([endpoint])
		health_checker.check(endpoint)
		
		health_checker.update_endpoints([])
		
		expect(health_checker.instance_variable_get(:@cache)).to be(:empty?)
	end
	
	it "returns unknown for unsupported health check types" do
		health_checker = subject.new([{type: :TCP}])
		
		expect(health_checker.check(endpoint)).to be == :unknown
	end
	
	it "marks failed HTTP health checks as unhealthy" do
		health_checker = subject.new([{type: :HTTP, path: "/ready"}])
		
		mock(Console) do |mock|
			mock.wrap(:warn) do
				nil
			end
			
			expect(health_checker.check(endpoint)).to be == :unhealthy
		end
	end
	
	it "clears cached checks when closed" do
		health_checker = subject.new([{type: :gRPC}])
		health_checker.check(endpoint)
		
		health_checker.close
		
		expect(health_checker.instance_variable_get(:@cache)).to be(:empty?)
	end
end

describe Async::GRPC::XDS::HealthChecker do
	include Sus::Fixtures::Async::HTTP::ServerContext
	
	let(:protocol) {Async::HTTP::Protocol::HTTP2}
	let(:app) do
		Protocol::HTTP::Middleware.for do |request|
			case request.path
			when "/ready"
				Protocol::HTTP::Response[200, {}, ["OK"]]
			else
				Protocol::HTTP::Response[404, {}, ["Not Found"]]
			end
		end
	end
	let(:health_checker) {Async::GRPC::XDS::HealthChecker.new([{type: :HTTP, path: "/ready"}])}
	
	it "checks HTTP health against a real async HTTP server" do
		expect(health_checker.check(client_endpoint)).to be == :healthy
	end
	
	it "marks non-success HTTP health responses as unhealthy" do
		health_checker = Async::GRPC::XDS::HealthChecker.new([{type: :HTTP, path: "/missing"}])
		
		expect(health_checker.check(client_endpoint)).to be == :unhealthy
	end
end
