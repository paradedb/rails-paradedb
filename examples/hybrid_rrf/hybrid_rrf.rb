#!/usr/bin/env ruby
# frozen_string_literal: true

require "neighbor"

require_relative "../common"
require_relative "setup"

class MockItem < ActiveRecord::Base
  has_neighbors :embedding
end

# Only keep helpers for SQL that Rails DSL genuinely cannot express
module RrfHelpers
  module_function

  # RRF score formula - the core calculation that repeats
  def rrf_score(weight:, rrf_k:, rank_column:)
    "#{weight.to_f}::float8 / (#{rrf_k.to_f}::float8 + #{rank_column}.rank_position)"
  end
end

def fulltext_ranked_cte(query, top_k:)
  # ParadeDB DSL branch: parse + score + rank.
  fulltext_source = MockItem.search(:description)
                            .parse(query, lenient: true)
                            .with_score
                            .order(search_score: :desc)
                            .limit(top_k)

  MockItem.from(fulltext_source, :fulltext_source)
          .select("fulltext_source.id")
          .select("ROW_NUMBER() OVER (ORDER BY fulltext_source.search_score DESC) AS rank_position")
end

def semantic_ranked_cte(query_embedding, top_k:)
  # Neighbor DSL branch: nearest neighbors + rank by neighbor_distance.
  semantic_source = MockItem.nearest_neighbors(:embedding, query_embedding, distance: "cosine")
                            .limit(top_k)

  MockItem.from(semantic_source, :semantic_source)
          .select("semantic_source.id")
          .select("ROW_NUMBER() OVER (ORDER BY semantic_source.neighbor_distance ASC) AS rank_position")
end

def bm25_contribution_cte(weight:, rrf_k:)
  contribution = RrfHelpers.rrf_score(weight: weight, rrf_k: rrf_k, rank_column: "fulltext")

  MockItem.from("fulltext")
          .select(
            "fulltext.id",
            "fulltext.rank_position AS bm25_rank",
            "NULL::integer AS semantic_rank",
            "#{contribution} AS bm25_rrf",
            "0.0::float8 AS semantic_rrf",
            "#{contribution} AS hybrid_rrf"
          )
end

def semantic_contribution_cte(weight:, rrf_k:)
  contribution = RrfHelpers.rrf_score(weight: weight, rrf_k: rrf_k, rank_column: "semantic")

  MockItem.from("semantic")
          .select(
            "semantic.id",
            "NULL::integer AS bm25_rank",
            "semantic.rank_position AS semantic_rank",
            "0.0::float8 AS bm25_rrf",
            "#{contribution} AS semantic_rrf",
            "#{contribution} AS hybrid_rrf"
          )
end

def combined_scores_cte
  MockItem.from("contributions")
          .select(
            "contributions.id",
            "MAX(contributions.bm25_rank) AS bm25_rank",
            "MAX(contributions.semantic_rank) AS semantic_rank",
            "SUM(contributions.bm25_rrf) AS bm25_rrf",
            "SUM(contributions.semantic_rrf) AS semantic_rrf",
            "SUM(contributions.hybrid_rrf) AS hybrid_score"
          )
          .group("contributions.id")
end

def hybrid_relation(query, top_k: 20, limit: 5, rrf_k: 60, bm25_weight: 1.0, semantic_weight: 1.0)
  query_embedding = HybridRrfSetup.query_embedding_for(query)
  fulltext_cte = fulltext_ranked_cte(query, top_k: top_k)
  semantic_cte = semantic_ranked_cte(query_embedding, top_k: top_k)
  bm25_contrib_cte = bm25_contribution_cte(weight: bm25_weight, rrf_k: rrf_k)
  semantic_contrib_cte = semantic_contribution_cte(weight: semantic_weight, rrf_k: rrf_k)
  scores_cte = combined_scores_cte

  MockItem.with(
            fulltext: fulltext_cte,
            semantic: semantic_cte,
            contributions: [bm25_contrib_cte, semantic_contrib_cte],
            hybrid_scores: scores_cte
          )
          .from("hybrid_scores")
          .joins("JOIN mock_items ON mock_items.id = hybrid_scores.id")
          .select(
            "mock_items.id",
            "mock_items.description",
            "hybrid_scores.bm25_rank",
            "hybrid_scores.semantic_rank",
            "hybrid_scores.bm25_rrf",
            "hybrid_scores.semantic_rrf",
            "hybrid_scores.hybrid_score"
          )
          .order("hybrid_scores.hybrid_score DESC, mock_items.id ASC")
          .limit(limit)
end

def hybrid_search(query, top_k: 20, limit: 5, rrf_k: 60, bm25_weight: 1.0, semantic_weight: 1.0)
  hybrid_relation(
    query,
    top_k: top_k,
    limit: limit,
    rrf_k: rrf_k,
    bm25_weight: bm25_weight,
    semantic_weight: semantic_weight
  ).to_a
end

def display_results(query, rows)
  puts "\n#{'=' * 80}"
  puts "Query: '#{query}'"
  puts "=" * 80

  if rows.empty?
    puts "  No results."
    return
  end

  rows.each_with_index do |row, index|
    bm25_rank = row.bm25_rank ? row.bm25_rank.to_i : nil
    semantic_rank = row.semantic_rank ? row.semantic_rank.to_i : nil

    puts format(
      "  %<rank>d. %<desc>-60s hybrid=%<hybrid>.4f bm25_rank=%<bm25>s semantic_rank=%<semantic>s",
      rank: index + 1,
      desc: "#{row.description[0, 60]}...",
      hybrid: row.hybrid_score.to_f,
      bm25: bm25_rank || "--",
      semantic: semantic_rank || "--"
    )
  end
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 80
  puts "Hybrid Search with Reciprocal Rank Fusion (single SQL query)"
  puts "=" * 80
  puts "\nCombining ParadeDB DSL + Neighbor DSL in one CTE-based query"

  HybridRrfSetup.setup!
  MockItem.reset_column_information

  ["running shoes", "footwear for exercise", "wireless earbuds"].each do |query|
    results = hybrid_search(query, top_k: 20, limit: 5)
    display_results(query, results)
  end

  puts "\n" + "=" * 80
  puts "Done!"
end
