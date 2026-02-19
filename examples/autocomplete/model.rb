# frozen_string_literal: true

require "active_record"
require_relative "../../lib/parade_db"

class MockItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "mock_items"
  self.primary_key = "id"
  self.has_paradedb_index = true
end

class MockItemIndex < ParadeDB::Index
  self.table_name = :mock_items
  self.key_field = :id
  self.index_name = :mock_items_bm25_idx
  self.fields = [
    :id,
    :description,
    :rating,
    { category: { literal: { alias: "category" } } },
    { "metadata->>'color'" => { literal: { alias: "metadata_color" } } },
    { "metadata->>'location'" => { literal: { alias: "metadata_location" } } }
  ]
end

class AutocompleteItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "autocomplete_items"
  self.primary_key = "id"
  self.has_paradedb_index = true
end

class AutocompleteItemIndex < ParadeDB::Index
  self.table_name = :autocomplete_items
  self.key_field = :id
  self.index_name = :autocomplete_items_idx
  self.fields = [
    :id,
    { description: { unicode_words: {}, ngram: { min: 3, max: 8, alias: "description_ngram" } } },
    { category: { literal: { alias: "category" } } }
  ]
end
