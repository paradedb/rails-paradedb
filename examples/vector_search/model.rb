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
  self.index_name = :search_idx
  self.fields = {
    id: nil,
    description: nil,
    category: { tokenizer: ParadeDB::Tokenizer.literal() },
    embedding: { metric: :l2 }
  }
end
