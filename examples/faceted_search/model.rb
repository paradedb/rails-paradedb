# frozen_string_literal: true

begin
  require "neighbor"
rescue LoadError
  abort "Example requires neighbor. Run with `BUNDLE_GEMFILE=examples/Gemfile bundle exec ...`."
end

require "active_record"
require_relative "../../lib/parade_db"

class MockItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "mock_items_faceted_search"
  self.primary_key = "id"
  self.has_paradedb_index = true
end

class MockItemIndex < ParadeDB::Index
  self.table_name = :mock_items_faceted_search
  self.key_field = :id
  self.index_name = :mock_items_faceted_search_bm25_idx
  self.fields = [
    :id,
    :description,
    :rating,
    { category: { literal: { alias: "category" } } },
    { "metadata->>'color'" => { literal: { alias: "metadata_color" } } },
    { "metadata->>'location'" => { literal: { alias: "metadata_location" } } }
  ]
end
