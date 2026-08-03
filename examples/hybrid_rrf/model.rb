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

  self.table_name = "mock_items"
  self.primary_key = "id"

  has_neighbors :embedding
end

class MockItemIndex < ParadeDB::Index
  self.table_name = :mock_items
  self.key_field = :id
  self.index_name = :search_idx
  self.fields = {
    id: nil,
    description: nil,
    rating: nil,
    category: { tokenizer: ParadeDB::Tokenizer.literal() },
    "metadata->>'color'" => { tokenizer: ParadeDB::Tokenizer.literal(options: {alias: "metadata_color"}) },
    "metadata->>'location'" => { tokenizer: ParadeDB::Tokenizer.literal(options: {alias: "metadata_location"}) }
  }
end
