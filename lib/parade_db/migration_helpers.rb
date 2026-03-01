# frozen_string_literal: true
require "json"
require_relative "tokenizer_sql"

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

    def add_bm25_index(table, fields:, key_field:, name: nil, index_options: nil, if_not_exists: false)
      ensure_postgresql_adapter!
      anonymous = Class.new(ParadeDB::Index)
      anonymous.table_name = table
      anonymous.key_field = key_field
      anonymous.index_name = name unless name.nil?
      anonymous.fields = fields
      anonymous.index_options = index_options unless index_options.nil?

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
      with_options_sql = bm25_with_options_sql(compiled)

      <<~SQL.strip.gsub(/\s+/, " ")
        CREATE INDEX #{prefix}#{quote_table_name(compiled.index_name)} ON #{quote_table_name(compiled.table_name)}
        USING bm25 (#{fields_sql})
        WITH (#{with_options_sql})
      SQL
    end

    def bm25_with_options_sql(compiled)
      options = []
      options << "key_field=#{quote(compiled.key_field.to_s)}"

      compiled.index_options.each do |key, value|
        case key.to_sym
        when :target_segment_count
          options << "target_segment_count=#{Integer(value)}"
        else
          raise ParadeDB::InvalidIndexDefinition, "unsupported index option #{key.inspect}"
        end
      end

      bm25_field_option_groups(compiled).each do |param_name, value_hash|
        options << "#{param_name}=#{quote(JSON.generate(value_hash))}"
      end

      options.join(", ")
    end

    def bm25_field_option_groups(compiled)
      field_options = compiled.field_options || {}
      return {} if field_options.empty?

      columns_by_name = columns(compiled.table_name.to_s).each_with_object({}) { |col, memo| memo[col.name] = col }
      grouped = {}

      field_options.each do |source, opts|
        next unless source.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

        column = columns_by_name[source.to_s]
        next unless column

        param_name = bm25_field_option_param_for_column(column)
        next if param_name.nil?

        normalized = normalize_field_options_for_param(opts, param_name)
        next if normalized.empty?

        grouped[param_name] ||= {}
        grouped[param_name][source.to_s] = normalized
      end

      grouped
    end

    def bm25_field_option_param_for_column(column)
      sql_type = column.sql_type.to_s.downcase
      return "range_fields" if sql_type.include?("range")

      case column.type
      when :json, :jsonb then "json_fields"
      when :text, :string then "text_fields"
      when :integer, :float, :decimal then "numeric_fields"
      when :boolean then "boolean_fields"
      when :datetime, :timestamp, :time, :date then "datetime_fields"
      else
        nil
      end
    end

    def normalize_field_options_for_param(options, param_name)
      symbolized = options.each_with_object({}) { |(k, v), memo| memo[k.to_sym] = v }

      case param_name
      when "text_fields"
        allowed = %i[fast record normalizer]
      when "json_fields"
        allowed = %i[fast expand_dots]
      when "numeric_fields", "boolean_fields", "datetime_fields", "range_fields"
        allowed = %i[fast]
      else
        allowed = []
      end

      symbolized.each_with_object({}) do |(key, value), memo|
        next unless allowed.include?(key)

        rendered =
          case value
          when Symbol then value.to_s
          else value
          end
        memo[key.to_s] = rendered
      end
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
      tokenizer = tokenizer.to_s.strip
      fn = ParadeDB::TokenizerSQL.qualify(tokenizer)

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
      positional = Array(opts.delete(:__positional)).map { |value| tokenizer_positional_arg_sql(value) }

      if opts.key?(:min) || opts.key?(:max)
        unless opts.key?(:min) && opts.key?(:max)
          raise ArgumentError, "tokenizer named args :min and :max must be provided together"
        end
        positional << Integer(opts.delete(:min)).to_s
        positional << Integer(opts.delete(:max)).to_s
      end

      named = opts.map do |k, v|
        quote("#{k}=#{v}")
      end

      [positional, named]
    end

    def tokenizer_positional_arg_sql(value)
      case value
      when Integer, Float
        value.to_s
      when TrueClass, FalseClass
        value ? "true" : "false"
      when NilClass
        "null"
      when Symbol
        quote(value.to_s)
      when String
        quote(value)
      else
        raise ParadeDB::InvalidIndexDefinition,
              "unsupported tokenizer positional arg type: #{value.class}"
      end
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
      index_options = extract_bm25_index_options(indexdef)
      fields_sql = extract_bm25_fields_sql(indexdef)

      if key_field && fields_sql
        field_sqls = split_bm25_top_level(fields_sql).map(&:strip)
        parsed = field_sqls.map { |f| bm25_parse_column_entry(f) }

        grouped = {}
        parsed.each { |e| (grouped[e[:source]] ||= []) << e }

        fields_pairs = grouped.map do |source, entries|
          source_ruby = source.match?(/[^a-zA-Z0-9_]/) ? "#{source.inspect} =>" : "#{source}:"

          if entries.all? { |e| e[:tokenizer].nil? }
            "#{source_ruby} {}"
          elsif entries.length == 1
            "#{source_ruby} #{bm25_tokenizer_config_ruby(entries.first)}"
          else
            configs = entries.map { |e| bm25_tokenizer_config_ruby(e) }
            "#{source_ruby} { tokenizers: [#{configs.join(', ')}] }"
          end
        end

        statement = "add_bm25_index #{table.to_sym.inspect}, " \
          "fields: { #{fields_pairs.join(', ')} }, " \
          "key_field: #{key_field.to_sym.inspect}, " \
          "name: #{name.inspect}"
        unless index_options.empty?
          statement += ", index_options: #{ruby_hash_literal(index_options)}"
        end
        statement
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

    def extract_bm25_index_options(indexdef)
      with_match = indexdef.match(/WITH\s*\((.*)\)\s*\z/im)
      return {} unless with_match

      with_sql = with_match[1]
      options = {}
      split_sql_arguments(with_sql).each do |argument|
        key, value_sql = split_assignment(argument)
        next if key.nil?
        next if key == "key_field"

        case key
        when "target_segment_count"
          parsed = parse_sql_literal(value_sql)
          if parsed.is_a?(Integer)
            options[:target_segment_count] = parsed
          elsif parsed.is_a?(String) && parsed.match?(/\A\d+\z/)
            options[:target_segment_count] = parsed.to_i
          end
        end
      end
      options
    rescue
      {}
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

    def bm25_parse_column_entry(field_sql)
      stripped = field_sql.strip

      if stripped.start_with?("(") && stripped.end_with?(")")
        inner = stripped[1..-2].strip

        if (source_sql, tok_sql = split_tokenized_cast(inner))
          normalized = unwrap_surrounding_groupings(source_sql)
          source_name = identifier_sql?(normalized) ? unquote_identifier(normalized) : normalized
          bm25_parse_tokenizer(tok_sql).merge(source: source_name)
        else
          { source: inner, tokenizer: nil, options: {} }
        end
      else
        source_name = identifier_sql?(stripped) ? unquote_identifier(stripped) : stripped
        { source: source_name, tokenizer: nil, options: {} }
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

    def bm25_parse_tokenizer(tokenizer_sql_str)
      match = tokenizer_sql_str.strip.match(/\A([a-zA-Z_][a-zA-Z0-9_]*(?:(?:::|\.)[a-zA-Z_][a-zA-Z0-9_]*)*)(?:\((.*)\))?\z/m)
      return { tokenizer: tokenizer_sql_str, options: {} } unless match

      raw_name = match[1]
      args_sql = match[2]

      normalized_name =
        if raw_name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
          raw_name
        elsif raw_name.start_with?("pdb.") && raw_name[4..].match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
          raw_name[4..]
        else
          raw_name
        end

      return { tokenizer: normalized_name, options: {} } if args_sql.nil? || args_sql.strip.empty?

      parsed_args = parse_tokenizer_arguments(split_sql_arguments(args_sql))
      return { tokenizer: normalized_name, options: {} } if parsed_args.nil?

      positional = parsed_args[:positional].dup
      named = parsed_args[:named].dup
      options = {}

      if normalized_name.end_with?("ngram") &&
         positional.length >= 2 &&
         positional[0].is_a?(Integer) &&
         positional[1].is_a?(Integer)
        options[:min] = positional.shift
        options[:max] = positional.shift
      end

      options[:__positional] = positional unless positional.empty?
      named.each { |k, v| options[k.to_sym] = v }

      { tokenizer: normalized_name, options: options }
    end

    def bm25_tokenizer_config_ruby(entry)
      opts = entry[:options].dup
      positional_args = Array(opts.delete(:__positional))
      alias_val = opts.delete(:alias)
      min_val = opts.delete(:min)
      max_val = opts.delete(:max)
      positional_args = [min_val, max_val] + positional_args if min_val && max_val

      parts = ["tokenizer: #{entry[:tokenizer].to_sym.inspect}"]
      parts << "args: #{positional_args.inspect}" unless positional_args.empty?
      parts << "alias: #{alias_val.inspect}" if alias_val

      unless opts.empty?
        named_pairs = opts.map { |k, v| "#{k.inspect} => #{v.inspect}" }.join(", ")
        parts << "named_args: { #{named_pairs} }"
      end

      "{ #{parts.join(', ')} }"
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
