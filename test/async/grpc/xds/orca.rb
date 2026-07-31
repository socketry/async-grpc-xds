# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "xds/service/orca/v3/open_rca_service"

describe Xds::Service::Orca::V3::OpenRcaService do
	it "defines the server-streaming ORCA method" do
		rpc = subject.rpcs.fetch(:StreamCoreMetrics)
		
		expect(rpc.request_class).to be == Xds::Service::Orca::V3::OrcaLoadReportRequest
		expect(rpc.response_class).to be == Xds::Data::Orca::V3::OrcaLoadReport
		expect(rpc.streaming).to be == :server_streaming
	end
end
