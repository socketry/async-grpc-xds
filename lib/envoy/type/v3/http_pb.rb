# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "google/protobuf"

require "udpa/annotations/status_pb"


descriptor_data = "\n\x18\x65nvoy/type/v3/http.proto\x12\renvoy.type.v3\x1a\x1dudpa/annotations/status.proto*2\n\x0f\x43odecClientType\x12\t\n\x05HTTP1\x10\x00\x12\t\n\x05HTTP2\x10\x01\x12\t\n\x05HTTP3\x10\x02\x42o\n\x1bio.envoyproxy.envoy.type.v3B\tHttpProtoP\x01Z;github.com/envoyproxy/go-control-plane/envoy/type/v3;typev3\xba\x80\xc8\xd1\x06\x02\x10\x02\x62\x06proto3"

pool = ::Google::Protobuf::DescriptorPool.generated_pool
pool.add_serialized_file(descriptor_data)

module Envoy
	module Type
		module V3
			CodecClientType = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("envoy.type.v3.CodecClientType").enummodule
		end
	end
end
