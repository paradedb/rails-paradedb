#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../common"

def demo_basic_search
  puts "\n--- Basic Search: 'shoes' ---"
  results = MockItem.search(:description).matching_all("shoes").limit(5)
  puts results.map { |item| "  - #{item.description.truncate(60)}" }
end

def demo_scored_search
  puts "\n--- Scored Search: 'running' ---"
  results = MockItem.search(:description)
                    .matching_all("running")
                    .with_score
                    .order(search_score: :desc)
                    .limit(5)

  puts results.map { |item| "  - #{item.description.truncate(50)} (score: #{item.search_score.round(2)})" }
end

def demo_phrase_search
  puts "\n--- Phrase Search: 'running shoes' ---"
  results = MockItem.search(:description)
                    .phrase("running shoes")
                    .with_score
                    .order(search_score: :desc)
                    .limit(5)

  puts results.map { |item| "  - #{item.description.truncate(50)} (score: #{item.search_score.round(2)})" }
end

def demo_snippet_highlighting
  puts "\n--- Snippet Highlighting: 'shoes' ---"
  results = MockItem.search(:description)
                    .matching_all("shoes")
                    .with_score
                    .with_snippet(:description, start_tag: "<b>", end_tag: "</b>")
                    .order(search_score: :desc)
                    .limit(3)

  puts results.map { |item| "  - #{item.description_snippet}" }
end

def demo_filtered_search
  puts "\n--- Filtered Search: 'shoes' + in_stock + rating >= 4 ---"
  results = MockItem.search(:description)
                    .matching_all("shoes")
                    .where(in_stock: true)
                    .where("rating >= ?", 4)
                    .with_score
                    .order(search_score: :desc)
                    .limit(5)

  puts results.map { |item| "  - #{item.description.truncate(40)} (rating: #{item.rating})" }
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "rails-paradedb Quickstart Example"
  puts "=" * 60

  count = ExampleCommon.setup_mock_items!
  puts "Loaded #{count} mock items"

  demo_basic_search
  demo_scored_search
  demo_phrase_search
  demo_snippet_highlighting
  demo_filtered_search

  puts "\n" + "=" * 60
  puts "Done!"
end
