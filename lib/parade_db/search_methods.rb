# frozen_string_literal: true

require "active_record"

module ParadeDB
  # SearchMethods extends ActiveRecord::Relation to add ParadeDB full-text search capabilities.
  # This module is mixed into relations via .search() to provide chainable query methods.
  module SearchMethods
    # Internal state tracking
    attr_accessor :_paradedb_current_field
    attr_accessor :_paradedb_facet_fields
    attr_accessor :_paradedb_facet_opts

    def builder
      @_paradedb_builder ||= ParadeDB::Arel::Builder.new(table_name)
    end

    def table_name
      klass.table_name
    end

    def primary_key
      klass.primary_key || :id
    end

    # ---- ParadeDB search entrypoints ----

    def search(column)
      extending(SearchMethods).tap { |rel| rel._paradedb_current_field = column }
    end

    def matching_all(*terms, boost: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      node = builder.match(_paradedb_current_field, *terms, boost: boost)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    def matching_any(*terms)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      node = builder.match_any(_paradedb_current_field, *terms)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    def excluding(*terms)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      neg = builder.match(_paradedb_current_field, *terms)
      where(::Arel.sql(ParadeDB::Arel.to_sql(neg.not, connection)))
    end

    def phrase(text, slop: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      node = builder.phrase(_paradedb_current_field, text, slop: slop)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    def fuzzy(term, distance:, prefix: nil, boost: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      node = builder.fuzzy(_paradedb_current_field, term, distance: distance, prefix: prefix, boost: boost)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    def regex(pattern)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      node = builder.regex(_paradedb_current_field, pattern)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    def term(value, boost: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      node = builder.term(_paradedb_current_field, value, boost: boost)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    def near(left_term, right_term, distance: 1)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      node = builder.near(_paradedb_current_field, left_term, right_term, distance: distance)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    def phrase_prefix(*terms)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      
      node = builder.phrase_prefix(_paradedb_current_field, *terms)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    def more_like_this(key, fields: nil)
      key_value = key.respond_to?(:id) ? key.id : key
      pk_node = builder[primary_key]
      node = builder.more_like_this(pk_node, key_value, fields: fields)
      where(::Arel.sql(ParadeDB::Arel.to_sql(node, connection)))
    end

    # ---- Decorators ----

    def with_score
      score_sql = %(pdb.score("#{table_name}"."#{primary_key}") AS search_score)
      with_projection(score_sql)
    end

    def with_snippet(column, start_tag: nil, end_tag: nil, max_chars: nil)
      formatted_args = []
      formatted_args << connection.quote(start_tag) if start_tag
      formatted_args << connection.quote(end_tag) if end_tag
      formatted_args << max_chars if max_chars
      
      call = if formatted_args.empty?
               %(pdb.snippet("#{table_name}"."#{column}"))
             else
               %(pdb.snippet("#{table_name}"."#{column}", #{formatted_args.join(', ')}))
             end
      
      with_projection("#{call} AS #{column}_snippet")
    end

    # ---- Facets ----

    def facets(*fields, size: 10, order: "-count", missing: nil, agg: nil)
      build_facet_query(
        fields: fields,
        size: size,
        order: order,
        missing: missing,
        agg: agg
      ).execute
    end

    # Internal method to build facet query (for testing)
    def build_facet_query(fields:, size: 10, order: "-count", missing: nil, agg: nil)
      FacetQuery.build(
        table_name,
        where_values_as_sql,
        primary_key,
        fields: fields,
        size: size,
        order: order,
        missing: missing,
        agg: agg,
        connection: connection
      )
    end

    def with_facets(*fields, size: 10, order: nil, missing: nil, agg: nil)
      opts = { size: size, order: order, missing: missing, agg: agg }
      
      rel = extending(FacetRelation)
      rel._paradedb_facet_fields = fields
      rel._paradedb_facet_opts = opts
      
      # Add pdb.all() if no ParadeDB predicates exist (for aggregate pushdown)
      unless rel.has_paradedb_predicate?
        rel = rel.ensure_paradedb_predicate
      end
      
      # Add window aggregates to SELECT
      facet_selects = fields.map do |field|
        json = facet_json(field, opts)
        ::Arel.sql(%(pdb.agg('#{json}') OVER () AS _#{field}_facet))
      end

      rel = rel.select(::Arel.sql("#{table_name}.*")) if rel.select_values.empty?
      rel.select(*facet_selects)
    end

    def has_paradedb_predicate?
      sql = where_values_as_sql
      # Check for ParadeDB operators: &&&, |||, ###, @@@
      sql.match?(/(&&&|\|\|\||###|@@@)/)
    end

    def ensure_paradedb_predicate
      # Add pdb.all() sentinel to force aggregate pushdown
      pk_col = "#{connection.quote_table_name(table_name)}.#{connection.quote_column_name(primary_key)}"
      where(::Arel.sql("#{pk_col} @@@ pdb.all()"))
    end

    private

    def with_projection(sql_fragment)
      rel = self
      rel = rel.select(::Arel.sql("#{table_name}.*")) if rel.select_values.empty?
      rel.select(::Arel.sql(sql_fragment))
    end

    def where_values_as_sql
      # Extract WHERE clause SQL from the relation
      # For facet queries that need the predicate SQL
      where_clause = arel.where_sql
      return "" if where_clause.nil? || where_clause.empty?
      
      # Remove "WHERE " prefix if present
      where_clause.sub(/^\s*WHERE\s+/i, '')
    end

    def facet_json(field, opts)
      size = opts[:size] || 10
      order_opt = opts[:order]
      missing_clause = opts[:missing] ? %("missing": "#{opts[:missing]}", ) : ""
      order_clause =
        case order_opt
        when "-count" then ', "order": {"_count": "desc"}'
        when "count" then ', "order": {"_count": "asc"}'
        else ""
        end
      %({"terms": {#{missing_clause}"field": "#{field}", "size": #{size}#{order_clause}}})
    end

    # ---- Facet Query helper ----
    class FacetQuery
      attr_reader :sql, :connection

      def self.build(table, predicate_sql, primary_key, fields:, size:, order:, missing:, agg:, connection:)
        new(table, predicate_sql, primary_key, fields, size, order, missing, agg, connection)
      end

      def initialize(table, predicate_sql, primary_key, fields, size, order, missing, agg, connection)
        @connection = connection
        @table = table
        @primary_key = primary_key
        @sql = build_sql(table, predicate_sql, primary_key, fields, size, order, missing, agg, connection)
      end

      def execute
        result = connection.execute(sql)
        # Parse JSON results into hash
        parse_facets(result.first)
      end

      private

      def build_sql(table, predicate_sql, primary_key, fields, size, order, missing, agg, connection)
        # Check if predicate contains ParadeDB operators
        has_paradedb_predicate = predicate_sql.match?(/(&&&|\|\|\||###|@@@)/)
        
        if agg
          agg_json = agg
        else
          agg_json = ->(field) {
            missing_clause = missing ? %("missing": "#{missing}", ) : ""
            order_clause =
              case order
              when "-count" then ', "order": {"_count": "desc"}'
              when "count" then ', "order": {"_count": "asc"}'
              else ""
              end
            %({"terms": {#{missing_clause}"field": "#{field}", "size": #{size}#{order_clause}}})
          }
        end

        selects = fields.map do |field|
          json = agg ? agg : agg_json.call(field)
          %(pdb.agg('#{json}') AS #{field}_facet)
        end

        buf = []
        buf << "SELECT"
        buf << "  #{selects.join(",\n  ")}"
        buf << "FROM #{table}"
        
        # Add WHERE clause
        if !predicate_sql.empty? && has_paradedb_predicate
          buf << "WHERE #{predicate_sql}"
        elsif !predicate_sql.empty? && !has_paradedb_predicate
          # Has predicates but no ParadeDB operators - add pdb.all()
          pk_col = "#{connection.quote_table_name(table)}.#{connection.quote_column_name(primary_key)}"
          buf << "WHERE #{predicate_sql} AND #{pk_col} @@@ pdb.all()"
        elsif predicate_sql.empty?
          # No predicates at all - add pdb.all() sentinel
          pk_col = "#{connection.quote_table_name(table)}.#{connection.quote_column_name(primary_key)}"
          buf << "WHERE #{pk_col} @@@ pdb.all()"
        end
        
        buf.join("\n")
      end

      def parse_facets(row)
        return {} unless row
        
        facets = {}
        row.each do |key, value|
          if key.end_with?("_facet")
            field_name = key.delete_suffix("_facet")
            parsed = parse_facet_value(value)
            facets[field_name] = parsed unless parsed.nil?
          end
        end
        facets
      end

      def parse_facet_value(value)
        case value
        when nil
          nil
        when String
          JSON.parse(value)
        else
          value
        end
      end
    end

    # Module to add .facets accessor to relations
    module FacetRelation
      attr_accessor :_paradedb_facet_fields, :_paradedb_facet_opts

      def load(*)
        validate_facet_query_shape!
        super
      end

      def facets
        validate_facet_query_shape!
        @_facets_cache ||= extract_facets_from_results
      end

      private

      def validate_facet_query_shape!
        missing = []
        missing << "ORDER BY" if order_values.empty?
        missing << "LIMIT" if limit_value.nil?
        return if missing.empty?

        raise ParadeDB::FacetQueryError,
              "with_facets requires #{missing.join(' and ')} for ParadeDB TopN pushdown. " \
              "Use .order(...).limit(...)."
      end

      def extract_facets_from_results
        # Execute query and extract facet columns
        first_row = limit(1).first
        return {} unless first_row
        
        facets = {}
        _paradedb_facet_fields.each do |field|
          facet_col = "_#{field}_facet"
          if first_row.respond_to?(facet_col)
            value = first_row.public_send(facet_col)
            parsed = parse_facet_value(value)
            facets[field.to_s] = parsed unless parsed.nil?
          end
        end
        facets
      end

      def parse_facet_value(value)
        case value
        when nil
          nil
        when String
          JSON.parse(value)
        else
          value
        end
      end
    end
  end
end
