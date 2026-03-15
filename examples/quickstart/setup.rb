# frozen_string_literal: true

require "logger"
require "rails"
require "active_record"
require_relative "../../lib/parade_db"
require_relative "../support/setup_helpers"

class QuickstartExampleApp < Rails::Application
  config.root = File.expand_path("../..", __dir__)
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "paradedb_examples_secret_key_base"
end

QuickstartExampleApp.initialize!

require_relative "model"

module QuickstartSetup
  extend ParadeDBExamples::SetupHelpers
  module_function

  def setup_mock_items!
    conn = prepare_mock_items_source_table!
    drop_bm25_indexes!(conn, :mock_items)
    conn.create_paradedb_index(MockItemIndex, if_not_exists: true)

    MockItem.reset_column_information
    MockItem.count
  end
end
