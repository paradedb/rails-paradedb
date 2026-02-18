# frozen_string_literal: true

module ParadeDB
  module MigrationHelpers
    def create_paradedb_index(index_klass, if_not_exists: false)
      ensure_postgresql_adapter!
      resolved = resolve_index_klass(index_klass)
      compiled = resolved.compiled_definition
      execute(build_create_sql(compiled, if_not_exists: if_not_exists))
      remember_schema_index_reference(resolved)
    end

    def replace_paradedb_index(index_klass)
      ensure_postgresql_adapter!
      resolved = resolve_index_klass(index_klass)
      compiled = resolved.compiled_definition
      remove_bm25_index(compiled.table_name, name: compiled.index_name, if_exists: true)
      execute(build_create_sql(compiled, if_not_exists: false))
      remember_schema_index_reference(resolved)
    end

    def add_bm25_index(table, fields:, key_field:, name: nil, if_not_exists: false)
      ensure_postgresql_adapter!
      anonymous = Class.new(ParadeDB::Index)
      anonymous.table_name = table
      anonymous.key_field = key_field
      anonymous.index_name = name unless name.nil?
      anonymous.fields = fields

      create_paradedb_index(anonymous, if_not_exists: if_not_exists)
    end

    def remove_bm25_index(table, name: nil, if_exists: false)
      ensure_postgresql_adapter!
      index_name = (name || "#{table}_bm25_idx").to_s
      prefix = if_exists ? "IF EXISTS " : ""
      execute("DROP INDEX #{prefix}#{quote_table_name(index_name)}")
    end

    def reindex_bm25(table, name: nil, concurrently: false)
      ensure_postgresql_adapter!
      if concurrently && transaction_open_for_paradedb?
        raise ArgumentError, "reindex_bm25 concurrently: true cannot run inside a transaction"
      end

      index_name = (name || "#{table}_bm25_idx").to_s
      modifier = concurrently ? " CONCURRENTLY" : ""
      execute("REINDEX INDEX#{modifier} #{quote_table_name(index_name)}")
    end

    def dump_paradedb_indexes(stream)
      rows = paradedb_bm25_index_rows
      return if rows.empty?

      stream.puts
      rows.each do |row|
        ruby_stmt = bm25_index_to_ruby(row)
        stream.puts "  #{ruby_stmt}"
      end
    end

    def paradedb_schema_index_references
      (@paradedb_schema_index_references || []).uniq.sort
    end

    def paradedb_bm25_index_names
      paradedb_bm25_index_rows.map { |r| r["index_name"] }
    end

    private

    def ensure_postgresql_adapter!
      ParadeDB.ensure_postgresql_adapter!(self, context: "ParadeDB migration helper")
    end

    def build_create_sql(compiled, if_not_exists:)
      prefix = if_not_exists ? "IF NOT EXISTS " : ""
      fields_sql = compiled.entries.map { |entry| bm25_entry_sql(entry) }.join(", ")
      escaped_key_field = quote_string(compiled.key_field.to_s)

      <<~SQL.strip.gsub(/\s+/, " ")
        CREATE INDEX #{prefix}#{quote_table_name(compiled.index_name)} ON #{quote_table_name(compiled.table_name)}
        USING bm25 (#{fields_sql})
        WITH (key_field='#{escaped_key_field}')
      SQL
    end

    def bm25_entry_sql(entry)
      source_sql = bm25_source_sql(entry)
      return source_sql if entry.tokenizer.nil?

      "(#{source_sql}::#{tokenizer_sql(entry.tokenizer, entry.options)})"
    end

    def bm25_source_sql(entry)
      if entry.expression
        "(#{entry.source})"
      else
        quote_column_name(entry.source)
      end
    end

    def tokenizer_sql(tokenizer, options)
      fn =
        if tokenizer.include?("::") || tokenizer.include?(".") || tokenizer.include?("(")
          tokenizer
        else
          "pdb.#{tokenizer}"
        end

      if tokenizer.include?("(")
        unless options.empty?
          raise ArgumentError, "tokenizer options cannot be combined with inline tokenizer arguments"
        end
        return fn
      end

      return fn if options.empty?

      positional, named = tokenizer_args(options)
      args = positional + named
      "#{fn}(#{args.join(', ')})"
    end

    def tokenizer_args(options)
      opts = options.dup
      positional = Array(opts.delete(:__positional)).map(&:to_s)

      if opts.key?(:min) || opts.key?(:max)
        if opts.key?(:min) && opts.key?(:max)
          positional << Integer(opts.delete(:min)).to_s
          positional << Integer(opts.delete(:max)).to_s
        end
      end

      named = opts.map do |k, v|
        quote("#{k}=#{v}")
      end

      [positional, named]
    end

    def resolve_index_klass(index_klass)
      case index_klass
      when String
        resolve_named_constant(index_klass)
      else
        index_klass
      end
    end

    def resolve_named_constant(name)
      name.to_s.split("::").inject(Object) { |ctx, const_name| ctx.const_get(const_name) }
    rescue NameError
      raise ParadeDB::InvalidIndexDefinition, "Unknown index class #{name.inspect}"
    end

    def remember_schema_index_reference(index_klass)
      return unless index_klass.respond_to?(:name)

      klass_name = index_klass.name
      return if klass_name.nil? || klass_name.empty?

      @paradedb_schema_index_references ||= []
      @paradedb_schema_index_references << klass_name
    end

    def transaction_open_for_paradedb?
      return transaction_open? if respond_to?(:transaction_open?)
      return open_transactions.to_i.positive? if respond_to?(:open_transactions)

      false
    end

    def paradedb_bm25_index_rows
      sql = <<~SQL
        SELECT
          c.relname  AS index_name,
          t.relname  AS table_name,
          pg_get_indexdef(c.oid) AS indexdef
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_index i ON i.indexrelid = c.oid
        JOIN pg_class t ON t.oid = i.indrelid
        JOIN pg_am am ON am.oid = c.relam
        WHERE n.nspname = current_schema()
          AND am.amname = 'bm25'
        ORDER BY t.relname, c.relname
      SQL
      select_all(sql).to_a
    rescue => e
      Kernel.warn("ParadeDB: unable to query bm25 indexes from catalog: #{e.message}")
      []
    end

    def bm25_index_to_ruby(row)
      indexdef = row["indexdef"]
      table = row["table_name"]
      name = row["index_name"]

      key_field = extract_bm25_key_field(indexdef)
      fields_sql = extract_bm25_fields_sql(indexdef)

      if key_field && fields_sql
        field_names = split_bm25_top_level(fields_sql).map { |f| f.strip }
        fields_ruby = field_names.map { |f| bm25_field_to_ruby(f) }
        "add_bm25_index #{table.to_sym.inspect}, " \
          "fields: [#{fields_ruby.join(', ')}], " \
          "key_field: #{key_field.to_sym.inspect}, " \
          "name: #{name.inspect}"
      else
        "execute #{indexdef.inspect}"
      end
    end

    def extract_bm25_key_field(indexdef)
      quoted = indexdef.match(/WITH\s*\([^)]*key_field\s*=\s*'((?:[^']|'')*)'/i)
      return quoted[1].gsub("''", "'") if quoted

      unquoted = indexdef.match(/WITH\s*\([^)]*key_field\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/i)
      return unquoted[1] if unquoted

      nil
    end

    def extract_bm25_fields_sql(indexdef)
      match = indexdef.match(/USING\s+bm25\s*\(/im)
      return nil unless match

      start = match.end(0)
      depth = 1
      pos = start
      while pos < indexdef.length && depth > 0
        case indexdef[pos]
        when "(" then depth += 1
        when ")" then depth -= 1
        end
        pos += 1
      end
      return nil if depth != 0

      indexdef[start..pos - 2]
    end

    def split_bm25_top_level(str)
      parts = []
      current = +""
      depth = 0
      str.each_char do |ch|
        case ch
        when "(" then depth += 1; current << ch
        when ")" then depth -= 1; current << ch
        when ","
          if depth == 0
            parts << current
            current = +""
          else
            current << ch
          end
        else
          current << ch
        end
      end
      parts << current unless current.strip.empty?
      parts
    end

    def bm25_field_to_ruby(field_sql)
      stripped = field_sql.strip

      if stripped.start_with?("(") && stripped.end_with?(")")
        inner = stripped[1..-2].strip

        if (cast_match = inner.match(/\A(.+?)::(.*)\z/m))
          source_sql = cast_match[1].strip
          tokenizer_sql_str = cast_match[2].strip

          source_sql = source_sql[1..-2].strip if source_sql.start_with?("(") && source_sql.end_with?(")")

          source = unquote_identifier(source_sql)
          "{ #{source.to_sym.inspect} => #{tokenizer_sql_str.inspect} }"
        else
          inner.inspect
        end
      else
        name = unquote_identifier(stripped)
        name.to_sym.inspect
      end
    end

    def unquote_identifier(str)
      if str.start_with?('"') && str.end_with?('"')
        str[1..-2].gsub('""', '"')
      else
        str
      end
    end
  end
end

if defined?(ActiveRecord::ConnectionAdapters::AbstractAdapter)
  ActiveRecord::ConnectionAdapters::AbstractAdapter.include(ParadeDB::MigrationHelpers)
end

if defined?(ActiveRecord::SchemaDumper)
  module ParadeDB
    module SchemaDumperPatch
      def tables(stream)
        super
        paradedb_connection&.dump_paradedb_indexes(stream)
      end

      private

      def indexes_in_create(table, stream)
        conn = paradedb_connection
        if conn
          bm25_names = conn.paradedb_bm25_index_names
          original_indexes = conn.method(:indexes)

          conn.define_singleton_method(:indexes) do |tbl|
            original_indexes.call(tbl).reject { |idx| bm25_names.include?(idx.name) }
          end

          begin
            super
          ensure
            conn.define_singleton_method(:indexes, original_indexes)
          end
        else
          super
        end
      end

      def paradedb_connection
        if instance_variable_defined?(:@connection)
          conn = instance_variable_get(:@connection)
          return conn if conn.respond_to?(:dump_paradedb_indexes)
        end
        nil
      end
    end
  end

  ActiveRecord::SchemaDumper.prepend(ParadeDB::SchemaDumperPatch)
end
