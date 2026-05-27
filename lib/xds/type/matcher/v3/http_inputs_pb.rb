# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "google/protobuf"


descriptor_data = "\n%xds/type/matcher/v3/http_inputs.proto\x12\x13xds.type.matcher.v3\"\x1d\n\x1bHttpAttributesCelMatchInputB_\n\x1e\x63om.github.xds.type.matcher.v3B\x0fHttpInputsProtoP\x01Z*github.com/cncf/xds/go/xds/type/matcher/v3b\x06proto3"

pool = ::Google::Protobuf::DescriptorPool.generated_pool
pool.add_serialized_file(descriptor_data)

module Xds
	module Type
		module Matcher
			module V3
				HttpAttributesCelMatchInput = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("xds.type.matcher.v3.HttpAttributesCelMatchInput").msgclass
			end
		end
	end
end
