# frozen_string_literal: true

module ParadeDB
  module Arel
    module Visitor
      module PostgreSQLExtensions
        def visit_ParadeDB_Arel_Nodes_BoostCast(o, collector)
          collector = visit(o.expr, collector)
          collector << "::pdb.boost("
          collector = visit(o.factor, collector)
          collector << ")"
        end

        def visit_ParadeDB_Arel_Nodes_ConstCast(o, collector)
          collector = visit(o.expr, collector)
          collector << "::pdb.const("
          collector = visit(o.score, collector)
          collector << ")"
        end

        def visit_ParadeDB_Arel_Nodes_SlopCast(o, collector)
          collector = visit(o.expr, collector)
          collector << "::pdb.slop("
          collector = visit(o.distance, collector)
          collector << ")"
        end

        def visit_ParadeDB_Arel_Nodes_QueryCast(o, collector)
          collector = visit(o.expr, collector)
          collector << "::pdb.query"
        end

        def visit_ParadeDB_Arel_Nodes_FuzzyCast(o, collector)
          collector = visit(o.expr, collector)
          collector << "::pdb.fuzzy("
          collector = visit(o.distance, collector)

          if o.transposition_cost_one
            collector << ", "
            collector << (o.prefix ? '"true"' : '"false"')
            collector << ", "
            collector << '"true"'
          elsif o.prefix
            collector << ', "true"'
          end

          collector << ")"
        end

        def visit_ParadeDB_Arel_Nodes_ArrayLiteral(o, collector)
          collector << "ARRAY["
          o.values.each_with_index do |value, idx|
            collector << ", " if idx.positive?
            collector = visit(value, collector)
          end
          collector << "]"
        end

        def visit_ParadeDB_Arel_Nodes_ParseNode(o, collector)
          collector << "pdb.parse("
          collector = visit(o.query, collector)

          unless o.lenient.nil?
            collector << ", lenient => "
            collector << (o.lenient ? "true" : "false")
          end

          unless o.conjunction_mode.nil?
            collector << ", conjunction_mode => "
            collector << (o.conjunction_mode ? "true" : "false")
          end

          collector << ")"
        end
      end

      module_function

      def install!
        klass = ::Arel::Visitors::PostgreSQL
        return if klass.ancestors.include?(PostgreSQLExtensions)

        klass.prepend(PostgreSQLExtensions)
      end
    end
  end
end
