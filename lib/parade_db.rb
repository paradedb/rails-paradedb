# frozen_string_literal: true

require_relative "parade_db/version"
require_relative "parade_db/errors"
require_relative "parade_db/arel"
require_relative "parade_db/index"
require_relative "parade_db/aggregations"
require_relative "parade_db/diagnostics"
require_relative "parade_db/migration_helpers"
require_relative "parade_db/model"
require_relative "parade_db/search_methods"
require_relative "parade_db/railtie"

module ParadeDB
  FacetQueryError = Errors::FacetQueryError
  InvalidIndexDefinition = Errors::InvalidIndexDefinition
  UnsupportedAdapterError = Errors::UnsupportedAdapterError
  MethodCollisionError = Errors::MethodCollisionError
  FieldNotIndexed = Errors::FieldNotIndexed
  IndexClassNotFoundError = Errors::IndexClassNotFoundError
  IndexDriftError = Errors::IndexDriftError

  module_function

  def paradedb_indexes(connection: ActiveRecord::Base.connection)
    Diagnostics.indexes(connection: connection)
  end

  def paradedb_index_segments(index, connection: ActiveRecord::Base.connection)
    Diagnostics.index_segments(index, connection: connection)
  end

  def paradedb_verify_index(index, **options)
    Diagnostics.verify_index(index, **options)
  end

  def paradedb_verify_all_indexes(**options)
    Diagnostics.verify_all_indexes(**options)
  end

  def index_validation_mode
    @index_validation_mode ||= :off
  end

  def index_validation_mode=(mode)
    normalized = mode.to_sym
    valid_modes = %i[warn raise off]
    if valid_modes.include?(normalized)
      @index_validation_mode = normalized
      return
    end

    raise ArgumentError, "index_validation_mode must be one of: #{valid_modes.join(', ')}"
  end

  def ensure_postgresql_adapter!(connection, context:)
    adapter_name = connection.adapter_name.to_s
    return if adapter_name.downcase.include?("postgres")

    raise Errors::UnsupportedAdapterError,
          "#{context} only supports PostgreSQL. Current adapter: #{adapter_name.inspect}"
  end
end
