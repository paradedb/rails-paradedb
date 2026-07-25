# frozen_string_literal: true

require "active_model"

module ParadeDB
  class Vector < ActiveModel::Type::Value
    METRICS = %i[l2 cosine ip].freeze
    METRIC_ALIASES = { inner_product: :ip }.freeze
    OPCLASSES = { l2: "vector_l2_ops", cosine: "vector_cosine_ops", ip: "vector_ip_ops" }.freeze
    METRICS_BY_OPCLASS = OPCLASSES.invert.freeze
    DISTANCE_OPERATORS = { l2: "<->", cosine: "<=>", ip: "<#>" }.freeze
    DEFAULT_METRIC = :l2

    def self.normalize_metric(metric)
      normalized = metric.to_sym
      normalized = METRIC_ALIASES.fetch(normalized, normalized)
      return normalized if METRICS.include?(normalized)

      raise ArgumentError,
            "unknown vector metric #{metric.inspect}. Valid metrics: #{(METRICS + METRIC_ALIASES.keys).map(&:inspect).join(', ')}"
    end

    def self.literal(value)
      "[#{Array(value).map { |v| Float(v) }.join(',')}]"
    end

    attr_reader :limit

    def initialize(limit: nil)
      super()
      @limit = limit
    end

    def type
      :vector
    end

    def cast(value)
      case value
      when nil
        nil
      when Array
        validate_dimensions!(value.map { |v| Float(v) })
      when String
        cast_string(value)
      else
        raise ArgumentError, "cannot cast #{value.class} to vector"
      end
    end

    def serialize(value)
      return nil if value.nil?

      self.class.literal(cast(value))
    end

    def deserialize(value)
      cast(value)
    end

    def changed_in_place?(raw_old_value, new_value)
      deserialize(raw_old_value) != new_value
    end

    def self.register_with_type_map(m)
      m.register_type "vector" do |_, _, sql_type|
        limit = sql_type.to_s[/\((\d+)\)/, 1]
        ParadeDB::Vector.new(limit: limit&.to_i)
      end
    end

    module PostgreSQLAdapterPatch
      def initialize_type_map(m)
        super
        ParadeDB::Vector.register_with_type_map(m)
      end
    end

    def self.install_postgresql_adapter!(adapter_class)
      adapter_class::NATIVE_DATABASE_TYPES[:vector] = { name: "vector" }

      unless adapter_class.singleton_class.ancestors.include?(PostgreSQLAdapterPatch)
        adapter_class.singleton_class.prepend(PostgreSQLAdapterPatch)
      end

      register_with_type_map(adapter_class::TYPE_MAP) if adapter_class.const_defined?(:TYPE_MAP)

      table_definition = ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition
      unless table_definition.method_defined?(:vector)
        table_definition.send(:define_column_methods, :vector)
      end
    end

    private

    def cast_string(value)
      stripped = value.strip
      unless stripped.start_with?("[") && stripped.end_with?("]")
        raise ArgumentError, "malformed vector literal: #{value.inspect}"
      end

      inner = stripped[1..-2].strip
      values = inner.empty? ? [] : inner.split(",").map { |v| Float(v) }
      validate_dimensions!(values)
    end

    def validate_dimensions!(values)
      if limit && values.length != limit
        raise ArgumentError, "expected #{limit} dimensions, got #{values.length}"
      end

      values
    end
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  ParadeDB::Vector.install_postgresql_adapter!(self)
end
