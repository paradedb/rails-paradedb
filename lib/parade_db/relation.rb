# frozen_string_literal: true

module ParadeDB
  class Relation
    attr_reader :model, :table, :builder, :predicates, :selects, :order_clause, :limit_value, :facet_fields, :facet_opts, :with_facet_window, :current_field

    def initialize(model, predicates: [], selects: nil, order_clause: nil, limit_value: nil, facet_fields: nil, facet_opts: {}, with_facet_window: false, current_field: nil)
      @model = model
      @table = model.table_name
      @builder = model.parade_arel
      @predicates = predicates # array of {sql:, kind: :search|:filter}
      @selects = selects || ["*"]
      @order_clause = order_clause
      @limit_value = limit_value
      @facet_fields = facet_fields
      @facet_opts = facet_opts
      @with_facet_window = with_facet_window
      @current_field = current_field
    end

    # ---- ParadeDB search entrypoints ----

    def search(column)
      dup_with(current_field: column)
    end

    # Matching AND terms
    def matching(*terms, any: nil, boost: nil)
      new_pred =
        if any
          builder.match_any(current_field, *any)
        else
          builder.match(current_field, *terms, boost: boost)
        end
      chain_with(new_pred)
    end

    # Exclusion (NOT)
    def excluding(*terms)
      neg = builder.match(current_field, *terms)
      chain_with(neg.not)
    end

    def phrase(text, slop: nil)
      chain_with(builder.phrase(current_field, text, slop: slop))
    end

    def fuzzy(term, distance:, prefix: nil, boost: nil)
      chain_with(builder.fuzzy(current_field, term, distance: distance, prefix: prefix, boost: boost))
    end

    def regex(pattern)
      chain_with(builder.regex(current_field, pattern))
    end

    def term(value, boost: nil)
      chain_with(builder.term(current_field, value, boost: boost))
    end

    def near(left_term, right_term, distance: 1)
      chain_with(builder.near(current_field, left_term, right_term, distance: distance))
    end

    def phrase_prefix(*terms)
      chain_with(builder.phrase_prefix(current_field, *terms))
    end

    def similar_to(key, fields: nil)
      predicate = builder.more_like_this(primary_key_node, key, fields: fields)
      chain_with(predicate)
    end

    # ---- Decorators ----

    def with_score
      dup_with(selects: ["#{table}. *".gsub(" ", ""), %(pdb.score("#{table}"."#{primary_key}") AS search_score)])
    end

    def with_snippet(column, start_tag: nil, end_tag: nil, max_chars: nil)
      formatted_args = []
      formatted_args << literal(start_tag) if start_tag
      formatted_args << literal(end_tag) if end_tag
      formatted_args << max_chars if max_chars
      call = if formatted_args.empty?
               %(pdb.snippet("#{table}"."#{column}"))
             else
               %(pdb.snippet("#{table}"."#{column}", #{formatted_args.join(', ')}))
             end
      dup_with(selects: ["#{table}. *".gsub(" ", ""), %(#{call} AS #{column}_snippet)])
    end

    def facets(*fields, size: 10, order: "-count", missing: nil, agg: nil)
      FacetQuery.build(table, predicates_sql, fields: fields, size: size, order: order, missing: missing, agg: agg)
    end

    def with_facets(*fields, size: 10, order: nil, missing: nil, agg: nil)
      opts = { size: size, order: order, missing: missing, agg: agg }
      add_facets(fields, opts)
    end

    # ---- ActiveRecord-like chaining ----

    def where(conditions)
      pred = predicate_from_where(conditions)
      chain_with(pred, kind: :filter)
    end

    def order(clause)
      new_clause =
        case clause
        when Hash
          clause.map { |k, v| "#{k} #{v.to_s.upcase}" }.join(", ")
        else
          clause.to_s
        end
      dup_with(order_clause: new_clause)
    end

    def limit(value)
      dup_with(limit_value: value)
    end

    def select(*columns)
      dup_with(selects: columns)
    end

    def or(other)
      combined = "((#{predicates_sql}) OR (#{other.send(:predicates_sql)}))"
      dup_with(predicates: [{ sql: combined, kind: :search }])
    end

    # ---- Rendering ----

    def to_sql
      buf = []
      buf << select_sql
      buf << where_clause unless predicates.empty?
      buf << order_sql if order_clause
      buf << limit_sql if limit_value
      buf.join("\n")
    end

    def sql
      to_sql
    end

  protected

  def current_field
      @current_field
  end

    private

    def chain_with(node_or_string, kind: :search)
      pred_sql =
        case node_or_string
        when String then node_or_string
        else
          ParadeDB::Arel.to_sql(node_or_string)
        end

      dup_with(predicates: predicates + [{ sql: pred_sql, kind: kind }])
    end

    def predicate_from_where(conditions)
      case conditions
      when String
        conditions
      when Hash
        conditions.map do |k, v|
          col = %("#{table}"."#{k}")
          if v.is_a?(Range)
            if v.begin.nil?
              "#{col} <= #{v.end}"
            else
              "#{col} >= #{v.begin}"
            end
          else
            "#{col} = #{literal(v)}"
          end
        end.join(" AND ")
      else
        conditions.to_s
      end
    end

    def predicates_sql
      predicates.map { |p| p[:sql] }.join(" AND ")
    end

    def only_search_predicates?
      predicates.all? { |p| p[:kind] == :search }
    end

    def where_clause
      sqls = predicates.map { |p| p[:sql] }
      return "WHERE #{sqls.first}" if sqls.size == 1

      if only_search_predicates?
        "WHERE (#{sqls.join(' AND ')})"
      elsif sqls.size <= 2
        "WHERE #{sqls.join(' AND ')}"
      else
        "WHERE #{sqls.join("\n  AND ")}"
      end
    end

    def select_sql
      sel = selects.join(", ")
      if with_facet_window && !facet_fields.nil?
        facet_selects = facet_fields.map do |field|
          json = facet_json(field, facet_opts)
          %(pdb.agg('#{json}') OVER () AS _#{field}_facet)
        end
        sel = ([sel] + facet_selects).join(", ")
      end
      "SELECT #{sel} FROM #{table}"
    end

    def order_sql
      "ORDER BY #{order_clause}"
    end

    def limit_sql
      "LIMIT #{limit_value}"
    end

    def select_add(expr)
      dup_with(selects: selects + [expr])
    end

    def dup_with(**attrs)
      self.class.new(
        model,
        predicates: attrs.fetch(:predicates, predicates),
        selects: attrs.fetch(:selects, selects),
        order_clause: attrs.fetch(:order_clause, order_clause),
        limit_value: attrs.fetch(:limit_value, limit_value),
        facet_fields: attrs.fetch(:facet_fields, facet_fields),
        facet_opts: attrs.fetch(:facet_opts, facet_opts),
        with_facet_window: attrs.fetch(:with_facet_window, with_facet_window),
        current_field: attrs.fetch(:current_field, current_field)
      )
    end

    def literal(val)
      case val
      when String then "'#{val.gsub("'", "''")}'"
      when Symbol then "'#{val}'"
      when TrueClass then "true"
      when FalseClass then "false"
      when NilClass then "NULL"
      else val.to_s
      end
    end

    def quote_ident(name)
      %("#{name}")
    end

    def primary_key
      :id
    end

    def primary_key_node
      builder[:id]
    end

    def snippet_args(args)
      return "" if args.empty?
      ", #{args.join(', ')}"
    end

    def add_facets(fields, opts)
      dup_with(facet_fields: fields, facet_opts: opts, with_facet_window: true)
    end

    def facet_json(field, opts)
      size = opts[:size] || 10
      order_opt = opts[:order]
      missing_clause = opts[:missing] ? %("missing": "#{opts[:missing]}", ) : ""
      order_clause =
        case order_opt
        when "-count" then %("order": {"_count": "desc"}, )
        when "count" then %("order": {"_count": "asc"}, )
        when nil then ""
        else ""
        end
      %({"terms": {#{missing_clause}#{order_clause}"field": "#{field}", "size": #{size}}})
    end

    # ---- Facet Query helper ----
    class FacetQuery
      attr_reader :sql

      def self.build(table, predicate_sql, fields:, size:, order:, missing:, agg:)
        new(table, predicate_sql, fields, size, order, missing, agg)
      end

      def initialize(table, predicate_sql, fields, size, order, missing, agg)
        @sql = build_sql(table, predicate_sql, fields, size, order, missing, agg)
      end

      private

      def build_sql(table, predicate_sql, fields, size, order, missing, agg)
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
        buf << "WHERE #{predicate_sql}"
        buf.join("\n")
      end
    end
  end
end
