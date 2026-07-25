# frozen_string_literal: true

require "active_record"
require_relative "../../lib/parade_db"

class VectorItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "vector_items"
  self.primary_key = "id"
end

class VectorItemIndex < ParadeDB::Index
  self.table_name = :vector_items
  self.key_field = :id
  self.index_name = :vector_items_bm25_idx
  self.fields = {
    id: nil,
    description: nil,
    category: { tokenizer: ParadeDB::Tokenizer.literal() },
    embedding: { metric: :l2 }
  }
end
