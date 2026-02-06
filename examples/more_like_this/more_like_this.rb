#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../common"

def demo_similar_to_single_product
  puts "\n" + "=" * 60
  puts "Demo 1: Similar to a single product"
  puts "=" * 60

  source_id = 3
  source = MockItem.find(source_id)
  puts "\nSource product (id=#{source_id}):"
  puts "  '#{source.description}' [#{source.category}]"

  puts "\nSimilar products (by description):"
  similar = MockItem.more_like_this(source_id, fields: [:description])
                    .with_score
                    .order(search_score: :desc)
                    .limit(5)

  similar.each do |item|
    marker = item.id == source_id ? " (source)" : ""
    puts "  #{item.id}: #{item.description.truncate(50)} [#{item.category}]#{marker}"
  end
end

def demo_similar_to_multiple_products
  puts "\n" + "=" * 60
  puts "Demo 2: Similar to multiple products (browsing history)"
  puts "=" * 60

  browsed_ids = [3, 12, 29]
  browsed = MockItem.where(id: browsed_ids)

  puts "\nUser's browsing history:"
  puts browsed.map { |item| "  #{item.id}: #{item.description.truncate(50)} [#{item.category}]" }

  combined_description = browsed.pluck(:description).join(" ")
  json_doc = { description: combined_description }.to_json

  puts "\nRecommended products (similar to browsing history):"
  similar = MockItem.more_like_this(json_doc)
                    .where.not(id: browsed_ids)
                    .with_score
                    .order(search_score: :desc)
                    .limit(5)

  puts similar.map { |item| "  #{item.id}: #{item.description.truncate(50)} [#{item.category}]" }
end

def demo_combined_with_filters
  puts "\n" + "=" * 60
  puts "Demo 3: MoreLikeThis + Filters (in_stock=true, rating >= 4)"
  puts "=" * 60

  source_id = 15

  results = MockItem.more_like_this(source_id, fields: [:description])
                    .where(in_stock: true)
                    .where("rating >= ?", 4)
                    .with_score
                    .order(search_score: :desc)
                    .limit(5)

  puts results.map { |item| "  #{item.id}: #{item.description.truncate(40)} (rating: #{item.rating})" }
end

def demo_multifield_similarity
  puts "\n" + "=" * 60
  puts "Demo 4: Multi-field similarity"
  puts "=" * 60

  source_id = 3
  source = MockItem.find(source_id)
  puts "\nSource: '#{source.description}' [#{source.category}]"

  puts "\nSimilar by DESCRIPTION only:"
  by_description = MockItem.more_like_this(source_id, fields: [:description]).where.not(id: source_id).limit(3)
  puts by_description.map { |item| "  #{item.id}: #{item.description.truncate(40)} [#{item.category}]" }

  puts "\nSimilar by DESCRIPTION + CATEGORY:"
  by_both = MockItem.more_like_this(source_id, fields: [:description, :category]).where.not(id: source_id).limit(3)
  puts by_both.map { |item| "  #{item.id}: #{item.description.truncate(40)} [#{item.category}]" }
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "rails-paradedb MoreLikeThis Example"
  puts "Find similar documents without vector embeddings"
  puts "=" * 60

  count = ExampleCommon.setup_mock_items!
  puts "Loaded #{count} mock items"

  demo_similar_to_single_product
  demo_similar_to_multiple_products
  demo_combined_with_filters
  demo_multifield_similarity

  puts "\n" + "=" * 60
  puts "Done!"
end
