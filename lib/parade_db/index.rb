# frozen_string_literal: true

module ParadeDB
  class Index
    class << self
      attr_writer :table_name, :key_field, :index_name, :fields, :index_options

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
      TOKENIZER_SINGLE_KEYS = %i[tokenizer args named_args filters stemmer alias].freeze

      class << self
        def parse(source_name, tokenizer_spec)
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

        private

        def parse_structured_tokenizer_config(source_name, config, context:)
          unless config.is_a?(Hash)
            raise InvalidIndexDefinition, "#{context} for #{source_name.inspect} must be a Hash"
          end

          tokenizer = config[:tokenizer] || config["tokenizer"]
          if tokenizer.nil?
            raise InvalidIndexDefinition, "#{context} for #{source_name.inspect} requires :tokenizer"
          end

          tokenizer_name = tokenizer.to_s
          validate_tokenizer_name!(source_name, tokenizer_name)

          args = config[:args] || config["args"]
          named_args = config[:named_args] || config["named_args"]
          filters = config[:filters] || config["filters"]
          stemmer = config[:stemmer] || config["stemmer"]
          alias_name = config[:alias] || config["alias"]

          options = {}
          if args
            unless args.respond_to?(:to_ary)
              raise InvalidIndexDefinition, "args for #{source_name.inspect} must be an Array"
            end
            options[:__positional] = args.to_ary
          end

          if named_args
            unless named_args.is_a?(Hash)
              raise InvalidIndexDefinition, "named_args for #{source_name.inspect} must be a Hash"
            end
            named_args.each { |key, value| options[key.to_sym] = value }
          end

          if filters
            unless filters.respond_to?(:to_ary)
              raise InvalidIndexDefinition, "filters for #{source_name.inspect} must be an Array"
            end
            filters.to_ary.each do |name|
              filter_key = name.to_s
              if filter_key == "stemmer" && stemmer
                options[:stemmer] = stemmer
              else
                key = filter_key.to_sym
                options[key] = true unless options.key?(key)
              end
            end
          end

          options[:stemmer] = stemmer if stemmer && !options.key?(:stemmer)
          options[:alias] = alias_name.to_s if alias_name

          build_tokenized_entry(source_name, tokenizer_name, options)
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
          DefinitionCompiler::Entry.new(
            source: source_name,
            expression: expression?(source_name),
            tokenizer: tokenizer,
            options: options,
            query_key: key
          )
        end

        def validate_tokenizer_name!(source_name, tokenizer)
          return if ParadeDB::TokenizerSQL::TOKENIZER_EXPRESSION.match?(tokenizer)

          raise InvalidIndexDefinition,
                "invalid tokenizer name #{tokenizer.inspect} for #{source_name}. " \
                "Expected identifier form like simple, pdb::simple, or pdb::ngram(2, 5, alias=field_alias)."
        end

        def expression?(value)
          value.match?(/[^a-zA-Z0-9_]/)
        end
      end
    end

    # Consumed by migration helpers; validates and normalizes the DSL class
    class DefinitionCompiler
      FIELD_OPTION_KEYS = %i[fast record normalizer expand_dots].freeze

      class Compiled
        attr_reader :table_name, :key_field, :index_name, :entries, :index_options, :field_options

        def initialize(table_name:, key_field:, index_name:, entries:, index_options:, field_options:)
          @table_name = table_name
          @key_field = key_field
          @index_name = index_name
          @entries = entries
          @index_options = index_options
          @field_options = field_options
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
            field_options: field_options
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

          build_entries_from_structured_fields(raw_fields)
        end

        def build_entries_from_structured_fields(raw_fields)
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

            if tokenizers
              if single_tokenizer_keys_present
                raise InvalidIndexDefinition,
                      "field #{source_name.inspect} cannot mix :tokenizers with :tokenizer/:args/:named_args/:filters/:stemmer/:alias"
              end
              unless tokenizers.respond_to?(:to_ary) && !tokenizers.to_ary.empty?
                raise InvalidIndexDefinition, "field #{source_name.inspect} :tokenizers must be a non-empty Array"
              end

              tokenizers.to_ary.each_with_index do |tokenizer_config, idx|
                entry = TokenizerParser.send(
                  :parse_structured_tokenizer_config,
                  source_name,
                  tokenizer_config,
                  context: "tokenizers[#{idx}]"
                )
                entries << entry
              end
            elsif single_tokenizer_keys_present
              unless normalized[:tokenizer]
                raise InvalidIndexDefinition,
                      "field #{source_name.inspect} specifies tokenizer configuration but no :tokenizer"
              end
              entry = TokenizerParser.send(
                :parse_structured_tokenizer_config,
                source_name,
                select_keys(normalized, TokenizerParser::TOKENIZER_SINGLE_KEYS),
                context: "tokenizer config"
              )
              entries << entry
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
