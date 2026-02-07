# frozen_string_literal: true

require_relative "search_methods"
require "active_support/concern"

module ParadeDB
  module Model
    extend ActiveSupport::Concern

    def self.included(base)
      base.extend(ClassMethods)
      base.class_attribute :has_paradedb_index, default: false
    end

    module ClassMethods
      def search(column)
        ensure_paradedb_ready!
        all.extending(SearchMethods).search(column)
      end

      def more_like_this(key, fields: nil)
        ensure_paradedb_ready!
        all.extending(SearchMethods).more_like_this(key, fields: fields)
      end

      def with_facets(*fields, **opts)
        ensure_paradedb_ready!
        all.extending(SearchMethods).with_facets(*fields, **opts)
      end

      def facets(*fields, **opts)
        ensure_paradedb_ready!
        all.extending(SearchMethods).facets(*fields, **opts)
      end

      def paradedb_arel
        ensure_paradedb_ready!
        @paradedb_arel ||= ParadeDB::Arel::Builder.new(table_name)
      end

      private

      def ensure_paradedb_ready!
        unless has_paradedb_index
          raise "ParadeDB is not enabled for #{name} (set self.has_paradedb_index = true)"
        end

        ParadeDB.ensure_postgresql_adapter!(connection, context: "ParadeDB")
      end
    end
  end
end
