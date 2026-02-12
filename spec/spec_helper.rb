# frozen_string_literal: true

require "rspec"
require "active_record"
require_relative "../lib/parade_db"

ActiveRecord::Base.logger = nil

module LegacyAssertions
  def assert_equal(expected, actual, _message = nil)
    expect(actual).to eq(expected)
  end

  def assert(value, _message = nil)
    expect(value).to be(true)
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
    expect(value).to be(false)
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
  return if defined?($paradedb_schema_loaded) && $paradedb_schema_loaded

  ActiveRecord::Schema.define do
    suppress_messages do
      create_table :products, force: true do |t|
        t.text :description
        t.text :category
        t.integer :rating
        t.boolean :in_stock
        t.integer :price
      end

      create_table :categories, force: true do |t|
        t.text :name
      end
    end
  end

  $paradedb_schema_loaded = true
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
