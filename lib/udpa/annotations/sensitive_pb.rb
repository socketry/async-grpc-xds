# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "google/protobuf"

require "google/protobuf/descriptor_pb"


descriptor_data = "\n udpa/annotations/sensitive.proto\x12\x10udpa.annotations\x1a google/protobuf/descriptor.proto:3\n\tsensitive\x12\x1d.google.protobuf.FieldOptions\x18\xf7\xb6\xc1$ \x01(\x08\x62\x06proto3"

pool = ::Google::Protobuf::DescriptorPool.generated_pool
pool.add_serialized_file(descriptor_data)

module Udpa
	module Annotations
	end
end
