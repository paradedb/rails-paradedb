# frozen_string_literal: true

require "logger"
require "rails"
require "active_record"
require_relative "../../lib/parade_db"
require_relative "../support/setup_helpers"

class FacetedSearchExampleApp < Rails::Application
  config.root = File.expand_path("../..", __dir__)
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "paradedb_examples_secret_key_base"
end

FacetedSearchExampleApp.initialize!

require_relative "model"

module FacetedSearchSetup
  extend ParadeDBExamples::SetupHelpers
  module_function

  def setup_mock_items!
    conn = recreate_mock_items_copy!(:mock_items_faceted_search)
    conn.remove_bm25_index(:mock_items_faceted_search, name: :mock_items_faceted_search_bm25_idx, if_exists: true)
    conn.create_paradedb_index(MockItemIndex, if_not_exists: true)

    MockItem.reset_column_information
    MockItem.count
  end
end
