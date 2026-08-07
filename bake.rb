# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "fileutils"
require "tmpdir"

PROTOBUF_SOURCES = {
	"envoy" => ["https://github.com/envoyproxy/data-plane-api.git", "84e84367f2560cdb47b9bb78fd3e615feb80c3e4"],
	"google/protobuf" => ["https://github.com/protocolbuffers/protobuf.git", "68cb3eaca7cf86ee8eec7e1b54523643fd6aa344", "src"],
	"google/rpc" => ["https://github.com/googleapis/api-common-protos.git", "3332dec527759859840a3a2ff108c67a54708130"],
	"xds" => ["https://github.com/cncf/xds.git", "dba9d589def2cd10099a3a64887d859188c2f57a"],
	"udpa" => ["https://github.com/cncf/udpa.git", "c52dc94e7fbe6449d8465faaeda22c76ca62d4ff"],
	"validate" => ["https://github.com/envoyproxy/protoc-gen-validate.git", "414042a5ff2e98dc47f8161937316a25b1da5bba"],
}.freeze

# Update the vendored protobuf definitions from pinned upstream revisions and regenerate their Ruby classes.
#
# @parameter proto_dir [String] The directory containing vendored protobuf definitions.
# @parameter output_dir [String] The directory containing generated Ruby classes.
def update_protos(proto_dir: "proto", output_dir: "lib")
	proto_dir = File.expand_path(proto_dir)
	files = Dir.glob(File.join(proto_dir, "**/*.proto"))
	
	Dir.mktmpdir("async-grpc-xds-protos") do |temporary_root|
		repositories = {}
		
		PROTOBUF_SOURCES.each_value do |url, revision, source_root|
			repository = File.join(temporary_root, repositories.size.to_s)
			system("git", "init", "--quiet", repository) or raise "Could not initialize a repository for #{url}!"
			system("git", "-C", repository, "remote", "add", "origin", url) or raise "Could not configure #{url}!"
			system("git", "-C", repository, "fetch", "--quiet", "--depth", "1", "origin", revision) or raise "Could not fetch #{revision} from #{url}!"
			system("git", "-C", repository, "checkout", "--quiet", "FETCH_HEAD") or raise "Could not check out #{revision} from #{url}!"
			
			repositories[url] = File.join(repository, source_root.to_s)
		end
		
		files.each do |destination|
			relative_path = destination.delete_prefix("#{proto_dir}/")
			prefix, source = PROTOBUF_SOURCES.find{|prefix, _source| relative_path.start_with?("#{prefix}/")}
			raise "No upstream source for #{relative_path}!" unless source
			
			url = source.first
			source_path = File.join(repositories.fetch(url), relative_path)
			raise "Could not find #{relative_path} in #{url}!" unless File.file?(source_path)
			
			FileUtils.cp(source_path, destination)
		end
	end
	
	{
		updated: files.size,
		sources: PROTOBUF_SOURCES.transform_values{|_url, revision, _source_root| revision},
		generated: generate_protos(proto_dir: proto_dir, output_dir: output_dir),
	}
end

# Generate the checked-in Ruby classes from the vendored protobuf definitions.
#
# @parameter proto_dir [String] The directory containing vendored protobuf definitions.
# @parameter output_dir [String] The output directory for generated Ruby classes.
def generate_protos(proto_dir: "proto", output_dir: "lib")
	proto_dir = File.expand_path(proto_dir)
	output_dir = File.expand_path(output_dir)
	
	files = Dir.glob(File.join(output_dir, "**/*_pb.rb")).map do |path|
		relative_path = path.delete_prefix("#{output_dir}/").sub(/_pb\.rb\z/, ".proto")
		File.join(proto_dir, relative_path)
	end
	
	missing = files.reject{|path| File.file?(path)}
	raise "Missing protobuf definitions: #{missing.join(', ')}" unless missing.empty?
	
	FileUtils.mkdir_p(output_dir)
	system("protoc", "--ruby_out=#{output_dir}", "--proto_path=#{proto_dir}", *files) or raise "Could not generate Ruby protobuf classes!"
	
	files.size
end

# Update the project documentation with the new version number.
#
# @parameter version [String] The new version number.
def after_gem_release_version_increment(version)
	context["releases:update"].call(version)
	context["utopia:project:update"].call
end

# Create a GitHub release for the given tag.
#
# @parameter tag [String] The tag to create a release for.
def after_gem_release(tag:, **options)
	context["releases:github:release"].call(tag)
end
