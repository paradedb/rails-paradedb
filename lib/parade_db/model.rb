# frozen_string_literal: true

require_relative "search_methods"
require "active_support/concern"

module ParadeDB
  module Model
    extend ActiveSupport::Concern

    DEPRECATED_HAS_PARADEDB_INDEX_MESSAGE =
      "`has_paradedb_index` is deprecated, has no effect, and will be removed in a future release."

    INJECTED_CLASS_METHODS = [
      :paradedb_search,
      :more_like_this,
      :with_facets,
      :facets,
      :with_agg,
      :facets_agg,
      :aggregate_by,
      :paradedb_arel,
      :paradedb_index,
      :paradedb_index_class,
      :paradedb_index_classes,
      :paradedb_indexed_fields,
      :paradedb_key_field,
      :paradedb_index_name,
      :paradedb_validate_index!
    ].freeze

    def self.included(base)
      unless defined?(ActiveRecord::Base) && base == ActiveRecord::Base
        INJECTED_CLASS_METHODS.each do |method_name|
          detect_method_collision!(base, method_name)
        end
      end

      base.extend(ClassMethods)

      # Provide `.search` as a convenience alias unless the model already defines it.
      # In collision scenarios (Searchkick, Ransack, etc.), users can call `.paradedb_search`.
      unless base.respond_to?(:search)
        base.singleton_class.define_method(:search) do |column|
          paradedb_search(column)
        end
      end
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
      def has_paradedb_index
        warn_has_paradedb_index_deprecation!
        return @has_paradedb_index if instance_variable_defined?(:@has_paradedb_index)

        false
      end

      def has_paradedb_index=(value)
        warn_has_paradedb_index_deprecation!
        @has_paradedb_index = value
      end

      def paradedb_search(column)
        ensure_postgres!
        all.extending(SearchMethods).search(column)
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

      def with_agg(**named_aggregations)
        ensure_postgres!
        paradedb_validate_index!
        all.extending(SearchMethods).with_agg(**named_aggregations)
      end

      def facets_agg(**named_aggregations)
        ensure_postgres!
        paradedb_validate_index!
        all.extending(SearchMethods).facets_agg(**named_aggregations)
      end

      def aggregate_by(*group_fields, exact: nil, **named_aggregations)
        ensure_postgres!
        paradedb_validate_index!
        all.extending(SearchMethods).aggregate_by(
          *group_fields,
          exact: exact,
          **named_aggregations
        )
      end

      def paradedb_arel
        ensure_postgres!
        @paradedb_arel ||= ParadeDB::Arel::Builder.new(table_name)
      end

      def paradedb_index(index_class)
        @paradedb_explicit_index_classes ||= []
        @paradedb_explicit_index_classes << index_class unless @paradedb_explicit_index_classes.include?(index_class)
        remove_instance_variable(:@paradedb_index_class) if instance_variable_defined?(:@paradedb_index_class)
        remove_instance_variable(:@paradedb_index_definition) if instance_variable_defined?(:@paradedb_index_definition)
        index_class
      end

      def paradedb_index_classes
        if instance_variable_defined?(:@paradedb_explicit_index_classes) && !@paradedb_explicit_index_classes.empty?
          @paradedb_explicit_index_classes.dup
        else
          klass = resolve_paradedb_index_class
          klass ? [klass] : []
        end
      end

      def paradedb_index_class
        return @paradedb_index_class if instance_variable_defined?(:@paradedb_index_class)

        @paradedb_index_class = paradedb_index_classes.first
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
        return true if ParadeDB.index_validation_mode == :off

        classes = paradedb_index_classes
        return true if classes.empty?

        all_valid = true
        classes.each do |klass|
          definition = klass.compiled_definition
          next if paradedb_catalog_index_valid?(definition)

          all_valid = false
          message = "ParadeDB index drift detected for #{name}: expected #{definition.index_name} on #{definition.table_name} with bm25."
          case ParadeDB.index_validation_mode
          when :warn
            paradedb_log_warn(message)
          when :raise
            raise ParadeDB::IndexDriftError, message
          end
        end
        all_valid
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
          paradedb_log_warn("ParadeDB index class not found for #{name}: expected #{candidate_name}")
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

      def paradedb_normalize_search_column(column, table_name: self.table_name)
        validate_field_indexed!(column)
        paradedb_validate_index!
        paradedb_search_column(column, table_name: table_name)
      end

      def paradedb_group_column(column, table_name: self.table_name)
        validate_field_indexed!(column)
        paradedb_validate_index!

        entry = paradedb_index_entry(column)
        return column if entry.nil?
        return paradedb_entry_source_node(entry, table_name: table_name)
      end

      def paradedb_search_column(column, table_name: self.table_name)
        entry = paradedb_index_entry(column)
        return column if entry.nil?
        return paradedb_entry_source_node(entry, table_name: table_name) if entry.query_key == entry.source && !entry.expression

        source_sql = paradedb_entry_source_sql(entry, table_name: table_name)
        alias_value = connection.quote(entry.query_key)

        Arel.sql("(#{source_sql}::pdb.alias(#{alias_value}))")
      end

      def paradedb_log_warn(message)
        if defined?(Rails) && Rails.logger
          Rails.logger.warn(message)
        else
          Kernel.warn(message)
        end
      end

      def warn_has_paradedb_index_deprecation!
        ActiveSupport::Deprecation.warn(DEPRECATED_HAS_PARADEDB_INDEX_MESSAGE)
      end

      def paradedb_catalog_index_valid?(definition)
        sql = <<~SQL
          SELECT 1
          FROM pg_index i
          JOIN pg_class c ON c.oid = i.indexrelid
          JOIN pg_am am ON am.oid = c.relam
          WHERE i.indexrelid = to_regclass(#{connection.quote(definition.index_name.to_s)})
            AND i.indrelid = to_regclass(#{connection.quote(definition.table_name.to_s)})
            AND am.amname = 'bm25'
          LIMIT 1
        SQL

        !connection.select_value(sql).nil?
      end

      def paradedb_index_entry(column)
        definition = paradedb_index_definition
        return nil if definition.nil?

        definition.entries.find { |candidate| candidate.query_key == column.to_s }
      end

      def paradedb_entry_source_node(entry, table_name: self.table_name)
        return entry.source.to_sym if !entry.expression && table_name.to_s == self.table_name.to_s

        Arel.sql(paradedb_entry_source_sql(entry, table_name: table_name))
      end

      def paradedb_entry_source_sql(entry, table_name: self.table_name)
        if entry.expression
          "(#{entry.source})"
        else
          "#{connection.quote_table_name(table_name)}.#{connection.quote_column_name(entry.source)}"
        end
      end
    end
  end
end
