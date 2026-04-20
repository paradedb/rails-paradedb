# frozen_string_literal: true

require_relative "tokenizer"

module ParadeDB
  class Index
    class << self
      attr_writer :table_name, :key_field, :index_name, :fields, :index_options, :where

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
        @fields || {}
      end

      def index_options
        @index_options || {}
      end

      def where
        @where
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

    class TokenizerParser
      TOKENIZER_EXPRESSION = /\A[a-zA-Z_][a-zA-Z0-9_]*(?:(?:::|\.)[a-zA-Z_][a-zA-Z0-9_]*)*(?:\(\s*[a-zA-Z0-9_'".,=\s:-]*\s*\))?\z/.freeze
      TOKENIZER_SINGLE_KEYS = %i[tokenizer alias].freeze

      class << self
        def parse(source_name, tokenizer, context:)
          unless tokenizer.is_a?(Tokenizer)
            raise InvalidIndexDefinition, "#{context} for #{source_name.inspect} must be a Tokenizer"
          end

          options = {}
          options[:__positional] = tokenizer.positional_args.dup unless tokenizer.positional_args.nil?
          tokenizer.options&.each { |key, value| options[key.to_sym] = value }

          key = options[:alias]&.to_s || source_name
          DefinitionCompiler::Entry.new(
            source: source_name,
            expression: expression?(source_name),
            tokenizer: tokenizer.name,
            options: options,
            query_key: key
          )
        end

        private

        def expression?(value)
          value.match?(/[^a-zA-Z0-9_]/)
        end
      end
    end

    # Consumed by migration helpers; validates and normalizes the DSL class
    class DefinitionCompiler
      FIELD_OPTION_KEYS = %i[fast record normalizer expand_dots].freeze

      class Compiled
        attr_reader :table_name, :key_field, :index_name, :entries, :index_options, :field_options, :where

        def initialize(table_name:, key_field:, index_name:, entries:, index_options:, field_options:, where:)
          @table_name = table_name
          @key_field = key_field
          @index_name = index_name
          @entries = entries
          @index_options = index_options
          @field_options = field_options
          @where = where
        end
      end
      Entry = Struct.new(:source, :expression, :tokenizer, :options, :query_key, keyword_init: true)

      class << self
        def compile!(klass)
          table_name = require_symbol!(klass.table_name, "table_name")
          key_field = require_symbol!(klass.key_field, "key_field")
          index_name = klass.index_name.to_s
          raise InvalidIndexDefinition, "index_name must be present" if index_name.strip.empty?

          raw_fields = klass.fields
          entries, field_options = build_entries(raw_fields)
          if entries.empty?
            raise InvalidIndexDefinition, "fields must include at least one indexed field"
          end

          index_options = normalize_index_options(klass.index_options)

          validate_key_field_shape!(key_field.to_s, entries)
          validate_query_key_collisions!(entries)

          Compiled.new(
            table_name: table_name,
            key_field: key_field,
            index_name: index_name,
            entries: entries,
            index_options: index_options,
            field_options: field_options,
            where: klass.where
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
          unless raw_fields.is_a?(Hash)
            raise InvalidIndexDefinition, "fields must be a Hash"
          end

          entries = []
          field_options = {}

          raw_fields.each do |source, config|
            source_name = source.to_s
            unless config.nil? || config.is_a?(Hash)
              raise InvalidIndexDefinition, "field config for #{source_name.inspect} must be a Hash"
            end
            normalized = (config || {}).each_with_object({}) { |(k, v), memo| memo[k.to_sym] = v }

            unknown_keys = normalized.keys - (TokenizerParser::TOKENIZER_SINGLE_KEYS + [:tokenizers] + FIELD_OPTION_KEYS)
            unless unknown_keys.empty?
              raise InvalidIndexDefinition,
                    "unknown field config keys for #{source_name.inspect}: #{unknown_keys.map(&:inspect).join(', ')}"
            end

            tokenizers = normalized[:tokenizers]
            single_tokenizer_keys_present = TokenizerParser::TOKENIZER_SINGLE_KEYS.any? { |key| normalized.key?(key) }

            is_alias = normalized[:alias] && normalized.length == 1
            if is_alias
              entries << Entry.new(
                source: source_name,
                expression: expression?(source_name),
                tokenizer: nil,
                options: {},
                query_key: normalized[:alias]
              )
            elsif tokenizers
              if single_tokenizer_keys_present
                raise InvalidIndexDefinition,
                      "field #{source_name.inspect} cannot mix :tokenizers with :tokenizer/:alias"
              end
              unless tokenizers.respond_to?(:to_ary) && !tokenizers.to_ary.empty?
                raise InvalidIndexDefinition, "field #{source_name.inspect} :tokenizers must be a non-empty Array"
              end

              tokenizers.to_ary.each_with_index do |tokenizer_config, idx|
                entry = TokenizerParser.parse(source_name, tokenizer_config, context: "tokenizers[#{idx}]")
                entries << entry
              end
            elsif normalized.key?(:tokenizer)
              entry = TokenizerParser.parse(source_name, normalized[:tokenizer], context: "tokenizer")
              entries << entry
            elsif single_tokenizer_keys_present
              raise InvalidIndexDefinition,
                    "field #{source_name.inspect} specifies tokenizer configuration but no :tokenizer"
            else
              entries << Entry.new(
                source: source_name,
                expression: expression?(source_name),
                tokenizer: nil,
                options: {},
                query_key: source_name
              )
            end

            field_opts = select_keys(normalized, FIELD_OPTION_KEYS)
            field_options[source_name] = field_opts unless field_opts.empty?
          end

          [entries, field_options]
        end

        def normalize_index_options(raw_options)
          return {} if raw_options.nil?
          unless raw_options.is_a?(Hash)
            raise InvalidIndexDefinition, "index_options must be a Hash"
          end

          normalized = raw_options.each_with_object({}) do |(key, value), memo|
            memo[key.to_sym] = value
          end

          unknown = normalized.keys - [:target_segment_count]
          unless unknown.empty?
            raise InvalidIndexDefinition,
                  "unknown index_options keys: #{unknown.map(&:inspect).join(', ')}"
          end

          if normalized.key?(:target_segment_count)
            target = normalized[:target_segment_count]
            unless target.is_a?(Integer) && target.positive?
              raise InvalidIndexDefinition, "index_options[:target_segment_count] must be an Integer > 0"
            end
          end

          normalized
        end

        def select_keys(hash, keys)
          keys.each_with_object({}) do |key, memo|
            memo[key] = hash[key] if hash.key?(key)
          end
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
