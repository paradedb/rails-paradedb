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
                    .order(Arel.sql("search_score DESC"))
                    .limit(5)

  similar.each do |item|
    marker = item.id == source_id ? " (source)" : ""
    puts format("  %<id>d: %<desc>s... [%<category>s]%<marker>s",
                id: item.id,
                desc: item.description[0, 50],
                category: item.category,
                marker: marker)
  end
end

def demo_similar_to_multiple_products
  puts "\n" + "=" * 60
  puts "Demo 2: Similar to multiple products (browsing history)"
  puts "=" * 60

  browsed_ids = [3, 12, 29]
  browsed = MockItem.where(id: browsed_ids)

  puts "\nUser's browsing history:"
  browsed.each do |item|
    puts "  #{item.id}: #{item.description[0, 50]}... [#{item.category}]"
  end

  relations = browsed_ids.map { |id| MockItem.more_like_this(id, fields: [:description]) }
  combined = relations.reduce { |memo, relation| memo.or(relation) }

  puts "\nRecommended products (similar to any browsed item):"
  similar = combined.where.not(id: browsed_ids)
                    .extending(ParadeDB::SearchMethods)
                    .with_score
                    .order(Arel.sql("search_score DESC"))
                    .limit(5)

  similar.each do |item|
    puts "  #{item.id}: #{item.description[0, 50]}... [#{item.category}]"
  end
end

def demo_combined_with_filters
  puts "\n" + "=" * 60
  puts "Demo 3: MoreLikeThis + ActiveRecord filters"
  puts "=" * 60

  source_id = 15
  source = MockItem.find(source_id)
  puts "\nSource: '#{source.description}' (rating: #{source.rating})"

  puts "\nSimilar products (in_stock=true, rating >= 4):"
  results = MockItem.more_like_this(source_id, fields: [:description])
                    .where(in_stock: true)
                    .where("rating >= ?", 4)
                    .with_score
                    .order(Arel.sql("search_score DESC"))
                    .limit(5)

  results.each do |item|
    stock = item.in_stock ? "In Stock" : "Out of Stock"
    puts "  #{item.id}: #{item.description[0, 40]}... (rating: #{item.rating}, #{stock})"
  end
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
  by_description.each do |item|
    puts "  #{item.id}: #{item.description[0, 40]}... [#{item.category}]"
  end

  puts "\nSimilar by DESCRIPTION + CATEGORY:"
  by_both = MockItem.more_like_this(source_id, fields: [:description, :category]).where.not(id: source_id).limit(3)
  by_both.each do |item|
    puts "  #{item.id}: #{item.description[0, 40]}... [#{item.category}]"
  end
rescue ActiveRecord::StatementInvalid => error
  puts "  (Skipped: #{error.message})"
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
