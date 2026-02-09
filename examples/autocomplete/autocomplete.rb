#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../common"
require_relative "setup"

class AutocompleteItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "autocomplete_items"
  self.primary_key = "id"
  self.has_paradedb_index = true
end

def demo_autocomplete
  puts "\n#{"=" * 60}"
  puts "Autocomplete"
  puts "=" * 60

  queries = %w[run runn running wire wirel wireles wireless blue blueto bluetooth]

  queries.each do |query|
    puts "\nUser types: '#{query}' ->"

    results = AutocompleteItem.search(:description_ngram)
                              .matching_all(query)
                              .with_score
                              .order(search_score: :desc)
                              .limit(5)
    puts results.map { |item| "  - #{item.description.truncate(50)} (score: #{item.search_score.round(2)})" }
  end
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "rails-paradedb Autocomplete Example"
  puts "Fast as-you-type search"
  puts "=" * 60

  count = AutocompleteSetup.setup_autocomplete_table!
  AutocompleteItem.reset_column_information
  puts "Loaded #{count} products from autocomplete_items table"

  demo_autocomplete

  puts "\nDone."
end
