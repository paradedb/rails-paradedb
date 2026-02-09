# frozen_string_literal: true

require_relative "search_methods"
require "active_support/concern"

module ParadeDB
  module Model
    extend ActiveSupport::Concern

    INJECTED_CLASS_METHODS = [
      :search,
      :more_like_this,
      :with_facets,
      :facets,
      :paradedb_arel,
      :paradedb_index_class,
      :paradedb_indexed_fields,
      :paradedb_key_field,
      :paradedb_index_name,
      :paradedb_validate_index!
    ].freeze

    def self.included(base)
      unless defined?(ActiveRecord::Base) && base == ActiveRecord::Base
        # Check for collisions on all injected class methods
        INJECTED_CLASS_METHODS.each do |method_name|
          detect_method_collision!(base, method_name)
        end
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
        validate_field_indexed!(column)
        paradedb_validate_index!
        all.extending(SearchMethods).search(paradedb_search_column(column))
      end

      def more_like_this(key, fields: nil, **options)
        ensure_postgres!
        paradedb_validate_index!
        all.extending(SearchMethods).more_like_this(key, fields: fields, **options)
      end

      def with_facets(*fields, **opts)
        ensure_postgres!
        paradedb_validate_index!
        all.extending(SearchMethods).with_facets(*fields, **opts)
      end

      def facets(*fields, **opts)
        ensure_postgres!
        paradedb_validate_index!
        all.extending(SearchMethods).facets(*fields, **opts)
      end

      def paradedb_arel
        ensure_postgres!
        @paradedb_arel ||= ParadeDB::Arel::Builder.new(table_name)
      end

      def paradedb_index_class
        return @paradedb_index_class if instance_variable_defined?(:@paradedb_index_class)

        @paradedb_index_class = resolve_paradedb_index_class
      end

      def paradedb_indexed_fields
        definition = paradedb_index_definition
        return [] if definition.nil?

        definition.entries.map(&:query_key).uniq
      end

      def paradedb_key_field
        definition = paradedb_index_definition
        definition&.key_field
      end

      def paradedb_index_name
        definition = paradedb_index_definition
        definition&.index_name
      end

      def paradedb_validate_index!
        definition = paradedb_index_definition
        return true if definition.nil?
        return true if ParadeDB.index_validation_mode == :off

        if paradedb_catalog_index_valid?(definition)
          @paradedb_index_validated = true
          return true
        end

        message = "ParadeDB index drift detected for #{name}: expected #{definition.index_name} on #{definition.table_name} with bm25."
        case ParadeDB.index_validation_mode
        when :warn
          Kernel.warn(message)
          false
        when :raise
          raise ParadeDB::IndexDriftError, message
        else
          false
        end
      end

      private

      def ensure_postgres!
        ParadeDB.ensure_postgresql_adapter!(connection, context: "ParadeDB")
      end

      def resolve_paradedb_index_class
        return nil if name.nil? || name.empty?

        candidate_name = "#{name}Index"
        candidate = candidate_name.split("::").inject(Object) { |ctx, const_name| ctx.const_get(const_name) }
        return candidate if candidate <= ParadeDB::Index

        nil
      rescue NameError
        handle_missing_paradedb_index_class(candidate_name)
      end

      def handle_missing_paradedb_index_class(candidate_name)
        case ParadeDB.index_validation_mode
        when :warn
          Kernel.warn("ParadeDB index class not found for #{name}: expected #{candidate_name}")
          nil
        when :raise
          raise ParadeDB::IndexClassNotFoundError,
                "ParadeDB index class not found for #{name}: expected #{candidate_name}"
        else
          nil
        end
      end

      def paradedb_index_definition
        index_class = paradedb_index_class
        return nil if index_class.nil?

        @paradedb_index_definition ||= index_class.compiled_definition
      end

      def validate_field_indexed!(column)
        indexed_fields = paradedb_indexed_fields
        return if indexed_fields.empty?

        column_name = column.to_s
        return if indexed_fields.include?(column_name)

        raise ParadeDB::FieldNotIndexed,
              "#{name}.search(#{column.inspect}) is not indexed. Indexed fields: #{indexed_fields.join(', ')}"
      end

      def paradedb_search_column(column)
        definition = paradedb_index_definition
        return column if definition.nil?

        column_name = column.to_s
        entry = definition.entries.find { |candidate| candidate.query_key == column_name }
        return column if entry.nil?
        return entry.source.to_sym if entry.query_key == entry.source && !entry.expression

        source_sql =
          if entry.expression
            "(#{entry.source})"
          else
            "#{connection.quote_table_name(table_name)}.#{connection.quote_column_name(entry.source)}"
          end
        alias_value = connection.quote(entry.query_key)

        Arel.sql("(#{source_sql}::pdb.alias(#{alias_value}))")
      end

      def paradedb_catalog_index_valid?(definition)
        sql = <<~SQL
          SELECT 1
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_index i ON i.indexrelid = c.oid
          JOIN pg_class t ON t.oid = i.indrelid
          JOIN pg_am am ON am.oid = c.relam
          WHERE c.relname = #{connection.quote(definition.index_name.to_s)}
            AND t.relname = #{connection.quote(definition.table_name.to_s)}
            AND n.nspname = current_schema()
            AND am.amname = 'bm25'
          LIMIT 1
        SQL

        !connection.select_value(sql).nil?
      end
    end
  end
end

if defined?(ActiveRecord::Base) && !(ActiveRecord::Base < ParadeDB::Model)
  ActiveRecord::Base.include(ParadeDB::Model)
end
