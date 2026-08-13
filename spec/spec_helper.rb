# frozen_string_literal: true

if ENV["COVERAGE"] == "1"
  require "simplecov"
  require "simplecov-cobertura"

  SimpleCov.start do
    command_name ENV.fetch("COVERAGE_COMMAND_NAME", "rspec")
    enable_coverage :branch
    track_files "lib/**/*.rb"
    add_filter "/spec/"
    add_filter "/vendor/"
    add_filter "/examples/"
    formatter SimpleCov::Formatter::MultiFormatter.new(
      [
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::CoberturaFormatter
      ]
    )
  end
end

require "rspec"
require "logger"
require "rails"
require "active_record"
require_relative "../lib/parade_db"

unless defined?(ParadeDBTestApp)
  class ParadeDBTestApp < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "paradedb_test_secret_key_base"
  end

  ParadeDBTestApp.initialize!
end

ActiveRecord::Base.logger = nil

module LegacyAssertions
  def assert_equal(expected, actual, _message = nil)
    expect(actual).to eq(expected)
  end

  def assert(value, _message = nil)
    expect(value).to be_truthy
  end

  def assert_nil(value, _message = nil)
    expect(value).to be_nil
  end

  def assert_instance_of(klass, value, _message = nil)
    expect(value).to be_instance_of(klass)
  end

  def assert_match(pattern, value, _message = nil)
    expect(value).to match(pattern)
  end

  def assert_includes(collection, member, _message = nil)
    expect(collection).to include(member)
  end

  def assert_kind_of(klass, value, _message = nil)
    expect(value).to be_a(klass)
  end

  def assert_empty(collection, _message = nil)
    expect(collection).to be_empty
  end

  def assert_operator(lhs, operator, rhs, _message = nil)
    expect(lhs.public_send(operator, rhs)).to be(true)
  end

  def assert_not(value, _message = nil)
    expect(value).to be_falsy
  end

  def assert_in_delta(expected, actual, delta = 0.001, _message = nil)
    expect(actual).to be_within(delta).of(expected)
  end

  def assert_raises(*error_classes)
    begin
      yield
    rescue StandardError => e
      return e if error_classes.any? { |klass| e.is_a?(klass) }

      expected = error_classes.map(&:name).join(", ")
      raise RSpec::Expectations::ExpectationNotMetError,
            "Expected #{expected}, but got #{e.class}: #{e.message}"
    end

    expected = error_classes.map(&:name).join(", ")
    raise RSpec::Expectations::ExpectationNotMetError, "Expected #{expected}, but nothing was raised"
  end

  def refute_equal(unexpected, actual, _message = nil)
    expect(actual).not_to eq(unexpected)
  end

  def refute_nil(value, _message = nil)
    expect(value).not_to be_nil
  end

  def refute_empty(collection, _message = nil)
    expect(collection).not_to be_empty
  end

  def refute_includes(collection, member, _message = nil)
    expect(collection).not_to include(member)
  end
end

RSpec.configure do |config|
  config.include LegacyAssertions
  config.disable_monkey_patching!
end

def establish_test_connection
  dsn = ENV["PARADEDB_TEST_DSN"].to_s
  if dsn.empty?
    raise "PARADEDB_TEST_DSN is required for all tests. Example: postgres://postgres:postgres@localhost:5432/postgres"
  end

  ActiveRecord::Base.establish_connection(dsn)
  ParadeDB.ensure_postgresql_adapter!(ActiveRecord::Base.connection, context: "Test suite")
end

def setup_test_schema
  connection = ActiveRecord::Base.connection
  connection.execute("CREATE EXTENSION IF NOT EXISTS pg_search CASCADE;")
  connection.drop_table(:mock_items, if_exists: true)
  connection.execute("CALL paradedb.create_bm25_test_table(schema_name => 'public', table_name => 'mock_items');")

  setup_test_index
end

def setup_test_index
  remove_test_indexes
  ActiveRecord::Base.connection.execute(<<~SQL)
    CREATE INDEX mock_items_search_idx ON mock_items
    USING paradedb (id, description, rating, (category::pdb.literal), in_stock, metadata, created_at, last_updated_date, latest_available_time, weight_range, embedding vector_l2_ops)
    WITH (key_field='id');
  SQL
end

def remove_test_indexes
  connection = ActiveRecord::Base.connection
  connection.select_values(<<~SQL).each do |index|
    SELECT indexname
    FROM pg_indexes
    WHERE schemaname = current_schema()
      AND tablename = 'mock_items'
      AND indexdef LIKE '%USING paradedb%'
  SQL
    connection.execute("DROP INDEX IF EXISTS #{connection.quote_table_name(index)}")
  end
end

establish_test_connection
setup_test_schema

def normalize_sql(sql)
  sql.to_s.strip
     .gsub(/\s+/, " ")
     .gsub(/"/, "")
     .gsub(/\bTRUE\b/i, "true")
     .gsub(/\bFALSE\b/i, "false")
     .gsub(/\(\s*([A-Za-z0-9_\.]+)\s*=\s*(true|false)\s*\)/i, '\\1 = \\2')
end

def assert_sql_equal(expected, actual)
  assert_equal normalize_sql(expected), normalize_sql(actual)
end

def assert_query_sql(expected, actual)
  assert_sql_equal expected, actual
  ActiveRecord::Base.connection.execute(actual)
end
