#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "setup"

QUERY_EMBEDDING = [1.0, 0.0, 0.0].freeze

def demo_top_k
  puts "\n--- Top-K Nearest Neighbors (L2, from the index metric) ---"
  results = VectorItem.nearest(:embedding, QUERY_EMBEDDING).limit(3)
  puts(results.map { |item| "  - #{item.description}" })
end

def demo_metric_override
  puts "\n--- Metric Override (cosine; falls back to a plain sort without a matching opclass) ---"
  results = VectorItem.nearest(:embedding, QUERY_EMBEDDING, metric: :cosine).limit(3)
  puts(results.map { |item| "  - #{item.description}" })
end

def demo_filtered_vector_search
  puts "\n--- Vector Search + Full-Text Filter: category 'Footwear' ---"
  results = VectorItem.search(:category)
                      .term("Footwear")
                      .nearest(:embedding, QUERY_EMBEDDING)
                      .limit(3)
  puts(results.map { |item| "  - #{item.description}" })
end

def demo_distance_projection
  puts "\n--- Distance Projection ---"
  distance = VectorItem.paradedb_arel.l2_distance(:embedding, QUERY_EMBEDDING)
  results = VectorItem.nearest(:embedding, QUERY_EMBEDDING)
                      .select(VectorItem.arel_table[Arel.star], distance.as("distance"))
                      .limit(3)
  puts(results.map { |item| "  - #{item.description} (distance: #{item.distance.round(3)})" })
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "rails-paradedb Vector Search Example"
  puts "=" * 60

  VectorSearchSetup.setup!

  demo_top_k
  demo_metric_override
  demo_filtered_vector_search
  demo_distance_projection

  puts "\nDone!"
end
