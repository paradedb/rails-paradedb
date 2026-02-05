# frozen_string_literal: true

require_relative "parade_db/arel"
require_relative "parade_db/model"
require_relative "parade_db/search_methods"

module ParadeDB
  class FacetQueryError < ArgumentError; end
end
