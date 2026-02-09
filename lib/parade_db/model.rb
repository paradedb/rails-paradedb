# frozen_string_literal: true

require_relative "search_methods"
require "active_support/concern"

module ParadeDB
  module Model
    extend ActiveSupport::Concern

    INJECTED_CLASS_METHODS = [:search, :more_like_this, :with_facets, :facets, :paradedb_arel].freeze

    def self.included(base)
      # Check for collisions on all injected class methods
      INJECTED_CLASS_METHODS.each do |method_name|
        detect_method_collision!(base, method_name)
      end

      base.extend(ClassMethods)
      base.class_attribute :has_paradedb_index, default: false
    end

    def self.detect_method_collision!(base, method_name)
      return unless base.singleton_methods(false).include?(method_name)

      method = base.method(method_name)
      source_location = method.source_location ? method.source_location.join(":") : "unknown"

      raise ParadeDB::MethodCollisionError,
            "Method collision on #{base.name}.#{method_name}. " \
            "Existing method owner=#{method.owner}, source=#{source_location}. " \
            "Rename the existing method or remove it before including ParadeDB::Model."
    end

    module ClassMethods
      def search(column)
        ensure_postgres!
        all.extending(SearchMethods).search(column)
      end

      def more_like_this(key, fields: nil, **options)
        ensure_postgres!
        all.extending(SearchMethods).more_like_this(key, fields: fields, **options)
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
