# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MethodCollisionUnitTest" do
  it "including model does not override an existing search method" do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = :products

      def self.search(_query)
        :custom_search
      end

      include ParadeDB::Model
    end

    expect(klass.search("query")).to eq(:custom_search)
    expect(klass).to respond_to(:paradedb_search)
  end

  it "including model does not raise without collision" do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end

    expect(klass).to respond_to(:search)
    expect(klass).to respond_to(:paradedb_search)
  end
end
