# frozen_string_literal: true

require "spec_helper"

class GuardTestProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
end

RSpec.describe "Guards" do
  let(:relation) { GuardTestProduct.all.extending(ParadeDB::SearchMethods) }
  let(:builder) { GuardTestProduct.search(:description).send(:builder) }

  it "requires a search field for query methods" do
    [
      -> { relation.match_all("shoes") },
      -> { relation.match_any("shoes") },
      -> { relation.excluding("shoes") },
      -> { relation.phrase("running shoes") },
      -> { relation.regex("run.*") },
      -> { relation.regex_phrase("run.*", "sho.*") },
      -> { relation.term("shoes") },
      -> { relation.term_set("shoes") },
      -> { relation.near(ParadeDB.proximity("running").within(1, "shoes")) },
      -> { relation.phrase_prefix("run") },
      -> { relation.parse("running AND shoes") },
      -> { relation.match_all },
      -> { relation.exists },
      -> { relation.range(3..5) },
      -> { relation.range_term(1) }
    ].each do |call|
      assert_includes assert_raises(ArgumentError, &call).message, "No search field set"
    end
  end

  it "validates query modifiers" do
    [
      [-> { ParadeDB.boost("shoes", "high") }, "factor must be numeric"],
      [-> { ParadeDB.tokenize("shoes", "whitespace") }, "tokenizer must be a Tokenizer"],
      [-> { ParadeDB.slop("running shoes", "lots") }, "distance must be numeric"],
      [-> { ParadeDB.fuzzy("shoes", "far") }, "distance must be numeric"],
      [-> { ParadeDB.fuzzy("shoes", 5) }, "distance must be between 0 and 2"],
      [-> { ParadeDB.constant("shoes", "fixed") }, "score must be numeric"],
      [-> { ParadeDB.regex_term("sl.*", max_expansions: "100") }, "max_expansions must be an integer"],
      [-> { builder.near(:description, "running") }, "near requires a ParadeDB.proximity"],
      [-> { builder.near(:description, ParadeDB.proximity("running")) }, "near requires at least one within clause"],
      [-> { builder.range(:rating) }, "range requires at least one bound"],
      [-> { builder.range(:rating, nil, gte: 2, gt: 3) }, "gte and gt"],
      [-> { builder.range(:rating, nil, lte: 5, lt: 4) }, "lte and lt"],
      [-> { builder.range(:rating, 1..2, type: :bad) }, "Unknown range type"],
      [-> { builder.range_term(:weight_range, "(10, 12]", relation: "Intersects") }, "relation requires range_type"],
      [-> { builder.range_term(:weight_range, "(10, 12]", relation: "Overlap", range_type: "int4range") }, "Unknown range relation"]
    ].each do |call, message|
      assert_includes assert_raises(ArgumentError, &call).message, message
    end
  end

  it "rejects empty query arguments" do
    [
      [-> { builder.match(:description) }, "at least one search term"],
      [-> { builder.match(:description, "   ") }, "at least one search term"],
      [-> { builder.match_any(:description) }, "at least one search term"],
      [-> { builder.term_set(:description) }, "term_set requires at least one value"],
      [-> { builder.phrase_prefix(:description) }, "phrase_prefix requires at least one term"],
      [-> { builder.phrase(:description, []) }, "phrase array input requires at least one term"],
      [-> { builder.regex_phrase(:description) }, "regex_phrase requires at least one pattern"]
    ].each do |call, message|
      assert_includes assert_raises(ArgumentError, &call).message, message
    end
  end

  it "validates projection options" do
    [
      [-> { GuardTestProduct.search(:description).match_all("shoes").with_snippet(:description, max_chars: "abc") }, /invalid value/i],
      [-> { GuardTestProduct.search(:description).match_all("shoes").with_snippets(:description, max_chars: "abc") }, /max_chars must be an integer/],
      [-> { GuardTestProduct.search(:description).match_all("shoes").with_snippets(:description, limit: "abc") }, /limit must be an integer/],
      [-> { GuardTestProduct.search(:description).match_all("shoes").with_snippets(:description, offset: "abc") }, /offset must be an integer/],
      [-> { GuardTestProduct.search(:description).match_all("shoes").with_snippets(:description, sort_by: :unknown) }, /sort_by must be one of/],
      [-> { GuardTestProduct.search(:description).match_all("shoes").with_snippets(:description, as: " ") }, /as cannot be blank/],
      [-> { GuardTestProduct.search(:description).match_all("shoes").with_snippet_positions(:description, as: "") }, /as cannot be blank/]
    ].each do |call, message|
      assert_match message, assert_raises(ArgumentError, &call).message
    end
  end

  it "validates more-like-this and facet options" do
    search = GuardTestProduct.search(:description).match_all("shoes")
    [
      [-> { GuardTestProduct.more_like_this(1, unsupported_option: 2) }, ArgumentError, "Unknown more_like_this option"],
      [-> { GuardTestProduct.more_like_this(1, min_term_freq: "2") }, ArgumentError, "min_term_frequency must be an Integer >= 1"],
      [-> { GuardTestProduct.more_like_this(1, min_term_freq: 0) }, ArgumentError, "min_term_frequency must be an Integer >= 1"],
      [-> { GuardTestProduct.more_like_this(1, stopwords: "the") }, ArgumentError, "stopwords must be an Array of strings"],
      [-> { GuardTestProduct.more_like_this(1, stopwords: ["the", 123]) }, ArgumentError, "stopwords must contain only strings"],
      [-> { search.build_facet_query(fields: []) }, ArgumentError, "facets requires at least one field or agg"],
      [-> { search.build_facet_query(fields: [:category, "category"]) }, ArgumentError, "Facet field names must be unique"],
      [-> { search.build_facet_query(fields: [123]) }, TypeError, "Facet field names must be strings or symbols"],
      [-> { search.build_facet_query(fields: [:category], size: -1) }, ArgumentError, "Facet size must be an integer"],
      [-> { search.build_facet_query(fields: [:category], order: "bogus") }, ArgumentError, "Unknown facet order"],
      [-> { search.with_facets(:category, agg: 123) }, ArgumentError, "agg must be a Hash or JSON String"],
      [-> { search.facets(:category, agg: Object.new) }, ArgumentError, "agg must be a Hash or JSON String"],
      [-> { search.with_agg }, ArgumentError, "at least one named aggregation"],
      [-> { search.with_agg(broken: { value_count: { field: "id" }, avg: { field: "rating" } }) }, ArgumentError, "exactly one top-level key"]
    ].each do |call, error_class, message|
      assert_includes assert_raises(error_class, &call).message, message
    end
  end

  it "requires order and limit before loading windowed facets" do
    base = GuardTestProduct.search(:description).match_all("shoes").with_facets(:category)

    [[base, "ORDER BY and LIMIT"], [base.order(:id), "LIMIT"], [base.limit(10), "ORDER BY"]].each do |query, message|
      assert_includes assert_raises(ParadeDB::FacetQueryError) { query.load }.message, message
    end
  end
end
