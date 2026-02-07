# frozen_string_literal: true

require "spec_helper"

class GuardTestProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

class GuardsUnitTest < Minitest::Test
  # ──────────────────────────────────────────────
  # 1. "No search field set" guards
  #    Every search method must raise when called
  #    on a relation without .search(column) first.
  # ──────────────────────────────────────────────

  def bare_relation
    GuardTestProduct.all.extending(ParadeDB::SearchMethods)
  end

  def test_matching_all_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.matching_all("shoes") }
    assert_includes error.message, "No search field set"
  end

  def test_matching_any_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.matching_any("shoes") }
    assert_includes error.message, "No search field set"
  end

  def test_excluding_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.excluding("shoes") }
    assert_includes error.message, "No search field set"
  end

  def test_phrase_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.phrase("running shoes") }
    assert_includes error.message, "No search field set"
  end

  def test_fuzzy_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.fuzzy("shoes", distance: 1) }
    assert_includes error.message, "No search field set"
  end

  def test_regex_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.regex("run.*") }
    assert_includes error.message, "No search field set"
  end

  def test_term_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.term("shoes") }
    assert_includes error.message, "No search field set"
  end

  def test_near_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.near("running", "shoes") }
    assert_includes error.message, "No search field set"
  end

  def test_phrase_prefix_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.phrase_prefix("run") }
    assert_includes error.message, "No search field set"
  end

  def test_parse_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.parse("running AND shoes") }
    assert_includes error.message, "No search field set"
  end

  def test_match_all_without_search_raises
    error = assert_raises(RuntimeError) { bare_relation.match_all }
    assert_includes error.message, "No search field set"
  end

  # ──────────────────────────────────────────────
  # 2. Numeric parameter validation (Builder)
  # ──────────────────────────────────────────────

  def builder
    @builder ||= ParadeDB::Arel::Builder.new(:products)
  end

  def test_match_boost_rejects_non_numeric
    error = assert_raises(ArgumentError) { builder.match(:description, "shoes", boost: "high") }
    assert_includes error.message, "boost must be numeric"
  end

  def test_match_boost_accepts_numeric
    node = builder.match(:description, "shoes", boost: 2.5)
    refute_nil node
  end

  def test_match_boost_accepts_nil
    node = builder.match(:description, "shoes", boost: nil)
    refute_nil node
  end

  def test_phrase_slop_rejects_non_numeric
    error = assert_raises(ArgumentError) { builder.phrase(:description, "running shoes", slop: "lots") }
    assert_includes error.message, "slop must be numeric"
  end

  def test_phrase_slop_accepts_integer
    node = builder.phrase(:description, "running shoes", slop: 2)
    refute_nil node
  end

  def test_fuzzy_distance_rejects_non_numeric
    error = assert_raises(ArgumentError) { builder.fuzzy(:description, "shoes", distance: "far") }
    assert_includes error.message, "distance must be numeric"
  end

  def test_fuzzy_boost_rejects_non_numeric
    error = assert_raises(ArgumentError) { builder.fuzzy(:description, "shoes", distance: 1, boost: "high") }
    assert_includes error.message, "boost must be numeric"
  end

  def test_fuzzy_accepts_valid_numerics
    node = builder.fuzzy(:description, "shoes", distance: 2, boost: 1.5)
    refute_nil node
  end

  def test_term_boost_rejects_non_numeric
    error = assert_raises(ArgumentError) { builder.term(:description, "shoes", boost: [1]) }
    assert_includes error.message, "boost must be numeric"
  end

  def test_near_distance_rejects_non_numeric
    error = assert_raises(ArgumentError) { builder.near(:description, "a", "b", distance: "close") }
    assert_includes error.message, "distance must be numeric"
  end

  def test_near_distance_accepts_integer
    node = builder.near(:description, "a", "b", distance: 3)
    refute_nil node
  end

  # ──────────────────────────────────────────────
  # 3. Empty terms guards (Builder)
  # ──────────────────────────────────────────────

  def test_matching_all_with_no_terms_raises
    error = assert_raises(ArgumentError) { builder.match(:description) }
    assert_includes error.message, "at least one search term"
  end

  def test_matching_all_with_empty_string_raises
    error = assert_raises(ArgumentError) { builder.match(:description, "") }
    assert_includes error.message, "at least one search term"
  end

  def test_matching_all_with_whitespace_only_raises
    error = assert_raises(ArgumentError) { builder.match(:description, "   ") }
    assert_includes error.message, "at least one search term"
  end

  def test_match_any_with_no_terms_raises
    error = assert_raises(ArgumentError) { builder.match_any(:description) }
    assert_includes error.message, "at least one search term"
  end

  def test_phrase_prefix_with_no_terms_raises
    error = assert_raises(ArgumentError) { builder.phrase_prefix(:description) }
    assert_includes error.message, "phrase_prefix requires at least one term"
  end

  def test_phrase_prefix_with_empty_array_raises
    error = assert_raises(ArgumentError) { builder.phrase_prefix(:description, *[]) }
    assert_includes error.message, "phrase_prefix requires at least one term"
  end

  def test_phrase_prefix_with_nil_terms_raises
    error = assert_raises(ArgumentError) { builder.phrase_prefix(:description, nil, nil) }
    assert_includes error.message, "phrase_prefix requires at least one term"
  end

  # ──────────────────────────────────────────────
  # 4. Integer() coercion guards (SearchMethods)
  # ──────────────────────────────────────────────

  def test_with_snippet_max_chars_rejects_non_integer
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_snippet(:description, max_chars: "abc")
    end
    assert_match(/invalid value|ArgumentError/i, error.class.name)
  end

  def test_with_snippet_max_chars_accepts_integer
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_snippet(:description, max_chars: 100)
    refute_nil rel.to_sql
  end

  def test_facets_size_rejects_non_integer_string
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [:category], size: "abc")
    end
    assert_match(/invalid value|ArgumentError/i, error.class.name)
  end

  def test_more_like_this_rejects_unknown_option
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, unsupported_option: 2)
    end
    assert_includes error.message, "Unknown more_like_this option"
  end

  def test_more_like_this_rejects_non_integer_numeric_option
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, min_term_freq: "2")
    end
    assert_includes error.message, "min_term_frequency must be an Integer >= 1"
  end

  def test_more_like_this_rejects_out_of_range_numeric_option
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, min_term_freq: 0)
    end
    assert_includes error.message, "min_term_frequency must be an Integer >= 1"
  end

  def test_more_like_this_rejects_non_array_stopwords
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, stopwords: "the")
    end
    assert_includes error.message, "stopwords must be an Array of strings"
  end

  def test_more_like_this_rejects_non_string_stopword_terms
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, stopwords: ["the", 123])
    end
    assert_includes error.message, "stopwords must contain only strings"
  end

  def test_facets_requires_fields_or_agg
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [])
    end
    assert_includes error.message, "facets requires at least one field or agg"
  end

  def test_facets_rejects_duplicate_fields
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [:category, "category"])
    end
    assert_includes error.message, "Facet field names must be unique"
  end

  def test_facets_rejects_non_string_or_symbol_fields
    error = assert_raises(TypeError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [123])
    end
    assert_includes error.message, "Facet field names must be strings or symbols"
  end

  def test_facets_rejects_negative_size
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [:category], size: -1)
    end
    assert_includes error.message, "Facet size must be an integer greater than or equal to 0."
  end

  def test_facets_with_agg_ignores_fields
    facet_query = GuardTestProduct.search(:description)
                                  .matching_all("shoes")
                                  .build_facet_query(fields: [Object.new], agg: { "value_count" => { "field" => "id" } })
    assert_includes facet_query.sql, %(pdb.agg('{"value_count":{"field":"id"}}'))
  end

  # ──────────────────────────────────────────────
  # 5. Facet order validation (SearchMethods)
  # ──────────────────────────────────────────────

  def test_facets_with_invalid_order_raises
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [:category], order: "bogus")
    end
    assert_includes error.message, "Unknown facet order"
    assert_includes error.message, "bogus"
  end

  def test_facets_with_valid_orders_do_not_raise
    %w[-count count -key key].each do |order|
      facet_query = GuardTestProduct.search(:description)
                                    .matching_all("shoes")
                                    .build_facet_query(fields: [:category], order: order)
      refute_nil facet_query.sql
    end
  end

  def test_facets_with_nil_order_does_not_raise
    facet_query = GuardTestProduct.search(:description)
                                  .matching_all("shoes")
                                  .build_facet_query(fields: [:category], order: nil)
    refute_nil facet_query.sql
  end

  # ──────────────────────────────────────────────
  # 6. Agg JSON validation (SearchMethods)
  # ──────────────────────────────────────────────

  def test_with_facets_agg_rejects_non_hash_non_string
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_facets(:category, agg: 12345)
    end
    assert_includes error.message, "agg must be a Hash or JSON String"
  end

  def test_with_facets_agg_accepts_hash
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, agg: { "terms" => { "field" => "category" } })
                          .order(:id).limit(10)
    refute_nil rel.to_sql
  end

  def test_with_facets_agg_accepts_string
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, agg: '{"terms": {"field": "category"}}')
                          .order(:id).limit(10)
    refute_nil rel.to_sql
  end

  def test_facets_agg_rejects_non_hash_non_string
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .facets(:category, agg: Object.new)
    end
    assert_includes error.message, "agg must be a Hash or JSON String"
  end

  # ──────────────────────────────────────────────
  # 7. with_facets without order/limit (existing
  #    guard, adding coverage for completeness)
  # ──────────────────────────────────────────────

  def test_with_facets_missing_both_order_and_limit_raises
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, size: 10)
    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
    assert_includes error.message, "LIMIT"
  end

  def test_with_facets_missing_limit_only_raises
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, size: 10)
                          .order(:id)
    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "LIMIT"
  end

  def test_with_facets_missing_order_only_raises
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, size: 10)
                          .limit(10)
    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
  end
end
