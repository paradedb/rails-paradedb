# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Experimental vector router" do
  %w[graph ivf].each do |router|
    it "creates #{router} indexes and preserves the router in schema dumps" do
      connection = ActiveRecord::Base.connection
      connection.execute("CREATE TABLE router_items (id int, embedding vector(64))")
      begin
        connection.add_paradedb_index(:router_items, name: :router_idx, fields: {id: {}, embedding: {metric: :l2}}, index_options: {vector_router: router})
        options = connection.select_value("SELECT reloptions FROM pg_class WHERE oid = 'router_idx'::regclass")
        expect(options).to include("vector_router=#{router}")
        dump = StringIO.new
        ActiveRecord::SchemaDumper.dump(connection.pool, dump)
        expect(dump.string).to include(":vector_router => \"#{router}\"")
      ensure
        connection.execute("DROP TABLE router_items CASCADE")
      end
    end
  end

  it "omits the router by default and rejects unsupported routers" do
    connection = ActiveRecord::Base.connection
    connection.execute("CREATE TABLE router_items (id int, embedding vector(64))")
    begin
      connection.add_paradedb_index(:router_items, name: :router_idx, fields: {id: {}, embedding: {metric: :l2}})
      options = connection.select_value("SELECT reloptions FROM pg_class WHERE oid = 'router_idx'::regclass")
      expect(options.to_s).not_to include("vector_router")
      expect {
        connection.add_paradedb_index(:router_items, name: :invalid_router_idx, fields: {id: {}, embedding: {metric: :l2}}, index_options: {vector_router: "invalid"})
      }.to raise_error(ParadeDB::InvalidIndexDefinition, /vector_router/)
    ensure
      connection.execute("DROP TABLE router_items CASCADE")
    end
  end
end
