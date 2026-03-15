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

  it "keeps has_paradedb_index as a deprecated compatibility shim" do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end

    allow(ActiveSupport::Deprecation).to receive(:warn)

    klass.has_paradedb_index = true

    expect(klass.has_paradedb_index).to eq(true)
    expect(ActiveSupport::Deprecation).to have_received(:warn).with(/has no effect/)
  end
end
