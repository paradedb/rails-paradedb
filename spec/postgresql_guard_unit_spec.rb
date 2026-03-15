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

RSpec.describe "PostgreSQLGuardUnitTest" do
  after do
    GuardProduct._mock_adapter_name = nil
  end

  it "helper allows postgresql" do
    mock_connection = Struct.new(:adapter_name).new("PostgreSQL")
    ParadeDB.ensure_postgresql_adapter!(mock_connection, context: "test helper")
  end
  it "helper rejects non postgresql" do
    mock_connection = Struct.new(:adapter_name).new("SQLite")
    error = assert_raises(ParadeDB::UnsupportedAdapterError) do
      ParadeDB.ensure_postgresql_adapter!(mock_connection, context: "test helper")
    end
    assert_includes error.message, "PostgreSQL"
    assert_includes error.message, "SQLite"
  end
  it "model search rejects non postgresql" do
    GuardProduct._mock_adapter_name = "SQLite"

    error = assert_raises(ParadeDB::UnsupportedAdapterError) { GuardProduct.search(:description) }
    assert_includes error.message, "PostgreSQL"
  end
  it "model paradedb arel rejects non postgresql" do
    GuardProduct._mock_adapter_name = "SQLite"

    error = assert_raises(ParadeDB::UnsupportedAdapterError) { GuardProduct.paradedb_arel }
    assert_includes error.message, "PostgreSQL"
  end
  it "relation search methods reject non postgresql" do
    GuardProduct._mock_adapter_name = "SQLite"

    relation = GuardProduct.all.extending(ParadeDB::SearchMethods)
    error = assert_raises(ParadeDB::UnsupportedAdapterError) { relation.search(:description) }
    assert_includes error.message, "PostgreSQL"
  end

end
