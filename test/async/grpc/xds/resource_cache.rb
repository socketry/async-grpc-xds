# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/xds/resource_cache"

describe Async::GRPC::XDS::ResourceCache do
	let(:cache) {subject.new}
	
	it "stores clusters by name" do
		cluster = Struct.new(:name).new("myservice")
		
		cache.update_cluster(cluster)
		
		expect(cache.get_cluster("myservice")).to be == cluster
	end
	
	it "stores endpoints by cluster name" do
		endpoints = [Object.new]
		
		cache.update_endpoints("myservice", endpoints)
		
		expect(cache.get_endpoints("myservice")).to be == endpoints
	end
	
	it "clears cached resources" do
		cache.update_cluster(Struct.new(:name).new("myservice"))
		cache.update_endpoints("myservice", [Object.new])
		
		cache.clear
		
		expect(cache.get_cluster("myservice")).to be == nil
		expect(cache.get_endpoints("myservice")).to be == nil
	end
end
