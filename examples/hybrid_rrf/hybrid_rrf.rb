#!/usr/bin/env ruby
# frozen_string_literal: true

begin
  require "neighbor"
rescue LoadError
  abort "neighbor gem is required for this example. Install with: BUNDLE_GEMFILE=examples/Gemfile bundle install"
end

require_relative "../common"
require_relative "setup"

class MockItem < ActiveRecord::Base
  has_neighbors :embedding
end

QUERY_SEED_TEXT = {
  "running shoes" => "Sleek running shoes",
  "footwear for exercise" => "Sleek running shoes",
  "wireless earbuds" => "Innovative wireless earbuds"
}.freeze

def tokenize(text)
  text.to_s.downcase.scan(/[[:alnum:]]+/)
end

def bm25_search(query, top_k: 20)
  terms = tokenize(query)
  return [] if terms.empty?

  MockItem.search(:description)
          .matching_any(*terms)
          .with_score
          .order(search_score: :desc)
          .limit(top_k)
          .map { |item| [item.id, item.search_score.to_f] }
end

def query_seed_item(query)
  terms = tokenize(query)
  normalized_query = query.to_s.downcase.strip

  seed_text = QUERY_SEED_TEXT[normalized_query]
  seed_scope = MockItem.where.not(embedding: nil)
  seed_id = if seed_text
              seed_scope.where("description ILIKE ?", "%#{seed_text}%")
                        .limit(1)
                        .pick(:id)
            end

  seed_id ||= if terms.empty?
              nil
            else
              seed_scope.search(:description)
                      .matching_any(*terms)
                      .limit(1)
                      .pick(:id)
            end

  seed_id ||= seed_scope.limit(1).pick(:id)
  raise "No embeddings available. Run setup first." unless seed_id

  seed_scope.find(seed_id)
end

def vector_search(query, top_k: 20)
  seed_item = query_seed_item(query)

  seed_item.nearest_neighbors(:embedding, distance: "cosine")
          .where.not(embedding: nil)
          .first(top_k)
          .map { |item| [item.id, item.neighbor_distance.to_f] }
end

def reciprocal_rank_fusion(bm25_results, vector_results, k: 60)
  scores = Hash.new(0.0)

  bm25_results.each_with_index do |(item_id, _score), rank|
    scores[item_id] += 1.0 / (k + rank + 1)
  end

  vector_results.each_with_index do |(item_id, _distance), rank|
    scores[item_id] += 1.0 / (k + rank + 1)
  end

  scores.sort_by { |_item_id, score| -score }
end

def display_results(query, bm25_results, vector_results, rrf_results)
  puts "\n#{'=' * 80}"
  puts "Query: '#{query}'"
  puts "=" * 80

  ids = (bm25_results.first(5) + vector_results.first(5) + rrf_results.first(5)).map(&:first).uniq
  items = MockItem.where(id: ids).index_by(&:id)

  puts "\nBM25 Results (keyword):"
  bm25_results.first(5).each_with_index do |(item_id, score), index|
    item = items[item_id]
    next unless item

    puts format(
      "  %<rank>d. %<desc>-60s (score: %<score>.2f)",
      rank: index + 1,
      desc: "#{item.description[0, 60]}...",
      score: score
    )
  end

  puts "\nVector Results (semantic):"
  vector_results.first(5).each_with_index do |(item_id, distance), index|
    item = items[item_id]
    next unless item

    puts format(
      "  %<rank>d. %<desc>-60s (dist: %<distance>.3f)",
      rank: index + 1,
      desc: "#{item.description[0, 60]}...",
      distance: distance
    )
  end

  puts "\nHybrid RRF Results (combined):"
  rrf_results.first(5).each_with_index do |(item_id, score), index|
    item = items[item_id]
    next unless item

    puts format(
      "  %<rank>d. %<desc>-60s (RRF: %<score>.4f)",
      rank: index + 1,
      desc: "#{item.description[0, 60]}...",
      score: score
    )
  end
end

def demo(query)
  bm25_results = bm25_search(query, top_k: 20)
  vector_results = vector_search(query, top_k: 20)
  rrf_results = reciprocal_rank_fusion(bm25_results, vector_results)

  display_results(query, bm25_results, vector_results, rrf_results)
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 80
  puts "Hybrid Search with Reciprocal Rank Fusion (RRF)"
  puts "=" * 80
  puts "\nCombining BM25 (keyword) + vector distance search"
  puts "RRF formula: score = sum(1 / (k + rank_i)) across all rankings"

  HybridRrfSetup.setup!
  MockItem.reset_column_information

  demo("running shoes")
  demo("footwear for exercise")
  demo("wireless earbuds")

  puts "\n" + "=" * 80
  puts "Done!"
end
