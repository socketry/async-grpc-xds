# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "protocol/grpc/interface"
require "xds/service/orca/v3/orca_pb"

module Xds
	module Service
		module Orca
			module V3
				# Interface definition for the out-of-band ORCA load reporting service.
				class OpenRcaService < Protocol::GRPC::Interface
					rpc :StreamCoreMetrics,
						request_class: OrcaLoadReportRequest,
						response_class: Xds::Data::Orca::V3::OrcaLoadReport,
						streaming: :server_streaming
				end
			end
		end
	end
end
