# frozen_string_literal: true

require "rake/testtask"

desc "Run unit tests"
task :test do
  sh "ruby -Ilib -Ispec -e 'Dir[\"spec/**/*_unit_spec.rb\"].sort.each { |f| require File.expand_path(f) }'"
end

namespace :test do
  desc "Run integration tests (requires ParadeDB running)"
  task :integration do
    # Set up ParadeDB connection
    ENV["PARADEDB_TEST_DSN"] ||= "postgresql://postgres:postgres@localhost:5432/postgres"
    ENV["PGPASSWORD"] ||= "postgres"
    
    sh "ruby -Ilib -Ispec -e 'Dir[\"spec/*_integration_spec.rb\", \"spec/*integration*_spec.rb\"].sort.each { |f| require File.expand_path(f) }'"
  end

  desc "Run all tests (unit + integration)"
  task :all => [:test, :integration]
end

task default: :test
