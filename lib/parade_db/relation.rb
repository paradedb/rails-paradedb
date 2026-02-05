# frozen_string_literal: true

require "active_record"

module ParadeDB
  class Relation
    attr_reader :model, :relation, :builder, :predicates, :current_field, :facet_fields, :facet_opts, :with_facet_window

    def initialize(model, relation: nil, predicates: [], current_field: nil, facet_fields: nil, facet_opts: {}, with_facet_window: false)
      @model = model
      @relation = relation || base_relation
      @builder = model.parade_arel
      @predicates = predicates # array of {sql:, kind:}
      @current_field = current_field
      @facet_fields = facet_fields
      @facet_opts = facet_opts
      @with_facet_window = with_facet_window
    end

    # ---- ParadeDB search entrypoints ----

    def search(column)
      dup_with(current_field: column)
    end

    def matching_all(*terms, boost: nil)
      chain_with(builder.match(current_field, *terms, boost: boost), kind: :search)
    end

    def matching_any(*terms)
      chain_with(builder.match_any(current_field, *terms), kind: :search)
    end

    def excluding(*terms)
      neg = builder.match(current_field, *terms)
      chain_with(neg.not, kind: :search)
    end

    def phrase(text, slop: nil)
      chain_with(builder.phrase(current_field, text, slop: slop), kind: :search)
    end

    def fuzzy(term, distance:, prefix: nil, boost: nil)
      chain_with(builder.fuzzy(current_field, term, distance: distance, prefix: prefix, boost: boost), kind: :search)
    end

    def regex(pattern)
      chain_with(builder.regex(current_field, pattern), kind: :search)
    end

    def term(value, boost: nil)
      chain_with(builder.term(current_field, value, boost: boost), kind: :search)
    end

    def near(left_term, right_term, distance: 1)
      chain_with(builder.near(current_field, left_term, right_term, distance: distance), kind: :search)
    end

    def phrase_prefix(*terms)
      chain_with(builder.phrase_prefix(current_field, *terms), kind: :search)
    end

    def more_like_this(key, fields: nil)
      predicate = builder.more_like_this(primary_key_node, key, fields: fields)
      chain_with(predicate, kind: :search)
    end

    # ---- Decorators ----

    def with_score
      sql = %(pdb.score("#{table}"."#{primary_key}") AS search_score)
      dup_with(relation: relation.except(:select).select(Arel.sql("#{table}.*"), Arel.sql(sql)))
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
      dup_with(relation: relation.except(:select).select(Arel.sql("#{table}.*"), Arel.sql("#{call} AS #{column}_snippet")))
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
      dup_with(relation: relation.order(Arel.sql(new_clause)))
    end

    def limit(value)
      dup_with(relation: relation.limit(value))
    end

    def select(*columns)
      cols = columns.map { |c| Arel.sql(c.to_s) }
      dup_with(relation: relation.select(*cols))
    end

    def or(other)
      combined = "((#{predicates_sql}) OR (#{other.send(:predicates_sql)}))"
      dup_with(
        relation: base_relation.where(Arel.sql(combined)),
        predicates: [{ sql: combined, kind: :search }]
      )
    end

    # ---- Rendering ----

    def to_sql
      relation.to_sql
    end

    def sql
      to_sql
    end

    private

    def chain_with(node_or_string, kind:)
      pred_sql =
        case node_or_string
        when String then node_or_string
        else
          ParadeDB::Arel.to_sql(node_or_string)
        end

      new_relation = relation.where(Arel.sql(pred_sql))
      dup_with(relation: new_relation, predicates: predicates + [{ sql: pred_sql, kind: kind }])
    end

    def predicate_from_where(conditions)
      case conditions
      when String
        conditions
      when Hash
        conditions.map do |k, v|
          col = %("#{table}"."#{k}")
          if v.is_a?(Range)
            range_conditions = []
            range_conditions << "#{col} >= #{literal(v.begin)}" if v.begin
            if v.end
              op = v.exclude_end? ? "<" : "<="
              range_conditions << "#{col} #{op} #{literal(v.end)}"
            end
            range_conditions.join(" AND ")
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

    def dup_with(relation: self.relation, predicates: self.predicates, current_field: self.current_field, facet_fields: self.facet_fields, facet_opts: self.facet_opts, with_facet_window: self.with_facet_window)
      new_relation = relation
      if with_facet_window && facet_fields
        facet_selects = facet_fields.map do |field|
          json = facet_json(field, facet_opts)
          Arel.sql(%(pdb.agg('#{json}') OVER () AS _#{field}_facet))
        end
        new_relation = new_relation.select(*facet_selects)
      end

      self.class.new(
        model,
        relation: new_relation,
        predicates: predicates,
        current_field: current_field,
        facet_fields: facet_fields,
        facet_opts: facet_opts,
        with_facet_window: with_facet_window
      )
    end

    def base_relation
      model.unscoped.select(Arel.sql("#{table}.*")).from(Arel.sql(table))
    end

    def table
      model.table_name
    end

    def primary_key
      :id
    end

    def primary_key_node
      builder[:id]
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
