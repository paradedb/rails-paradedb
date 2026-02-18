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

        if (source_sql, tokenizer_sql_str = split_tokenized_cast(inner))
          normalized_source = unwrap_surrounding_groupings(source_sql)
          source_ruby =
            if identifier_sql?(normalized_source)
              unquote_identifier(normalized_source).to_sym.inspect
            else
              normalized_source.inspect
            end

          tokenizer_spec_ruby = tokenizer_sql_to_ruby(tokenizer_sql_str)
          "{ #{source_ruby} => #{tokenizer_spec_ruby} }"
        else
          inner.inspect
        end
      else
        if identifier_sql?(stripped)
          name = unquote_identifier(stripped)
          name.to_sym.inspect
        else
          stripped.inspect
        end
      end
    end

    def split_tokenized_cast(sql)
      top_level_cast_positions(sql).reverse_each do |position|
        source = sql[0...position].strip
        tokenizer = sql[(position + 2)..].strip
        next unless tokenizer_like?(tokenizer)

        return [source, tokenizer]
      end

      nil
    end

    def top_level_cast_positions(sql)
      positions = []
      depth = 0
      in_single_quote = false
      in_double_quote = false

      i = 0
      while i < sql.length - 1
        ch = sql[i]
        nxt = sql[i + 1]

        if in_single_quote
          if ch == "'" && nxt == "'"
            i += 2
            next
          end

          in_single_quote = false if ch == "'"
          i += 1
          next
        end

        if in_double_quote
          if ch == '"' && nxt == '"'
            i += 2
            next
          end

          in_double_quote = false if ch == '"'
          i += 1
          next
        end

        case ch
        when "'"
          in_single_quote = true
        when '"'
          in_double_quote = true
        when "("
          depth += 1
        when ")"
          depth -= 1 if depth.positive?
        when ":"
          if nxt == ":" && depth.zero?
            positions << i
            i += 2
            next
          end
        end

        i += 1
      end

      positions
    end

    def tokenizer_like?(tokenizer_sql)
      return false if tokenizer_sql.empty?

      tokenizer_sql.match?(ParadeDB::Index::TokenizerParser::TOKENIZER_EXPRESSION)
    rescue NameError
      tokenizer_sql.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*(?:(?:::|\.)[a-zA-Z_][a-zA-Z0-9_]*)*(?:\(\s*[a-zA-Z0-9_'".,=\s:-]*\s*\))?\z/)
    end

    def unwrap_surrounding_groupings(sql)
      value = sql.strip
      while wrapped_by_grouping?(value)
        value = value[1..-2].strip
      end
      value
    end

    def wrapped_by_grouping?(sql)
      return false unless sql.start_with?("(") && sql.end_with?(")")

      depth = 0
      in_single_quote = false
      in_double_quote = false

      i = 0
      while i < sql.length
        ch = sql[i]
        nxt = i + 1 < sql.length ? sql[i + 1] : nil

        if in_single_quote
          if ch == "'" && nxt == "'"
            i += 2
            next
          end

          in_single_quote = false if ch == "'"
          i += 1
          next
        end

        if in_double_quote
          if ch == '"' && nxt == '"'
            i += 2
            next
          end

          in_double_quote = false if ch == '"'
          i += 1
          next
        end

        case ch
        when "'"
          in_single_quote = true
        when '"'
          in_double_quote = true
        when "("
          depth += 1
        when ")"
          depth -= 1
          return false if depth.zero? && i < sql.length - 1
        end

        i += 1
      end

      depth.zero?
    end

    def identifier_sql?(sql)
      sql.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) || sql.match?(/\A"(?:[^"]|"")+"\z/)
    end

    def tokenizer_sql_to_ruby(tokenizer_sql)
      match = tokenizer_sql.strip.match(/\A([a-zA-Z_][a-zA-Z0-9_]*(?:(?:::|\.)[a-zA-Z_][a-zA-Z0-9_]*)*)(?:\((.*)\))?\z/m)
      return tokenizer_sql.inspect unless match

      tokenizer_name = match[1]
      args_sql = match[2]
      tokenizer_name_ruby = tokenizer_name_to_ruby(tokenizer_name)
      return tokenizer_name_ruby if args_sql.nil? || args_sql.strip.empty?

      parsed_args = parse_tokenizer_arguments(split_sql_arguments(args_sql))
      return tokenizer_sql.inspect if parsed_args.nil?

      positional = parsed_args[:positional].dup
      named = parsed_args[:named].dup
      options = {}

      if tokenizer_name.end_with?("ngram") &&
         positional.length >= 2 &&
         positional[0].is_a?(Integer) &&
         positional[1].is_a?(Integer)
        options[:min] = positional.shift
        options[:max] = positional.shift
      end

      options[:__positional] = positional unless positional.empty?
      named.each { |k, v| options[k.to_sym] = v }

      return tokenizer_name_ruby if options.empty?

      "{ #{tokenizer_name_ruby} => #{ruby_hash_literal(options)} }"
    end

    def tokenizer_name_to_ruby(tokenizer_name)
      if tokenizer_name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
        tokenizer_name.to_sym.inspect
      elsif tokenizer_name.start_with?("pdb.") && tokenizer_name[4..].match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
        tokenizer_name[4..].to_sym.inspect
      else
        tokenizer_name.inspect
      end
    end

    def split_sql_arguments(args_sql)
      parts = []
      current = +""
      depth = 0
      in_single_quote = false
      in_double_quote = false

      i = 0
      while i < args_sql.length
        ch = args_sql[i]
        nxt = i + 1 < args_sql.length ? args_sql[i + 1] : nil

        if in_single_quote
          current << ch
          if ch == "'" && nxt == "'"
            current << nxt
            i += 2
            next
          end

          in_single_quote = false if ch == "'"
          i += 1
          next
        end

        if in_double_quote
          current << ch
          if ch == '"' && nxt == '"'
            current << nxt
            i += 2
            next
          end

          in_double_quote = false if ch == '"'
          i += 1
          next
        end

        case ch
        when "'"
          in_single_quote = true
          current << ch
        when '"'
          in_double_quote = true
          current << ch
        when "("
          depth += 1
          current << ch
        when ")"
          depth -= 1 if depth.positive?
          current << ch
        when ","
          if depth.zero?
            parts << current.strip unless current.strip.empty?
            current = +""
          else
            current << ch
          end
        else
          current << ch
        end

        i += 1
      end

      parts << current.strip unless current.strip.empty?
      parts
    end

    def parse_tokenizer_arguments(arguments)
      positional = []
      named = {}

      arguments.each do |argument|
        key, value = split_assignment(argument)
        if key
          named[key] = parse_sql_literal(value)
          next
        end

        literal = parse_sql_literal(argument)
        if literal.is_a?(String) && literal.include?("=")
          config_parts = literal.split(",").map(&:strip).reject(&:empty?)
          parsed_all = config_parts.all? { |part| split_assignment(part).is_a?(Array) }
          if parsed_all
            config_parts.each do |part|
              config_key, config_value = split_assignment(part)
              named[config_key] = parse_sql_literal(config_value)
            end
            next
          end
        end

        positional << literal
      end

      { positional: positional, named: named }
    rescue
      nil
    end

    def split_assignment(argument)
      match = argument.strip.match(/\A([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)\z/m)
      return nil unless match

      [match[1], match[2]]
    end

    def parse_sql_literal(value_sql)
      value = value_sql.strip
      return value[1..-2].gsub("''", "'") if value.start_with?("'") && value.end_with?("'")
      return value[1..-2].gsub('""', '"') if value.start_with?('"') && value.end_with?('"')
      return true if value.casecmp("true").zero?
      return false if value.casecmp("false").zero?
      return nil if value.casecmp("null").zero?
      return Integer(value, 10) if value.match?(/\A[-+]?\d+\z/)
      return Float(value) if value.match?(/\A[-+]?\d+\.\d+\z/)

      value
    end

    def ruby_hash_literal(hash)
      pairs = hash.map { |k, v| "#{k.inspect} => #{ruby_literal(v)}" }
      "{ #{pairs.join(', ')} }"
    end

    def ruby_literal(value)
      case value
      when Array
        "[#{value.map { |item| ruby_literal(item) }.join(', ')}]"
      when Hash
        ruby_hash_literal(value)
      else
        value.inspect
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
