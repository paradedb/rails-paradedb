# frozen_string_literal: true

require_relative "parade_db/arel"
require_relative "parade_db/model"
require_relative "parade_db/search_methods"

module ParadeDB
  class FacetQueryError < ArgumentError; end
  class UnsupportedAdapterError < ArgumentError; end

  module_function

  def ensure_postgresql_adapter!(connection, context:)
    adapter_name = connection.adapter_name.to_s
    return if adapter_name.downcase.include?("postgres")

    raise UnsupportedAdapterError,
          "#{context} only supports PostgreSQL. Current adapter: #{adapter_name.inspect}"
  end
end
