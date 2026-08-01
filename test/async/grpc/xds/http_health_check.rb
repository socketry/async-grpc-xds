# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/http_health_check"

describe Async::GRPC::XDS::HTTPHealthCheck do
	it "builds an HTTP active health check" do
		health_check = subject.build(
			"/services/ping",
			interval: 1.5,
			timeout: 0.25,
			unhealthy_threshold: 3,
			healthy_threshold: 2
		)
		
		expect(health_check.http_health_check.path).to be == "/services/ping"
		expect(health_check.interval.seconds).to be == 1
		expect(health_check.interval.nanos).to be == 500_000_000
		expect(health_check.timeout.seconds).to be == 0
		expect(health_check.timeout.nanos).to be == 250_000_000
		expect(health_check.unhealthy_threshold.value).to be == 3
		expect(health_check.healthy_threshold.value).to be == 2
	end
end
