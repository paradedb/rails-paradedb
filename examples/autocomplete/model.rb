# frozen_string_literal: true

require "active_record"
require_relative "../../lib/parade_db"

class MockItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "mock_items"
  self.primary_key = "id"
end

class MockItemIndex < ParadeDB::Index
  self.table_name = :mock_items
  self.key_field = :id
  self.index_name = :mock_items_bm25_idx
  self.fields = {
    id: nil,
    description: nil,
    rating: nil,
    category: { tokenizer: Tokenizer.literal() },
    "metadata->>'color'" => { tokenizer: Tokenizer.literal(options: {alias: "metadata_color"}) },
    "metadata->>'location'" => { tokenizer: Tokenizer.literal(options: {alias: "metadata_location"}) }
  }
end

class AutocompleteItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "autocomplete_items"
  self.primary_key = "id"
end

class AutocompleteItemIndex < ParadeDB::Index
  self.table_name = :autocomplete_items
  self.key_field = :id
  self.index_name = :autocomplete_items_idx
  self.fields = {
    id: nil,
    description: {
      tokenizers: [
        Tokenizer.unicode_words(),
        Tokenizer.ngram(3, 8, options: {alias: "description_ngram"})
      ]
    },
    category: { tokenizer: Tokenizer.literal() }
  }
end
