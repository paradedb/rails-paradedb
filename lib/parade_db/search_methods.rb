# frozen_string_literal: true

require "active_record"

module ParadeDB
  # SearchMethods extends ActiveRecord::Relation to add ParadeDB full-text search capabilities.
  # This module is mixed into relations via .search() to provide chainable query methods.
  module SearchMethods
    MLT_OPTION_ALIASES = {
      min_term_freq: :min_term_frequency,
      min_term_frequency: :min_term_frequency,
      max_query_terms: :max_query_terms,
      min_doc_freq: :min_doc_frequency,
      min_doc_frequency: :min_doc_frequency,
      max_term_freq: :max_term_frequency,
      max_term_frequency: :max_term_frequency,
      max_doc_freq: :max_doc_frequency,
      max_doc_frequency: :max_doc_frequency,
      min_word_length: :min_word_length,
      max_word_length: :max_word_length,
      stopwords: :stopwords
    }.freeze
    MLT_INTEGER_OPTION_KEYS = %i[
      min_term_frequency
      max_query_terms
      min_doc_frequency
      max_term_frequency
      max_doc_frequency
      min_word_length
      max_word_length
    ].freeze
    MLT_OPTION_ORDER = %i[
      min_term_frequency
      max_query_terms
      min_doc_frequency
      max_term_frequency
      max_doc_frequency
      min_word_length
      max_word_length
      stopwords
    ].freeze

    # Internal state tracking
    attr_accessor :_paradedb_current_field
    attr_accessor :_paradedb_facet_fields

    module PredicateInspector
      PARADEDB_INFIX_OPERATORS = %w[&&& ||| ### @@@ === ##].freeze
      PARADEDB_SQL_PATTERN = /(&&&|\|\|\||###|@@@|===|##|pdb\.)/

      module_function

      def relation_has_paradedb_predicate?(relation)
        return false unless relation
        contains_paradedb_predicate?(relation.where_clause&.ast)
      end

      def contains_paradedb_predicate?(node)
        case node
        when nil
          false
        when ::Array
          node.any? { |child| contains_paradedb_predicate?(child) }
        when ::Arel::Nodes::InfixOperation
          PARADEDB_INFIX_OPERATORS.include?(node.operator.to_s) ||
            contains_paradedb_predicate?(node.left) ||
            contains_paradedb_predicate?(node.right)
        when ::Arel::Nodes::NamedFunction
          node.name.to_s.start_with?("pdb.") ||
            node.expressions.any? { |expr| contains_paradedb_predicate?(expr) }
        when ::Arel::Nodes::SqlLiteral
          node.to_s.match?(PARADEDB_SQL_PATTERN)
        when ::Arel::Nodes::Grouping
          contains_paradedb_predicate?(node.expr)
        when ::Arel::Nodes::And
          node.children.any? { |child| contains_paradedb_predicate?(child) }
        when ::Arel::Nodes::Or
          contains_paradedb_predicate?(node.left) || contains_paradedb_predicate?(node.right)
        when ::Arel::Nodes::Not
          contains_paradedb_predicate?(node.expr)
        when ::Arel::Nodes::Node
          # Custom ParadeDB nodes
          node.class.name.start_with?("ParadeDB::") ||
            (node.respond_to?(:expr) && contains_paradedb_predicate?(node.expr)) ||
            (node.respond_to?(:left) && contains_paradedb_predicate?(node.left)) ||
            (node.respond_to?(:right) && contains_paradedb_predicate?(node.right))
        else
          false
        end
      end
    end

    def builder
      @_paradedb_builder ||= begin
        ensure_paradedb_runtime!
        ParadeDB::Arel::Builder.new(table_name)
      end
    end

    def table_name
      klass.table_name
    end

    def primary_key
      klass.primary_key || :id
    end

    # ---- ParadeDB search entrypoints ----

    def search(column)
      ensure_paradedb_runtime!
      extending(SearchMethods).tap { |rel| rel._paradedb_current_field = column }
    end

    def matching_all(
      *terms,
      distance: nil,
      prefix: nil,
      transposition_cost_one: nil,
      boost: nil,
      constant_score: nil
    )
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      node = builder.match(
        _paradedb_current_field,
        *terms,
        distance: distance,
        prefix: prefix,
        transposition_cost_one: transposition_cost_one,
        boost: boost,
        constant_score: constant_score
      )
      where(grouped(node))
    end

    def matching_any(
      *terms,
      distance: nil,
      prefix: nil,
      transposition_cost_one: nil,
      boost: nil,
      constant_score: nil
    )
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      node = builder.match_any(
        _paradedb_current_field,
        *terms,
        distance: distance,
        prefix: prefix,
        transposition_cost_one: transposition_cost_one,
        boost: boost,
        constant_score: constant_score
      )
      where(grouped(node))
    end

    def excluding(*terms)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      neg = builder.match(_paradedb_current_field, *terms)
      where(grouped(neg.not))
    end

    def phrase(text, slop: nil, boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      node = builder.phrase(_paradedb_current_field, text, slop: slop, boost: boost, constant_score: constant_score)
      where(grouped(node))
    end

    def regex(pattern, boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      node = builder.regex(_paradedb_current_field, pattern, boost: boost, constant_score: constant_score)
      where(grouped(node))
    end

    def term(
      value,
      distance: nil,
      prefix: nil,
      transposition_cost_one: nil,
      boost: nil,
      constant_score: nil
    )
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      node = builder.term(
        _paradedb_current_field,
        value,
        distance: distance,
        prefix: prefix,
        transposition_cost_one: transposition_cost_one,
        boost: boost,
        constant_score: constant_score
      )
      where(grouped(node))
    end

    def term_set(*values, boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      node = builder.term_set(_paradedb_current_field, *values, boost: boost, constant_score: constant_score)
      where(grouped(node))
    end

    def near(left_term, right_term, distance: 1, boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      node = builder.near(_paradedb_current_field, left_term, right_term, distance: distance, boost: boost, constant_score: constant_score)
      where(grouped(node))
    end

    def phrase_prefix(*terms, max_expansion: nil, boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      node = builder.phrase_prefix(
        _paradedb_current_field,
        *terms,
        max_expansion: max_expansion,
        boost: boost,
        constant_score: constant_score
      )
      where(grouped(node))
    end

    # Parse query-string syntax into ParadeDB query AST (e.g. "running AND shoes").
    def parse(query, lenient: nil, conjunction_mode: nil, boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field
      node = builder.parse(
        _paradedb_current_field,
        query,
        lenient: lenient,
        conjunction_mode: conjunction_mode,
        boost: boost,
        constant_score: constant_score
      )
      where(grouped(node))
    end

    # Match-all wrapper for APIs that need an explicit ParadeDB predicate.
    # Use with `.search(:id)` (or any indexed field): `Product.search(:id).match_all`.
    def match_all(boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      where(grouped(builder.match_all(_paradedb_current_field, boost: boost, constant_score: constant_score)))
    end

    # Exists wrapper to match rows where the indexed field has a value.
    # Use with `.search(:id)` (or another exists-compatible indexed field).
    def exists(boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      where(grouped(builder.exists(_paradedb_current_field, boost: boost, constant_score: constant_score)))
    end

    # Range wrapper for numeric/date/timestamp fields in ParadeDB query context.
    # Examples:
    #   Product.search(:rating).range(3..5)
    #   Product.search(:rating).range(gte: 3, lt: 5)
    def range(value = nil, gte: nil, gt: nil, lte: nil, lt: nil, type: nil, boost: nil, constant_score: nil)
      raise "No search field set. Call .search(column) first." unless _paradedb_current_field

      inferred_type = type || default_range_type_for_field(_paradedb_current_field)
      node = builder.range(_paradedb_current_field, value, gte: gte, gt: gt, lte: lte, lt: lt, type: inferred_type, boost: boost, constant_score: constant_score)
      where(grouped(node))
    end

    def more_like_this(key, fields: nil, **options)
      ensure_paradedb_runtime!
      runtime_key_field = paradedb_runtime_key_field
      key_value = more_like_this_key_value(key, runtime_key_field)
      pk_node = builder[runtime_key_field]
      mlt_options = normalize_more_like_this_options(options)
      node = builder.more_like_this(pk_node, key_value, fields: fields, options: mlt_options)
      where(grouped(node))
    end

    # ---- Decorators ----

    def with_score
      with_projection(builder.score(paradedb_runtime_key_field).as("search_score"))
    end

    def with_snippet(column, start_tag: nil, end_tag: nil, max_chars: nil)
      formatted_args = []
      formatted_args << start_tag unless start_tag.nil?
      formatted_args << end_tag unless end_tag.nil?
      formatted_args << Integer(max_chars) unless max_chars.nil?

      snippet =
        if formatted_args.empty?
          builder.snippet(column)
        else
          builder.snippet(column, *formatted_args)
        end

      with_projection(snippet.as("#{column}_snippet"))
    end

    def with_snippets(
      column,
      start_tag: nil,
      end_tag: nil,
      max_chars: nil,
      limit: nil,
      offset: nil,
      sort_by: nil,
      as: nil
    )
      snippets = builder.snippets(
        column,
        start_tag: start_tag,
        end_tag: end_tag,
        max_num_chars: normalize_integer_option!(max_chars, "max_chars"),
        limit: normalize_integer_option!(limit, "limit"),
        offset: normalize_integer_option!(offset, "offset"),
        sort_by: normalize_snippets_sort_by(sort_by)
      )

      with_projection(snippets.as(normalize_projection_alias(as, "#{column}_snippets")))
    end

    def with_snippet_positions(column, as: nil)
      positions = builder.snippet_positions(column)
      with_projection(positions.as(normalize_projection_alias(as, "#{column}_snippet_positions")))
    end

    # ---- Facets ----

    def facets(*fields, size: 10, order: :count_desc, missing: nil, agg: nil)
      ensure_paradedb_runtime!
      build_facet_query(
        fields: fields,
        size: size,
        order: order,
        missing: missing,
        agg: agg
      ).execute
    end

    def facets_agg(**named_aggregations)
      agg_specs = normalize_named_aggregation_specs(named_aggregations)
      build_aggregation_query(agg_specs).execute
    end

    # Internal method to build facet query (for testing)
    def build_facet_query(fields:, size: 10, order: :count_desc, missing: nil, agg: nil)
      ensure_paradedb_runtime!
      facet_args = normalize_facet_inputs(fields: fields, size: size, order: order, missing: missing, agg: agg)
      FacetQuery.build(
        relation: self,
        primary_key: paradedb_runtime_key_field,
        builder: builder,
        fields: facet_args[:fields],
        size: facet_args[:size],
        order: facet_args[:order],
        missing: facet_args[:missing],
        agg: facet_args[:agg],
        connection: connection
      )
    end

    def with_facets(*fields, size: 10, order: :count_desc, missing: nil, agg: nil)
      ensure_paradedb_runtime!
      facet_args = normalize_facet_inputs(fields: fields, size: size, order: order, missing: missing, agg: agg)
      opts = {
        size: facet_args[:size],
        order: facet_args[:order],
        missing: facet_args[:missing],
        agg: facet_args[:agg]
      }
      facet_fields = facet_args[:agg].nil? ? facet_args[:fields] : [:agg]

      rel = extending(FacetRelation)
      rel._paradedb_facet_fields = facet_fields

      # Add pdb.all() if no ParadeDB predicates exist (for aggregate pushdown)
      unless rel.has_paradedb_predicate?
        rel = rel.ensure_paradedb_predicate
      end

      # Add window aggregates to SELECT using native Arel nodes.
      facet_selects = facet_fields.map do |field|
        json = facet_args[:agg] || facet_json(field, opts)
        builder.agg(json).over.as("_#{field}_facet")
      end

      rel = rel.select(klass.arel_table[::Arel.star]) if rel.select_values.empty?
      rel.select(*facet_selects)
    end

    def with_agg(**named_aggregations)
      ensure_paradedb_runtime!
      agg_specs = normalize_named_aggregation_specs(named_aggregations)
      rel = extending(FacetRelation, AggregationRelation)
      rel._paradedb_facet_fields = agg_specs.keys

      unless rel.has_paradedb_predicate?
        rel = rel.ensure_paradedb_predicate
      end

      facet_selects = agg_specs.map do |alias_name, json|
        builder.agg(json).over.as("_#{alias_name}_facet")
      end

      rel = rel.select(klass.arel_table[::Arel.star]) if rel.select_values.empty?
      rel.select(*facet_selects)
    end

    def has_paradedb_predicate?
      PredicateInspector.relation_has_paradedb_predicate?(self)
    end

    def ensure_paradedb_predicate
      # Add pdb.all() sentinel to force aggregate pushdown
      where(grouped(builder.match_all(paradedb_runtime_key_field)))
    end

    private

    def paradedb_runtime_key_field
      return primary_key unless klass.respond_to?(:paradedb_key_field)

      key_field = klass.paradedb_key_field
      return primary_key if key_field.nil? || key_field.to_s.empty?

      key_field
    end

    def default_range_type_for_field(field)
      column = klass.columns_hash[field.to_s]
      return nil unless column

      case column.type
      when :integer
        "int8range"
      when :float, :decimal
        "numrange"
      when :date
        "daterange"
      when :datetime, :timestamp, :time
        "tsrange"
      else
        nil
      end
    end

    def more_like_this_key_value(key, runtime_key_field)
      return key.public_send(runtime_key_field) if key.respond_to?(runtime_key_field)
      return key.id if key.respond_to?(:id)

      key
    end

    def ensure_paradedb_runtime!
      ParadeDB.ensure_postgresql_adapter!(connection, context: "ParadeDB search")
      ParadeDB::Arel::Visitor.install!
    end

    def grouped(node)
      ::Arel::Nodes::Grouping.new(node)
    end

    def with_projection(projection)
      rel = self
      rel = rel.select(klass.arel_table[::Arel.star]) if rel.select_values.empty?
      rel.select(projection)
    end

    def facet_json(field, opts)
      size = opts.key?(:size) ? opts[:size] : 10
      order_key, order_direction = facet_order(opts[:order])

      payload = {
        field: field.to_s,
        size: size,
        missing: opts[:missing]&.to_s
      }.compact

      payload[:order] = { order_key => order_direction } if order_key

      JSON.generate(terms: payload)
    end

    def normalize_more_like_this_options(options)
      normalized = {}
      options.each do |raw_key, value|
        canonical = MLT_OPTION_ALIASES[raw_key.to_sym]
        unless canonical
          allowed = MLT_OPTION_ALIASES.keys.map(&:inspect).join(", ")
          raise ArgumentError, "Unknown more_like_this option #{raw_key.inspect}. Valid options: #{allowed}"
        end

        if MLT_INTEGER_OPTION_KEYS.include?(canonical)
          normalized[canonical] = normalize_positive_integer_option!(canonical, value)
          next
        end

        if canonical == :stopwords
          normalized_stopwords = normalize_stopwords_option!(value)
          normalized[canonical] = normalized_stopwords unless normalized_stopwords.empty?
        end
      end

      ordered = {}
      MLT_OPTION_ORDER.each do |key|
        ordered[key] = normalized[key] if normalized.key?(key)
      end
      ordered
    end

    def normalize_facet_inputs(fields:, size:, order:, missing:, agg:)
      normalized_agg = agg.nil? ? nil : normalize_agg_json(agg)
      normalized_fields = normalize_facet_fields(fields, agg: normalized_agg)
      normalized_size = normalize_facet_size(size)
      facet_order(order)

      {
        fields: normalized_fields,
        size: normalized_size,
        order: order,
        missing: missing,
        agg: normalized_agg
      }
    end

    def normalize_named_aggregation_specs(named_aggregations)
      ParadeDB::Aggregations
        .build_named_payload(named_aggregations)
        .transform_values(&:to_json)
    end

    def build_aggregation_query(agg_specs)
      AggregationQuery.build(
        relation: self,
        primary_key: paradedb_runtime_key_field,
        builder: builder,
        agg_specs: agg_specs,
        connection: connection
      )
    end

    def normalize_facet_fields(fields, agg:)
      raw_fields = Array(fields)
      return [] unless agg.nil?
      raise ArgumentError, "facets requires at least one field or agg" if raw_fields.empty?

      normalized = raw_fields.map do |field|
        case field
        when String then field
        when Symbol then field.to_s
        else
          raise TypeError, "Facet field names must be strings or symbols, got #{field.class}"
        end
      end

      if normalized.uniq.length != normalized.length
        raise ArgumentError, "Facet field names must be unique."
      end

      normalized
    end

    def normalize_facet_size(size)
      return nil if size.nil?

      normalized = Integer(size)
      raise ArgumentError, "Facet size must be an integer greater than or equal to 0." if normalized.negative?

      normalized
    rescue ArgumentError, TypeError
      raise ArgumentError, "Facet size must be an integer greater than or equal to 0."
    end

    def normalize_positive_integer_option!(name, value)
      unless value.is_a?(Integer)
        raise ArgumentError, "#{name} must be an Integer >= 1, got #{value.class}"
      end
      raise ArgumentError, "#{name} must be an Integer >= 1" if value < 1

      value
    end

    def normalize_stopwords_option!(value)
      unless value.respond_to?(:to_ary)
        raise ArgumentError, "stopwords must be an Array of strings"
      end

      stopwords = value.to_ary.map do |term|
        case term
        when String then term
        when Symbol then term.to_s
        else
          raise ArgumentError, "stopwords must contain only strings"
        end
      end

      stopwords.reject(&:empty?)
    end

    def normalize_integer_option!(value, name)
      return nil if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{name} must be an integer"
    end

    def normalize_snippets_sort_by(sort_by)
      return nil if sort_by.nil?

      value = sort_by.to_s
      return value if %w[score position].include?(value)

      raise ArgumentError, "sort_by must be one of: score, position"
    end

    def normalize_projection_alias(custom_alias, default_alias)
      return default_alias if custom_alias.nil?

      value = custom_alias.to_s
      raise ArgumentError, "as cannot be blank" if value.strip.empty?

      value
    end

    def facet_order(order)
      case order
      when :count_desc then ["_count", "desc"]
      when :count_asc then ["_count", "asc"]
      when :key_desc then ["_key", "desc"]
      when :key_asc then ["_key", "asc"]
      when nil then nil
      else
        raise ArgumentError,
              "Unknown facet order #{order.inspect}. Valid values: :count_desc, :count_asc, :key_desc, :key_asc"
      end
    end

    def normalize_agg_json(agg)
      case agg
      when Hash then agg.to_json
      when String then agg
      else
        raise ArgumentError,
              "agg must be a Hash or JSON String, got #{agg.class}"
      end
    end

    # ---- Facet Query helper ----
    class FacetQuery
      attr_reader :relation, :connection

      def self.build(relation:, primary_key:, builder:, fields:, size:, order:, missing:, agg:, connection:)
        new(
          relation: relation,
          primary_key: primary_key,
          builder: builder,
          fields: fields,
          size: size,
          order: order,
          missing: missing,
          agg: agg,
          connection: connection
        )
      end

      def initialize(relation:, primary_key:, builder:, fields:, size:, order:, missing:, agg:, connection:)
        @connection = connection
        @relation = build_relation(
          relation: relation,
          primary_key: primary_key,
          builder: builder,
          fields: fields,
          size: size,
          order: order,
          missing: missing,
          agg: agg
        )
      end

      def sql
        relation.to_sql
      end

      def execute
        parse_facets(connection.select_one(sql))
      end

      private

      def build_relation(relation:, primary_key:, builder:, fields:, size:, order:, missing:, agg:)
        predicate_scope = relation.except(:select, :order, :limit, :offset, :group, :having, :distinct)
        predicate_scope = predicate_scope.select(relation.klass.arel_table[::Arel.star]) if predicate_scope.select_values.empty?

        unless PredicateInspector.relation_has_paradedb_predicate?(predicate_scope)
          predicate_scope = predicate_scope.where(::Arel::Nodes::Grouping.new(builder.match_all(primary_key)))
        end

        source_alias = "paradedb_facet_source"
        source = predicate_scope.arel.as(source_alias)
        projections = build_facet_projections(relation, builder, fields, size, order, missing, agg)

        relation.klass.unscoped.from(source).select(*projections)
      end

      def build_facet_projections(relation, builder, fields, size, order, missing, agg)
        return [builder.agg(relation.send(:normalize_agg_json, agg)).as("agg_facet")] if agg

        fields.map do |field|
          opts = { size: size, order: order, missing: missing }
          json = relation.send(:facet_json, field, opts)
          builder.agg(json).as("#{field}_facet")
        end
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

    class AggregationQuery
      attr_reader :relation, :connection

      def self.build(relation:, primary_key:, builder:, agg_specs:, connection:)
        new(
          relation: relation,
          primary_key: primary_key,
          builder: builder,
          agg_specs: agg_specs,
          connection: connection
        )
      end

      def initialize(relation:, primary_key:, builder:, agg_specs:, connection:)
        @connection = connection
        @agg_specs = agg_specs
        @relation = build_relation(
          relation: relation,
          primary_key: primary_key,
          builder: builder,
          agg_specs: agg_specs
        )
      end

      def sql
        relation.to_sql
      end

      def execute
        row = connection.select_one(sql)
        parse_aggregates(row)
      end

      private

      attr_reader :agg_specs

      def build_relation(relation:, primary_key:, builder:, agg_specs:)
        predicate_scope = relation.except(:select, :order, :limit, :offset, :group, :having, :distinct)
        predicate_scope = predicate_scope.select(relation.klass.arel_table[::Arel.star]) if predicate_scope.select_values.empty?

        unless PredicateInspector.relation_has_paradedb_predicate?(predicate_scope)
          predicate_scope = predicate_scope.where(::Arel::Nodes::Grouping.new(builder.match_all(primary_key)))
        end

        source_alias = "paradedb_agg_source"
        source = predicate_scope.arel.as(source_alias)
        projections = agg_specs.map { |alias_name, json| builder.agg(json).as("#{alias_name}_facet") }

        relation.klass.unscoped.from(source).select(*projections)
      end

      def parse_aggregates(row)
        return {} unless row

        aggregates = {}
        row.each do |key, value|
          next unless key.end_with?("_facet")

          name = key.delete_suffix("_facet")
          parsed = parse_value(value)
          aggregates[name] = parsed unless parsed.nil?
        end
        aggregates
      end

      def parse_value(value)
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
      attr_accessor :_paradedb_facet_fields

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

    module AggregationRelation
      def aggregates
        facets
      end
    end
  end
end
