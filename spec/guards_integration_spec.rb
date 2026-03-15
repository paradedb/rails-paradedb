# frozen_string_literal: true

require "spec_helper"

class GuardTestProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

RSpec.describe "GuardsUnitTest" do
  # ──────────────────────────────────────────────
  # 1. "No search field set" guards
  #    Every search method must raise when called
  #    on a relation without .search(column) first.
  # ──────────────────────────────────────────────

  def bare_relation
    GuardTestProduct.all.extending(ParadeDB::SearchMethods)
  end
  it "matching all without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.matching_all("shoes") }
    assert_includes error.message, "No search field set"
  end
  it "matching any without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.matching_any("shoes") }
    assert_includes error.message, "No search field set"
  end
  it "excluding without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.excluding("shoes") }
    assert_includes error.message, "No search field set"
  end
  it "phrase without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.phrase("running shoes") }
    assert_includes error.message, "No search field set"
  end
  it "fuzzy-style matching_any without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.matching_any("shoes", distance: 1) }
    assert_includes error.message, "No search field set"
  end
  it "regex without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.regex("run.*") }
    assert_includes error.message, "No search field set"
  end
  it "regex phrase without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.regex_phrase("run.*", "sho.*") }
    assert_includes error.message, "No search field set"
  end
  it "term without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.term("shoes") }
    assert_includes error.message, "No search field set"
  end
  it "term set without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.term_set("shoes") }
    assert_includes error.message, "No search field set"
  end
  it "near without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.near("running", anchor: "shoes", distance: 1) }
    assert_includes error.message, "No search field set"
  end
  it "phrase prefix without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.phrase_prefix("run") }
    assert_includes error.message, "No search field set"
  end
  it "parse without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.parse("running AND shoes") }
    assert_includes error.message, "No search field set"
  end
  it "match all without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.match_all }
    assert_includes error.message, "No search field set"
  end
  it "exists without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.exists }
    assert_includes error.message, "No search field set"
  end
  it "range without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.range(3..5) }
    assert_includes error.message, "No search field set"
  end
  it "range term without search raises" do
    error = assert_raises(ArgumentError) { bare_relation.range_term(1) }
    assert_includes error.message, "No search field set"
  end

  # ──────────────────────────────────────────────
  # 2. Numeric parameter validation (Builder)
  # ──────────────────────────────────────────────

  def builder
    @builder ||= ParadeDB::Arel::Builder.new(:products)
  end
  it "match boost rejects non numeric" do
    error = assert_raises(ArgumentError) { builder.match(:description, "shoes", boost: "high") }
    assert_includes error.message, "boost must be numeric"
  end
  it "match boost accepts numeric" do
    node = builder.match(:description, "shoes", boost: 2.5)
    refute_nil node
  end
  it "match boost accepts nil" do
    node = builder.match(:description, "shoes", boost: nil)
    refute_nil node
  end
  it "match tokenizer rejects non-string" do
    error = assert_raises(ArgumentError) { builder.match(:description, "shoes", tokenizer: 123) }
    assert_includes error.message, "tokenizer must be a string"
  end
  it "match tokenizer rejects invalid expression" do
    error = assert_raises(ArgumentError) { builder.match(:description, "shoes", tokenizer: "whitespace;drop") }
    assert_includes error.message, "invalid tokenizer expression"
  end
  it "match tokenizer rejects fuzzy distance combination" do
    error = assert_raises(ArgumentError) do
      builder.match(:description, "shoes", tokenizer: "whitespace", distance: 1)
    end
    assert_includes error.message, "tokenizer cannot be combined with fuzzy options"
  end
  it "match any tokenizer rejects fuzzy prefix combination" do
    error = assert_raises(ArgumentError) do
      builder.match_any(:description, "shoes", tokenizer: "whitespace", prefix: true)
    end
    assert_includes error.message, "tokenizer cannot be combined with fuzzy options"
  end
  it "phrase slop rejects non numeric" do
    error = assert_raises(ArgumentError) { builder.phrase(:description, "running shoes", slop: "lots") }
    assert_includes error.message, "slop must be numeric"
  end
  it "phrase tokenizer rejects non-string" do
    error = assert_raises(ArgumentError) { builder.phrase(:description, "running shoes", tokenizer: 123) }
    assert_includes error.message, "tokenizer must be a string"
  end
  it "phrase tokenizer rejects invalid expression" do
    error = assert_raises(ArgumentError) { builder.phrase(:description, "running shoes", tokenizer: "whitespace;drop") }
    assert_includes error.message, "invalid tokenizer expression"
  end
  it "phrase array rejects tokenizer" do
    error = assert_raises(ArgumentError) { builder.phrase(:description, %w[running shoes], tokenizer: "whitespace") }
    assert_includes error.message, "tokenizer is not supported for pretokenized phrase arrays"
  end
  it "phrase slop accepts integer" do
    node = builder.phrase(:description, "running shoes", slop: 2)
    refute_nil node
  end
  it "fuzzy distance on term rejects non numeric" do
    error = assert_raises(ArgumentError) { builder.term(:description, "shoes", distance: "far") }
    assert_includes error.message, "distance must be numeric"
  end
  it "fuzzy distance on term rejects out of range" do
    error = assert_raises(ArgumentError) { builder.term(:description, "shoes", distance: 5) }
    assert_includes error.message, "distance must be between 0 and 2"
  end
  it "fuzzy distance on matching_any rejects out of range" do
    error = assert_raises(ArgumentError) { builder.match_any(:description, "shoes", distance: 5) }
    assert_includes error.message, "distance must be between 0 and 2"
  end
  it "fuzzy boost on term rejects non numeric" do
    error = assert_raises(ArgumentError) { builder.term(:description, "shoes", distance: 1, boost: "high") }
    assert_includes error.message, "boost must be numeric"
  end
  it "fuzzy options on term accept valid numerics" do
    node = builder.term(:description, "shoes", distance: 2, boost: 1.5)
    refute_nil node
  end
  it "term boost rejects non numeric" do
    error = assert_raises(ArgumentError) { builder.term(:description, "shoes", boost: [1]) }
    assert_includes error.message, "boost must be numeric"
  end
  it "term set empty values raises" do
    error = assert_raises(ArgumentError) { builder.term_set(:description, []) }
    assert_includes error.message, "term_set requires at least one value"
  end
  it "near distance rejects non numeric" do
    error = assert_raises(ArgumentError) { builder.near(:description, "a", anchor: "b", distance: "close") }
    assert_includes error.message, "distance must be numeric"
  end
  it "near distance accepts integer" do
    node = builder.near(:description, "a", anchor: "b", distance: 3)
    refute_nil node
  end
  it "near regex max expansions rejects non integer" do
    error = assert_raises(ArgumentError) do
      builder.near(:description, ParadeDB.regex_term("sl.*", max_expansions: "100"), anchor: "shoes", distance: 1)
    end
    assert_includes error.message, "max_expansions must be an integer"
  end
  it "near rejects array right operand" do
    error = assert_raises(ArgumentError) { builder.near(:description, anchor: "shoes", distance: 1) }
    assert_includes error.message, "near requires at least one term"
  end
  it "range with no bounds raises" do
    error = assert_raises(ArgumentError) { builder.range(:rating) }
    assert_includes error.message, "range requires at least one bound"
  end
  it "range with conflicting lower bounds raises" do
    error = assert_raises(ArgumentError) { builder.range(:rating, nil, gte: 2, gt: 3) }
    assert_includes error.message, "gte and gt"
  end
  it "range with conflicting upper bounds raises" do
    error = assert_raises(ArgumentError) { builder.range(:rating, nil, lte: 5, lt: 4) }
    assert_includes error.message, "lte and lt"
  end
  it "range with explicit unknown type raises" do
    error = assert_raises(ArgumentError) { builder.range(:rating, 1..2, type: :bad) }
    assert_includes error.message, "Unknown range type"
  end
  it "range term relation requires range type" do
    error = assert_raises(ArgumentError) { builder.range_term(:weight_range, "(10, 12]", relation: "Intersects") }
    assert_includes error.message, "relation requires range_type"
  end
  it "range term rejects unknown relation" do
    error = assert_raises(ArgumentError) { builder.range_term(:weight_range, "(10, 12]", relation: "Overlap", range_type: "int4range") }
    assert_includes error.message, "Unknown range relation"
  end

  # ──────────────────────────────────────────────
  # 3. Empty terms guards (Builder)
  # ──────────────────────────────────────────────
  it "matching all with no terms raises" do
    error = assert_raises(ArgumentError) { builder.match(:description) }
    assert_includes error.message, "at least one search term"
  end
  it "matching all with empty string raises" do
    error = assert_raises(ArgumentError) { builder.match(:description, "") }
    assert_includes error.message, "at least one search term"
  end
  it "matching all with whitespace only raises" do
    error = assert_raises(ArgumentError) { builder.match(:description, "   ") }
    assert_includes error.message, "at least one search term"
  end
  it "match any with no terms raises" do
    error = assert_raises(ArgumentError) { builder.match_any(:description) }
    assert_includes error.message, "at least one search term"
  end
  it "term set with no terms raises" do
    error = assert_raises(ArgumentError) { builder.term_set(:description) }
    assert_includes error.message, "term_set requires at least one value"
  end
  it "phrase prefix with no terms raises" do
    error = assert_raises(ArgumentError) { builder.phrase_prefix(:description) }
    assert_includes error.message, "phrase_prefix requires at least one term"
  end
  it "phrase prefix with empty array raises" do
    terms = []
    error = assert_raises(ArgumentError) { builder.phrase_prefix(:description, *terms) }
    assert_includes error.message, "phrase_prefix requires at least one term"
  end
  it "phrase prefix with nil terms raises" do
    error = assert_raises(ArgumentError) { builder.phrase_prefix(:description, nil, nil) }
    assert_includes error.message, "phrase_prefix requires at least one term"
  end
  it "phrase array with no terms raises" do
    error = assert_raises(ArgumentError) { builder.phrase(:description, []) }
    assert_includes error.message, "phrase array input requires at least one term"
  end
  it "regex phrase with no patterns raises" do
    error = assert_raises(ArgumentError) { builder.regex_phrase(:description) }
    assert_includes error.message, "regex_phrase requires at least one pattern"
  end
  it "phrase prefix max expansion must be integer" do
    error = assert_raises(ArgumentError) { builder.phrase_prefix(:description, "run", max_expansion: "100") }
    assert_includes error.message, "max_expansion must be an integer"
  end

  # ──────────────────────────────────────────────
  # 4. Integer() coercion guards (SearchMethods)
  # ──────────────────────────────────────────────
  it "with snippet max chars rejects non integer" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_snippet(:description, max_chars: "abc")
    end
    assert_match(/invalid value|ArgumentError/i, error.class.name)
  end
  it "with snippet max chars accepts integer" do
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_snippet(:description, max_chars: 100)
    refute_nil rel.to_sql
  end
  it "with snippets max chars rejects non integer" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_snippets(:description, max_chars: "abc")
    end
    assert_includes error.message, "max_chars must be an integer"
  end
  it "with snippets limit rejects non integer" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_snippets(:description, limit: "abc")
    end
    assert_includes error.message, "limit must be an integer"
  end
  it "with snippets offset rejects non integer" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_snippets(:description, offset: "abc")
    end
    assert_includes error.message, "offset must be an integer"
  end
  it "with snippets sort by validates values" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_snippets(:description, sort_by: :unknown)
    end
    assert_includes error.message, "sort_by must be one of: score, position"
  end
  it "with snippets as rejects blank aliases" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_snippets(:description, as: "   ")
    end
    assert_includes error.message, "as cannot be blank"
  end
  it "with snippet positions as rejects blank aliases" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_snippet_positions(:description, as: "")
    end
    assert_includes error.message, "as cannot be blank"
  end
  it "term set relation rejects empty values" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:category).term_set
    end
    assert_includes error.message, "term_set requires at least one value"
  end
  it "facets size rejects non integer string" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [:category], size: "abc")
    end
    assert_match(/invalid value|ArgumentError/i, error.class.name)
  end
  it "more like this rejects unknown option" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, unsupported_option: 2)
    end
    assert_includes error.message, "Unknown more_like_this option"
  end
  it "more like this rejects non integer numeric option" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, min_term_freq: "2")
    end
    assert_includes error.message, "min_term_frequency must be an Integer >= 1"
  end
  it "more like this rejects out of range numeric option" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, min_term_freq: 0)
    end
    assert_includes error.message, "min_term_frequency must be an Integer >= 1"
  end
  it "more like this rejects non array stopwords" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, stopwords: "the")
    end
    assert_includes error.message, "stopwords must be an Array of strings"
  end
  it "more like this rejects non string stopword terms" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.more_like_this(1, stopwords: ["the", 123])
    end
    assert_includes error.message, "stopwords must contain only strings"
  end
  it "facets requires fields or agg" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [])
    end
    assert_includes error.message, "facets requires at least one field or agg"
  end
  it "facets rejects duplicate fields" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [:category, "category"])
    end
    assert_includes error.message, "Facet field names must be unique"
  end
  it "facets rejects non string or symbol fields" do
    error = assert_raises(TypeError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [123])
    end
    assert_includes error.message, "Facet field names must be strings or symbols"
  end
  it "facets rejects negative size" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [:category], size: -1)
    end
    assert_includes error.message, "Facet size must be an integer greater than or equal to 0."
  end
  it "facets with agg ignores fields" do
    facet_query = GuardTestProduct.search(:description)
                                  .matching_all("shoes")
                                  .build_facet_query(fields: [Object.new], agg: { "value_count" => { "field" => "id" } })
    assert_includes facet_query.sql, %(pdb.agg('{"value_count":{"field":"id"}}'))
  end
  it "facets exact false raises on non-windowed API" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description).matching_all("shoes").facets(:category, exact: false)
    end
    assert_includes error.message, "facets(exact: false)"
  end
  it "facets_agg exact false raises on non-windowed API" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .facets_agg(exact: false, docs: ParadeDB::Aggregations.value_count(:id))
    end
    assert_includes error.message, "facets_agg(exact: false)"
  end

  # ──────────────────────────────────────────────
  # 5. Facet order validation (SearchMethods)
  # ──────────────────────────────────────────────
  it "facets with invalid order raises" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .build_facet_query(fields: [:category], order: "bogus")
    end
    assert_includes error.message, "Unknown facet order"
    assert_includes error.message, "bogus"
  end
  it "facets with valid orders do not raise" do
    %i[count_desc count_asc key_desc key_asc].each do |order|
      facet_query = GuardTestProduct.search(:description)
                                    .matching_all("shoes")
                                    .build_facet_query(fields: [:category], order: order)
      refute_nil facet_query.sql
    end
  end
  it "facets with nil order does not raise" do
    facet_query = GuardTestProduct.search(:description)
                                  .matching_all("shoes")
                                  .build_facet_query(fields: [:category], order: nil)
    refute_nil facet_query.sql
  end

  # ──────────────────────────────────────────────
  # 6. Agg JSON validation (SearchMethods)
  # ──────────────────────────────────────────────
  it "with facets agg rejects non hash non string" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_facets(:category, agg: 12345)
    end
    assert_includes error.message, "agg must be a Hash or JSON String"
  end
  it "with facets agg accepts hash" do
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, agg: { "terms" => { "field" => "category" } })
                          .order(:id).limit(10)
    refute_nil rel.to_sql
  end
  it "with facets agg accepts string" do
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, agg: '{"terms": {"field": "category"}}')
                          .order(:id).limit(10)
    refute_nil rel.to_sql
  end
  it "facets agg rejects non hash non string" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .facets(:category, agg: Object.new)
    end
    assert_includes error.message, "agg must be a Hash or JSON String"
  end
  it "with agg rejects empty payload" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_agg
    end
    assert_includes error.message, "at least one named aggregation"
  end
  it "with agg rejects multi-key aggregation specs" do
    error = assert_raises(ArgumentError) do
      GuardTestProduct.search(:description)
                      .matching_all("shoes")
                      .with_agg(
                        broken: { value_count: { field: "id" }, avg: { field: "rating" } }
                      )
    end
    assert_includes error.message, "exactly one top-level key"
  end

  # ──────────────────────────────────────────────
  # 7. with_facets without order/limit (existing
  #    guard, adding coverage for completeness)
  # ──────────────────────────────────────────────
  it "with facets missing both order and limit raises" do
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, size: 10)
    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
    assert_includes error.message, "LIMIT"
  end
  it "with facets missing limit only raises" do
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, size: 10)
                          .order(:id)
    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "LIMIT"
  end
  it "with facets missing order only raises" do
    rel = GuardTestProduct.search(:description)
                          .matching_all("shoes")
                          .with_facets(:category, size: 10)
                          .limit(10)
    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
  end
end
