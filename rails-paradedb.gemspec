# frozen_string_literal: true

require_relative "lib/parade_db/version"

Gem::Specification.new do |spec|
  spec.name = "rails-paradedb"
  spec.version = ParadeDB::VERSION
  spec.authors = ["ParadeDB"]
  spec.email = ["support@paradedb.com"]

  spec.summary = "ParadeDB integration for ActiveRecord"
  spec.description = "Simple, Elastic-quality search for Postgres via ParadeDB and ActiveRecord."
  spec.homepage = "https://github.com/paradedb/rails-paradedb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/paradedb/rails-paradedb",
    "documentation_uri" => "https://docs.paradedb.com",
    "changelog_uri" => "https://github.com/paradedb/rails-paradedb/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/paradedb/rails-paradedb/issues",
  }

  spec.files = Dir.chdir(__dir__) do
    Dir.glob("lib/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) } +
      %w[README.md LICENSE CHANGELOG.md]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2", "< 9"
  spec.add_dependency "activesupport", ">= 7.2", "< 9"
  spec.add_dependency "pg", "~> 1.5"
  spec.add_dependency "railties", ">= 7.2", "< 9"
end
