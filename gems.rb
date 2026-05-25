# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

source "https://rubygems.org"

gemspec

group :maintenance, optional: true do
	gem "bake-gem"
	gem "bake-releases"
	gem "utopia-project"
end

group :test do
	gem "covered"
	gem "sus"
	gem "sus-fixtures-async-http"
end
