# frozen_string_literal: true

desc "Run unit tests"
task :test do
  ENV["PARADEDB_TEST_DSN"] ||= "postgresql://postgres:postgres@localhost:5432/postgres"
  ENV["PGPASSWORD"] ||= "postgres"

  sh "bundle exec rspec spec --pattern '**/*_unit_spec.rb'"
end

namespace :test do
  desc "Run integration tests (requires ParadeDB running)"
  task :integration do
    # Set up ParadeDB connection
    ENV["PARADEDB_TEST_DSN"] ||= "postgresql://postgres:postgres@localhost:5432/postgres"
    ENV["PGPASSWORD"] ||= "postgres"

    sh "bundle exec rspec spec --pattern '**/*_integration_spec.rb,**/*integration*_spec.rb'"
  end

  desc "Run all tests (unit + integration)"
  task :all => [:test, :integration]
end

task default: :test
