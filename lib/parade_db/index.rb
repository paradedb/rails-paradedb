# frozen_string_literal: true

module ParadeDB
  class InvalidIndexDefinition < ArgumentError; end

  class Index
    class << self
      attr_writer :table_name, :key_field, :index_name, :fields

      def table_name
        @table_name
      end

      def key_field
        @key_field
      end

      def index_name
        @index_name || default_index_name
      end

      def fields
        @fields || []
      end

      def default_index_name
        return nil if table_name.nil?

        "#{table_name}_bm25_idx"
      end

      def compiled_definition
        DefinitionCompiler.compile!(self)
      end

      def validate!
        compiled_definition
        true
      end
    end

    # Consumed by migration helpers; validates and normalizes the DSL class
    class DefinitionCompiler
      TOKENIZER_EXPRESSION = /\A[a-zA-Z_][a-zA-Z0-9_]*(?:(?:::|\.)[a-zA-Z_][a-zA-Z0-9_]*)*(?:\(\s*[a-zA-Z0-9_'".,\s]*\s*\))?\z/.freeze
      Compiled = Struct.new(:table_name, :key_field, :index_name, :entries, keyword_init: true)
      Entry = Struct.new(:source, :expression, :tokenizer, :options, :query_key, keyword_init: true)

      class << self
        def compile!(klass)
          table_name = require_symbol!(klass.table_name, "table_name")
          key_field = require_symbol!(klass.key_field, "key_field")
          index_name = klass.index_name.to_s
          raise InvalidIndexDefinition, "index_name must be present" if index_name.strip.empty?

          raw_fields = klass.fields
          unless raw_fields.respond_to?(:to_ary)
            raise InvalidIndexDefinition, "fields must be an Array"
          end

          entries = build_entries(raw_fields.to_ary)
          if entries.empty?
            raise InvalidIndexDefinition, "fields must include at least one indexed field"
          end

          validate_key_field_shape!(key_field.to_s, entries)
          validate_query_key_collisions!(entries)

          Compiled.new(
            table_name: table_name,
            key_field: key_field,
            index_name: index_name,
            entries: entries
          )
        end

        private

        def require_symbol!(value, name)
          case value
          when String then value.to_sym
          when Symbol then value
          else
            raise InvalidIndexDefinition, "#{name} must be a Symbol or String"
          end
        end

        def build_entries(raw_fields)
          entries = []
          raw_fields.each do |entry|
            case entry
            when Symbol, String
              field = entry.to_s
              entries << Entry.new(source: field, expression: expression?(field), tokenizer: nil, options: {}, query_key: field)
            when Hash
              unless entry.size == 1
                raise InvalidIndexDefinition, "field hash entries must have exactly one key"
              end

              source, tokenizer_spec = entry.first
              source_name = source.to_s
              entries.concat(expand_tokenizer_entries(source_name, tokenizer_spec))
            else
              raise InvalidIndexDefinition, "unsupported field entry type: #{entry.class}"
            end
          end
          entries
        end

        def expand_tokenizer_entries(source_name, tokenizer_spec)
          case tokenizer_spec
          when Symbol, String
            [build_tokenized_entry(source_name, tokenizer_spec.to_s, {})]
          when Hash
            tokenizer_spec.map do |tokenizer, opts|
              case opts
              when Hash
                build_tokenized_entry(source_name, tokenizer.to_s, normalize_options(opts))
              when Symbol, String
                build_tokenized_entry(source_name, tokenizer.to_s, normalize_positional_option(opts))
              else
                raise InvalidIndexDefinition,
                      "tokenizer options for #{source_name}.#{tokenizer} must be a Hash, Symbol, or String"
              end
            end
          else
            raise InvalidIndexDefinition,
                  "invalid tokenizer definition for #{source_name}: #{tokenizer_spec.inspect}"
          end
        end

        def normalize_options(opts)
          opts.each_with_object({}) do |(key, value), memo|
            memo[key.to_sym] = value
          end
        end

        def normalize_positional_option(option)
          { __positional: [option.to_s] }
        end

        def build_tokenized_entry(source_name, tokenizer, options)
          validate_tokenizer_name!(source_name, tokenizer) unless tokenizer.nil?
          key = options[:alias]&.to_s || source_name
          Entry.new(
            source: source_name,
            expression: expression?(source_name),
            tokenizer: tokenizer,
            options: options,
            query_key: key
          )
        end

        def validate_tokenizer_name!(source_name, tokenizer)
          return if TOKENIZER_EXPRESSION.match?(tokenizer)

          raise InvalidIndexDefinition,
                "invalid tokenizer name #{tokenizer.inspect} for #{source_name}. " \
                "Expected identifier form like simple, pdb::simple, or pdb::ngram(2, 5)."
        end

        def expression?(value)
          value.match?(/[^a-zA-Z0-9_]/)
        end

        def validate_query_key_collisions!(entries)
          grouped = entries.group_by(&:query_key)
          grouped.each do |query_key, conflicting|
            next if conflicting.size == 1

            conflict_sources = conflicting.map { |e| "#{e.source}(#{e.tokenizer || 'raw'})" }.join(", ")
            raise InvalidIndexDefinition,
                  "ambiguous index definition for query key #{query_key.inspect}: #{conflict_sources}. " \
                  "Use unique alias values to disambiguate."
          end
        end

        def validate_key_field_shape!(key_field_name, entries)
          unless entries.any? { |entry| entry.source == key_field_name }
            raise InvalidIndexDefinition,
                  "key_field #{key_field_name.inspect} must be present in fields."
          end

          first_entry = entries.first
          unless first_entry.source == key_field_name
            raise InvalidIndexDefinition,
                  "key_field #{key_field_name.inspect} must be first in fields."
          end

          return if first_entry.tokenizer.nil?

          raise InvalidIndexDefinition,
                "key_field #{key_field_name.inspect} must not be tokenized."
        end
      end
    end
  end
end
