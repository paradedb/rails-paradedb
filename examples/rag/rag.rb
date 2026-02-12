#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "setup"

OPENROUTER_API_KEY = ENV["OPENROUTER_API_KEY"]
MODEL = ENV.fetch("RAG_MODEL", "anthropic/claude-3-haiku")

def tokenize(text)
  text.to_s.downcase.scan(/[[:alnum:]]+/)
end

def format_context(items)
  return "No products found." if items.empty?

  items.map do |item|
    stock = item.in_stock ? "In Stock" : "Out of Stock"
    color = item.metadata&.fetch("color", nil) || "N/A"
    "- #{item.description} | Category: #{item.category} | Rating: #{item.rating}/5 | #{stock} | Color: #{color}"
  end.join("\n")
end

def generate(query, context)
  unless OPENROUTER_API_KEY && !OPENROUTER_API_KEY.empty?
    return "(OPENROUTER_API_KEY is not set. Retrieval worked, generation skipped.)"
  end

  prompt = <<~PROMPT
    You are a helpful product assistant. Answer the customer's question based only on the product information provided below.

    Product Catalog:
    #{context}

    Customer Question: #{query}

    Provide a helpful, concise answer. If the products don't match what the customer is looking for, say so.
  PROMPT

  uri = URI("https://openrouter.ai/api/v1/chat/completions")
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{OPENROUTER_API_KEY}"
  request["Content-Type"] = "application/json"
  request.body = JSON.dump(
    {
      model: MODEL,
      messages: [{ role: "user", content: prompt }]
    }
  )

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
    http.request(request)
  end

  unless response.is_a?(Net::HTTPSuccess)
    return "(OpenRouter HTTP #{response.code}: #{response.body})"
  end

  JSON.parse(response.body).dig("choices", 0, "message", "content") || "(No response content returned)"
rescue StandardError => error
  "(OpenRouter error: #{error})"
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "RAG with rails-paradedb + OpenRouter"
  puts "=" * 60
  puts "Using model: #{MODEL}"
  puts "Set RAG_MODEL to use a different model"

  count = RagSetup.setup_mock_items!
  puts "Loaded #{count} products"

  [
    "What running shoes do you have?",
    "I need comfortable shoes for everyday use",
    "Do you have any wireless audio products?"
  ].each do |query|
    puts "\n#{'=' * 60}"
    puts "Question: #{query}"
    puts "=" * 60

    terms = tokenize(query)
    items = if terms.empty?
              []
            else
              MockItem.search(:description)
                      .matching_any(*terms)
                      .with_score
                      .order(search_score: :desc)
                      .limit(5)
                      .to_a
            end

    puts "\nRetrieved #{items.length} products:"
    puts items.map { |item| "  - #{item.description} (score: #{item.search_score.round(2)})" }

    context = format_context(items)
    puts "\nAnswer:"
    puts "-" * 40
    puts generate(query, context)
  end

  puts "\n#{"=" * 60}"
  puts "Done!"
end
