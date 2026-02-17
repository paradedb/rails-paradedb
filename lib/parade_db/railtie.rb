# frozen_string_literal: true

require "rails/railtie"

module ParadeDB
  class Railtie < Rails::Railtie
    initializer "parade_db.install_arel_visitor" do
      ActiveSupport.on_load(:active_record) do
        ParadeDB::Arel::Visitor.install!
      end
    end
  end
end
