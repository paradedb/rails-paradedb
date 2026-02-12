#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "setup"

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "rails-paradedb Faceted Search Example"
  puts "=" * 60

  count = FacetedSearchSetup.setup_mock_items!
  puts "Loaded #{count} mock items"

  search_query = "shoes"
  puts "\nQuery: '#{search_query}'"

  puts "\n--- Facets + Rows (Top-N) ---"
  relation = MockItem.search(:description)
                     .matching_all(search_query)
                     .with_facets(:category, :rating, :metadata_color)
                     .order(rating: :desc)
                     .limit(5)

  rows = relation.to_a
  facets = relation.facets

  puts "Top results:"
  puts rows.map { |item|
    color = item.metadata&.fetch("color", nil) || "N/A"
    "  - #{item.description.truncate(50)} [#{item.category}] (rating: #{item.rating}, color: #{color})"
  }

  puts "\nFacet buckets:"
  facets.each do |key, data|
    buckets = data.is_a?(Hash) ? Array(data["buckets"]) : []
    puts "#{key} (#{buckets.length} buckets)"
    puts buckets.map { |bucket| "  - #{bucket["key"]}: #{bucket["doc_count"]}" }
  end

  puts "\n#{"=" * 60}"
  puts "Done!"
end
