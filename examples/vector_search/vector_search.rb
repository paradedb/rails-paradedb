#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "setup"

def demo_top_k(query_embedding)
  puts "\n--- Top-K Nearest Neighbors (L2, from the index metric) ---"
  results = MockItem.nearest(:embedding, query_embedding).limit(3)
  puts(results.map { |item| "  - #{item.description}" })
end

def demo_metric_override(query_embedding)
  puts "\n--- Metric Override (cosine; falls back to a plain sort without a matching opclass) ---"
  results = MockItem.nearest(:embedding, query_embedding, metric: :cosine).limit(3)
  puts(results.map { |item| "  - #{item.description}" })
end

def demo_filtered_vector_search(query_embedding)
  puts "\n--- Vector Search + Full-Text Filter: category 'Footwear' ---"
  results = MockItem.search(:category)
                    .term("Footwear")
                    .nearest(:embedding, query_embedding)
                    .limit(3)
  puts(results.map { |item| "  - #{item.description}" })
end

def demo_distance_projection(query_embedding)
  puts "\n--- Distance Projection ---"
  distance = MockItem.l2_distance(:embedding, query_embedding)
  results = MockItem.nearest(:embedding, query_embedding)
                    .select(MockItem.arel_table[Arel.star], distance.as("distance"))
                    .limit(3)
  puts(results.map { |item| "  - #{item.description} (distance: #{item.distance.round(3)})" })
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "rails-paradedb Vector Search Example"
  puts "=" * 60

  VectorSearchSetup.setup!
  query_embedding = VectorSearchSetup.query_embedding

  demo_top_k(query_embedding)
  demo_metric_override(query_embedding)
  demo_filtered_vector_search(query_embedding)
  demo_distance_projection(query_embedding)

  puts "\nDone!"
end
