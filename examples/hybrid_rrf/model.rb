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

  self.table_name = "mock_items_hybrid_rrf"
  self.primary_key = "id"
  self.has_paradedb_index = true

  has_neighbors :embedding
end

class MockItemIndex < ParadeDB::Index
  self.table_name = :mock_items_hybrid_rrf
  self.key_field = :id
  self.index_name = :mock_items_hybrid_rrf_bm25_idx
  self.fields = [
    :id,
    :description,
    :rating,
    { category: { literal: { alias: "category" } } },
    { "metadata->>'color'" => { literal: { alias: "metadata_color" } } },
    { "metadata->>'location'" => { literal: { alias: "metadata_location" } } }
  ]
end
