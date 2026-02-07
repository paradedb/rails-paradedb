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
        ensure_postgres!
        all.extending(SearchMethods).search(column)
      end

      def more_like_this(key, fields: nil)
        ensure_postgres!
        all.extending(SearchMethods).more_like_this(key, fields: fields)
      end

      def with_facets(*fields, **opts)
        ensure_postgres!
        all.extending(SearchMethods).with_facets(*fields, **opts)
      end

      def facets(*fields, **opts)
        ensure_postgres!
        all.extending(SearchMethods).facets(*fields, **opts)
      end

      def paradedb_arel
        ensure_postgres!
        @paradedb_arel ||= ParadeDB::Arel::Builder.new(table_name)
      end

      private

      def ensure_postgres!
        ParadeDB.ensure_postgresql_adapter!(connection, context: "ParadeDB")
      end
    end
  end
end
