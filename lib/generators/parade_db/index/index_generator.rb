# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module ParadeDB
  module Generators
    class IndexGenerator < Rails::Generators::NamedBase
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :fields, type: :array, default: [], banner: "field field ..."

      class_option :concurrent, type: :boolean, default: false,
                                desc: "Add disable_ddl_transaction! to the migration (required for concurrent index creation)"

      desc "Creates a ParadeDB::Index class and a BM25 index migration for MODEL."

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_index_file
        template "index.rb.tt", "app/parade_db/#{file_name}_index.rb"
      end

      def create_migration_file
        migration_template "migration.rb.tt", "db/migrate/create_#{table_name}_bm25_index.rb"
      end

      private

      def index_name
        "#{table_name}_bm25_idx"
      end

      def migration_class_name
        "Create#{class_name}Bm25Index"
      end
    end
  end
end
