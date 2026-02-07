# frozen_string_literal: true

require "spec_helper"

class GuardProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products

  class << self
    attr_accessor :_mock_adapter_name

    def connection
      return super if _mock_adapter_name.nil?

      Struct.new(:adapter_name).new(_mock_adapter_name)
    end
  end
end

class PostgreSQLGuardUnitTest < Minitest::Test
  def teardown
    GuardProduct._mock_adapter_name = nil
  end

  def test_helper_allows_postgresql
    mock_connection = Struct.new(:adapter_name).new("PostgreSQL")
    ParadeDB.ensure_postgresql_adapter!(mock_connection, context: "test helper")
  end

  def test_helper_rejects_non_postgresql
    mock_connection = Struct.new(:adapter_name).new("SQLite")
    error = assert_raises(ParadeDB::UnsupportedAdapterError) do
      ParadeDB.ensure_postgresql_adapter!(mock_connection, context: "test helper")
    end
    assert_includes error.message, "PostgreSQL"
    assert_includes error.message, "SQLite"
  end

  def test_model_search_rejects_non_postgresql
    GuardProduct._mock_adapter_name = "SQLite"

    error = assert_raises(ParadeDB::UnsupportedAdapterError) { GuardProduct.search(:description) }
    assert_includes error.message, "PostgreSQL"
  end

  def test_model_paradedb_arel_rejects_non_postgresql
    GuardProduct._mock_adapter_name = "SQLite"

    error = assert_raises(ParadeDB::UnsupportedAdapterError) { GuardProduct.paradedb_arel }
    assert_includes error.message, "PostgreSQL"
  end

  def test_relation_search_methods_reject_non_postgresql
    GuardProduct._mock_adapter_name = "SQLite"

    relation = GuardProduct.all.extending(ParadeDB::SearchMethods)
    error = assert_raises(ParadeDB::UnsupportedAdapterError) { relation.search(:description) }
    assert_includes error.message, "PostgreSQL"
  end

end
