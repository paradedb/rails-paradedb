#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../common"
require_relative "setup"

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

def query_embedding_text(query)
  terms = tokenize(query)
  normalized_query = query.to_s.downcase.strip

  seed_text = QUERY_SEED_TEXT[normalized_query]
  seed_id = if seed_text
              MockItem.where("description ILIKE ?", "%#{seed_text}%")
                      .where.not(embedding: nil)
                      .limit(1)
                      .pick(:id)
            end

  seed_id ||= if terms.empty?
              nil
            else
              MockItem.search(:description)
                      .matching_any(*terms)
                      .where.not(embedding: nil)
                      .limit(1)
                      .pick(:id)
            end

  seed_id ||= MockItem.where.not(embedding: nil).limit(1).pick(:id)
  raise "No embeddings available. Run setup first." unless seed_id

  MockItem.connection.select_value("SELECT embedding::text FROM mock_items WHERE id = #{seed_id.to_i}")
end

def vector_search(query, top_k: 20)
  embedding_literal = query_embedding_text(query)
  quoted_vector = MockItem.connection.quote(embedding_literal)

  MockItem.where.not(embedding: nil)
          .select(
            :id,
            Arel.sql("embedding <=> #{quoted_vector}::vector AS distance")
          )
          .order(distance: :asc)
          .limit(top_k)
          .map { |item| [item.id, item.distance.to_f] }
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
