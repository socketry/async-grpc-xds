# frozen_string_literal: true

require_relative "lib/async/grpc/xds/version"

Gem::Specification.new do |spec|
	spec.name = "async-grpc-xds"
	spec.version = Async::GRPC::XDS::VERSION
	
	spec.summary = "xDS support for Async::GRPC clients."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/async-grpc-xds"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/async-grpc-xds/",
		"source_code_uri" => "https://github.com/socketry/async-grpc-xds.git",
	}
	
	spec.files = Dir.glob(["{fixtures,lib,proto,xds}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)
	
	spec.required_ruby_version = ">= 3.3"
	
	spec.add_dependency "async", ">= 2.38.0"
	spec.add_dependency "async-grpc", "~> 0.7"
	spec.add_dependency "async-http"
	spec.add_dependency "google-protobuf"
	spec.add_dependency "protocol-grpc", "~> 0.11.0"
	spec.add_dependency "protocol-http", "~> 0.60"
end
