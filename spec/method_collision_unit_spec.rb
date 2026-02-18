# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MethodCollisionUnitTest" do
  it "including model raises when search is already defined" do
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

  it "including model does not raise without collision" do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end

    expect(klass).to respond_to(:search)
  end
end
