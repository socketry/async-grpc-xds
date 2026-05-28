# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/service"
require "async/grpc/xds/client"
require "async/grpc/test_interface"
require "json"
require "tmpdir"

describe Async::GRPC::XDS::Client do
	let(:bootstrap) do
		{
			"xds_servers" => [
				{
					"server_uri" => "127.0.0.1:18000",
					"channel_creds" => [{"type" => "insecure"}]
				}
			],
			"node" => {
				"id" => "test-node",
				"cluster" => "test"
			}
		}
	end
	
	it "normalizes bootstrap hash keys" do
		client = subject.new("myservice", bootstrap: bootstrap)
		
		normalized = client.instance_variable_get(:@bootstrap)
		expect(normalized[:xds_servers].first[:server_uri]).to be == "127.0.0.1:18000"
		expect(normalized[:xds_servers].first[:channel_creds].first[:type]).to be == "insecure"
		expect(normalized[:node][:id]).to be == "test-node"
	ensure
		client&.close
	end
	
	it "loads bootstrap JSON from a file" do
		Dir.mktmpdir do |directory|
			path = File.join(directory, "bootstrap.json")
			File.write(path, JSON.dump(bootstrap))
			
			client = subject.new("myservice", bootstrap: path)
			
			expect(client.instance_variable_get(:@bootstrap)[:node][:cluster]).to be == "test"
		ensure
			client&.close
		end
	end
	
	it "rejects invalid bootstrap values" do
		expect do
			subject.new("myservice", bootstrap: Object.new)
		end.to raise_exception(ArgumentError)
	end
	
	it "rejects missing bootstrap files" do
		expect do
			subject.new("myservice", bootstrap: "/missing/bootstrap.json")
		end.to raise_exception(Async::GRPC::XDS::Client::ConfigurationError)
	end
	
	it "rejects invalid bootstrap JSON" do
		Dir.mktmpdir do |directory|
			path = File.join(directory, "bootstrap.json")
			File.write(path, "{")
			
			expect do
				subject.new("myservice", bootstrap: path)
			end.to raise_exception(Async::GRPC::XDS::Client::ConfigurationError)
		end
	end
	
	it "rejects missing default bootstrap configuration" do
		previous = ENV.delete("GRPC_XDS_BOOTSTRAP")
		
		expect do
			subject.new("myservice")
		end.to raise_exception(Async::GRPC::XDS::Client::ConfigurationError)
	ensure
		ENV["GRPC_XDS_BOOTSTRAP"] = previous
	end
	
	it "builds stubs without resolving endpoints" do
		client = subject.new("myservice", bootstrap: bootstrap)
		stub = client.stub(Async::GRPC::Fixtures::TestInterface, "myservice")
		
		expect(stub).to be_a(Async::GRPC::Stub)
		expect(stub.interface.name).to be == "myservice"
	ensure
		client&.close
	end
end
