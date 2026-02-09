# frozen_string_literal: true

module ParadeDB
  module MigrationHelpers
    def create_paradedb_index(index_klass, if_not_exists: false)
      ensure_postgresql_adapter!
      compiled = index_klass.compiled_definition
      execute(build_create_sql(compiled, if_not_exists: if_not_exists))
    end

    def replace_paradedb_index(index_klass)
      ensure_postgresql_adapter!
      compiled = index_klass.compiled_definition
      remove_bm25_index(compiled.table_name, name: compiled.index_name, if_exists: true)
      execute(build_create_sql(compiled, if_not_exists: false))
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

    private

    def ensure_postgresql_adapter!
      ParadeDB.ensure_postgresql_adapter!(self, context: "ParadeDB migration helper")
    end

    def build_create_sql(compiled, if_not_exists:)
      prefix = if_not_exists ? "IF NOT EXISTS " : ""
      fields_sql = compiled.entries.map { |entry| bm25_entry_sql(entry) }.join(", ")

      <<~SQL.strip.gsub(/\s+/, " ")
        CREATE INDEX #{prefix}#{quote_table_name(compiled.index_name)} ON #{quote_table_name(compiled.table_name)}
        USING bm25 (#{fields_sql})
        WITH (key_field='#{compiled.key_field}')
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
  end
end

if defined?(ActiveRecord::ConnectionAdapters::AbstractAdapter)
  ActiveRecord::ConnectionAdapters::AbstractAdapter.include(ParadeDB::MigrationHelpers)
end
