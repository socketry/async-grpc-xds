# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/cluster"
require "async/grpc/xds/client_side_weighted_round_robin"

describe Async::GRPC::XDS::ClientSideWeightedRoundRobin do
	it "builds a typed load-balancing policy" do
		policy = subject.build(18000, reporting_period: 2.5)
		cluster = Async::GRPC::XDS::Cluster.build("myservice", load_balancing_policy: policy)
		
		typed_configuration = cluster.load_balancing_policy.policies.first.typed_extension_config
		configuration = Envoy::Extensions::LoadBalancingPolicies::ClientSideWeightedRoundRobin::V3::ClientSideWeightedRoundRobin.decode(
			typed_configuration.typed_config.value
		)
		
		expect(cluster.lb_policy).to be == :ROUND_ROBIN
		expect(typed_configuration.name).to be == "envoy.load_balancing_policies.client_side_weighted_round_robin"
		expect(configuration.enable_oob_load_report.value).to be == true
		expect(configuration.oob_reporting_period.seconds).to be == 2
		expect(configuration.oob_reporting_period.nanos).to be == 500_000_000
		expect(configuration.oob_reporting_config.port_value).to be == 18000
	end
end
