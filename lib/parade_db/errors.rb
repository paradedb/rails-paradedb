# frozen_string_literal: true

module ParadeDB
  # Centralized error types for rails-paradedb.
  #
  # These are also aliased at the top-level (e.g. `ParadeDB::FacetQueryError`) for
  # backwards-compatibility.
  module Errors
    class Base < ArgumentError; end

    class FacetQueryError < Base; end
    class InvalidIndexDefinition < Base; end
    class UnsupportedAdapterError < Base; end
    class MethodCollisionError < Base; end
    class FieldNotIndexed < Base; end
    class IndexClassNotFoundError < Base; end
    class IndexDriftError < Base; end
  end
end
