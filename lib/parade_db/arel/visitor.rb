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

        def visit_ParadeDB_Arel_Nodes_SlopCast(o, collector)
          collector = visit(o.expr, collector)
          collector << "::pdb.slop("
          collector = visit(o.distance, collector)
          collector << ")"
        end

        def visit_ParadeDB_Arel_Nodes_FuzzyCast(o, collector)
          collector = visit(o.expr, collector)
          collector << "::pdb.fuzzy("
          collector = visit(o.distance, collector)
          collector << ', "true"' if o.prefix
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
