# frozen_string_literal: true

require "spec_helper"

class MethodCollisionUnitTest < Minitest::Test
  def test_including_model_raises_when_search_is_already_defined
    error = assert_raises(ParadeDB::MethodCollisionError) do
      Class.new(ActiveRecord::Base) do
        self.table_name = :products

        def self.search(_query)
          :custom_search
        end

        include ParadeDB::Model
      end
    end

    assert_includes error.message, "Method collision"
    assert_includes error.message, ".search"
  end

  def test_including_model_does_not_raise_without_search_collision
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end

    assert_respond_to klass, :search
  end
end
