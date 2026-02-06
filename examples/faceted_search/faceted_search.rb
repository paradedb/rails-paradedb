#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../common"

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "rails-paradedb Faceted Search Example"
  puts "=" * 60

  count = ExampleCommon.setup_mock_items!
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
  rows.each do |item|
    color = item.metadata&.fetch("color", nil) || "N/A"
    stock = item.in_stock ? "In Stock" : "Out of Stock"
    puts "  - #{item.description[0, 50]}... [#{item.category}] " \
         "(rating: #{item.rating}, #{stock}, color: #{color})"
  end

  puts "\nFacet buckets:"
  facets.each do |key, data|
    buckets = data.is_a?(Hash) ? Array(data["buckets"]) : []
    puts "#{key} (#{buckets.length} buckets)"
    buckets.each do |bucket|
      puts "  - #{bucket["key"]}: #{bucket["doc_count"]}"
    end
  end

  puts "\n" + "=" * 60
  puts "Done!"
end
