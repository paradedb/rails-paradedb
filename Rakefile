# frozen_string_literal: true

require "json"
require "active_record"
require_relative "lib/parade_db"

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

    sh "bundle exec rspec spec --pattern '**/*_integration_spec.rb'"
  end

  desc "Run all tests (unit + integration)"
  task all: [:test, :integration]
end

namespace :paradedb do
  namespace :diagnostics do
    desc "List BM25 indexes from pdb.indexes()"
    task :indexes do
      rows = ParadeDB.paradedb_indexes(connection: paradedb_diagnostics_connection)
      puts JSON.pretty_generate(rows)
    end

    desc "List BM25 index segments from pdb.index_segments(index)"
    task :index_segments, [:index] do |_task, args|
      index = args[:index] || ENV["INDEX"]
      raise ArgumentError, "index is required (usage: rake paradedb:diagnostics:index_segments[my_index])" if index.nil? || index.strip.empty?

      rows = ParadeDB.paradedb_index_segments(index, connection: paradedb_diagnostics_connection)
      puts JSON.pretty_generate(rows)
    end

    desc "Run pdb.verify_index(index, ...)"
    task :verify_index, [:index] do |_task, args|
      index = args[:index] || ENV["INDEX"]
      raise ArgumentError, "index is required (usage: rake paradedb:diagnostics:verify_index[my_index])" if index.nil? || index.strip.empty?

      rows = ParadeDB.paradedb_verify_index(
        index,
        heapallindexed: paradedb_bool_env("HEAPALLINDEXED"),
        sample_rate: paradedb_float_env("SAMPLE_RATE"),
        report_progress: paradedb_bool_env("REPORT_PROGRESS"),
        verbose: paradedb_bool_env("VERBOSE"),
        on_error_stop: paradedb_bool_env("ON_ERROR_STOP"),
        segment_ids: paradedb_int_array_env("SEGMENT_IDS"),
        connection: paradedb_diagnostics_connection
      )
      puts JSON.pretty_generate(rows)
    end

    desc "Run pdb.verify_all_indexes(...)"
    task :verify_all_indexes do
      rows = ParadeDB.paradedb_verify_all_indexes(
        schema_pattern: ENV["SCHEMA_PATTERN"],
        index_pattern: ENV["INDEX_PATTERN"],
        heapallindexed: paradedb_bool_env("HEAPALLINDEXED"),
        sample_rate: paradedb_float_env("SAMPLE_RATE"),
        report_progress: paradedb_bool_env("REPORT_PROGRESS"),
        on_error_stop: paradedb_bool_env("ON_ERROR_STOP"),
        connection: paradedb_diagnostics_connection
      )
      puts JSON.pretty_generate(rows)
    end
  end
end

def paradedb_diagnostics_connection
  @paradedb_diagnostics_connection ||= begin
    if ActiveRecord::Base.connected?
      ActiveRecord::Base.connection
    else
      dsn = ENV["DATABASE_URL"] || ENV["PARADEDB_TEST_DSN"] || "postgresql://postgres:postgres@localhost:5432/postgres"
      ActiveRecord::Base.establish_connection(dsn)
      ActiveRecord::Base.connection
    end
  end
end

def paradedb_bool_env(name)
  value = ENV[name]
  return false if value.nil?

  %w[1 true t yes y on].include?(value.to_s.strip.downcase)
end

def paradedb_float_env(name)
  value = ENV[name]
  return nil if value.nil? || value.strip.empty?

  Float(value)
end

def paradedb_int_array_env(name)
  value = ENV[name]
  return nil if value.nil? || value.strip.empty?

  value.split(",").map { |part| Integer(part.strip) }
end

task default: :test
