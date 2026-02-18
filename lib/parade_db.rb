# frozen_string_literal: true

require_relative "parade_db/version"
require_relative "parade_db/arel"
require_relative "parade_db/index"
require_relative "parade_db/migration_helpers"
require_relative "parade_db/model"
require_relative "parade_db/search_methods"
require_relative "parade_db/railtie"

module ParadeDB
  class FacetQueryError < ArgumentError; end
  class InvalidIndexDefinition < ArgumentError; end
  class UnsupportedAdapterError < ArgumentError; end
  class MethodCollisionError < ArgumentError; end
  class FieldNotIndexed < ArgumentError; end
  class IndexClassNotFoundError < ArgumentError; end
  class IndexDriftError < ArgumentError; end

  module_function

  def index_validation_mode
    @index_validation_mode ||= :off
  end

  def index_validation_mode=(mode)
    normalized = mode.to_sym
    valid_modes = %i[warn raise off]
    return @index_validation_mode = normalized if valid_modes.include?(normalized)

    raise ArgumentError, "index_validation_mode must be one of: #{valid_modes.join(', ')}"
  end

  def ensure_postgresql_adapter!(connection, context:)
    adapter_name = connection.adapter_name.to_s
    return if adapter_name.downcase.include?("postgres")

    raise UnsupportedAdapterError,
          "#{context} only supports PostgreSQL. Current adapter: #{adapter_name.inspect}"
  end
end
