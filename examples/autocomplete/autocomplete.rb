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

def autocomplete_relation(query)
  AutocompleteItem.search(:description)
                  .parse("description_ngram:#{query}")
                  .with_score
                  .order(search_score: :desc)
                  .limit(5)
end

def demo_autocomplete
  puts "\n" + "=" * 60
  puts "Autocomplete"
  puts "=" * 60

  queries = %w[run runn running wire wirel wireles wireless blue blueto bluetooth]

  queries.each do |query|
    puts "\nUser types: '#{query}' ->"

    results = autocomplete_relation(query)

    if results.empty?
      puts "  (no results)"
      next
    end

    results.each do |item|
      puts format("  - %-50s (score: %.2f)", "#{item.description[0, 50]}...", item.search_score.to_f)
    end
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
