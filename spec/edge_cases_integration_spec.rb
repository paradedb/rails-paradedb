# frozen_string_literal: true

require "spec_helper"

class EdgeProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

class EdgeCasesIntegrationTest < Minitest::Test
  def setup
    skip "Edge-case integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_edge_case_products!
  end

  # ──────────────────────────────────────────────
  # 1. NULLs
  # ──────────────────────────────────────────────

  def test_null_description_invisible_to_text_search
    ids = search(:description).matching_all("alpha").order(:id).pluck(:id)
    assert_includes ids, @p_null_cat.id
    refute_includes ids, @p_null_desc.id
    refute_includes ids, @p_both_null.id
  end

  def test_null_description_invisible_to_phrase_and_fuzzy
    phrase_ids = search(:description).phrase("alpha beta").order(:id).pluck(:id)
    fuzzy_ids  = search(:description).fuzzy("alph", distance: 1, prefix: true).order(:id).pluck(:id)
    regex_ids  = search(:description).regex("alpha.*").order(:id).pluck(:id)

    [phrase_ids, fuzzy_ids, regex_ids].each do |ids|
      refute_includes ids, @p_null_desc.id
      refute_includes ids, @p_both_null.id
    end
  end

  def test_match_all_returns_null_rows
    ids = search(:id).match_all.order(:id).pluck(:id)
    assert_includes ids, @p_null_desc.id
    assert_includes ids, @p_null_cat.id
    assert_includes ids, @p_both_null.id
  end

  def test_facets_with_missing_counts_null_categories
    facets = search(:id).match_all.facets(:category, size: 100, missing: "N/A")
    assert_kind_of Hash, facets
    assert_includes facets, "category"
  end

  def test_more_like_this_on_null_description_raises
    assert_raises(ActiveRecord::StatementInvalid) do
      EdgeProduct.more_like_this(@p_null_desc.id, fields: [:description]).limit(5).pluck(:id)
    end
  end

  # ──────────────────────────────────────────────
  # 2. Empty strings
  # ──────────────────────────────────────────────

  def test_empty_string_description_not_matched_by_text_queries
    term_ids  = search(:description).term("anything").order(:id).pluck(:id)
    regex_ids = search(:description).regex(".*").order(:id).pluck(:id)

    refute_includes term_ids, @p_empty_desc.id
    refute_includes regex_ids, @p_empty_desc.id
  end

  def test_empty_string_returned_by_match_all
    ids = search(:id).match_all.order(:id).pluck(:id)
    assert_includes ids, @p_empty_desc.id
  end

  def test_empty_string_with_snippet_does_not_crash
    rows = search(:id).match_all
             .with_snippet(:description)
             .order(:id).limit(50).to_a

    empty_row = rows.find { |r| r.id == @p_empty_desc.id }
    refute_nil empty_row
  end

  # ──────────────────────────────────────────────
  # 3. Long text (1000+ words)
  # ──────────────────────────────────────────────

  def test_long_text_phrase_finds_unique_needle
    ids = search(:description).phrase("ultra rare needlephrase").order(:id).pluck(:id)
    assert_equal [@p_long.id], ids
  end

  def test_long_text_phrase_prefix_finds_needle
    ids = search(:description).phrase_prefix("ultra", "rare", "needle").order(:id).pluck(:id)
    assert_includes ids, @p_long.id
  end

  def test_long_text_fuzzy_finds_misspelled_needle
    ids = search(:description).fuzzy("needlephras", distance: 2).order(:id).pluck(:id)
    assert_includes ids, @p_long.id
  end

  def test_long_text_near_finds_needle_terms
    ids = search(:description).near("ultra", "needlephrase", distance: 5).order(:id).pluck(:id)
    assert_includes ids, @p_long.id
  end

  def test_long_text_with_score_ranks_unique_term_higher
    rows = search(:description).matching_any("needlephrase")
             .with_score.order(search_score: :desc).limit(10).to_a
    refute_empty rows
    assert_equal @p_long.id, rows.first.id
    assert rows.first.search_score.to_f > 0
  end

  def test_long_text_snippet_is_bounded_and_highlights
    rows = search(:description).matching_all("needlephrase")
             .with_snippet(:description, start_tag: "<b>", end_tag: "</b>", max_chars: 200)
             .order(:id).to_a

    refute_empty rows
    snippet = rows.first.description_snippet.to_s
    assert snippet.length < rows.first.description.length,
           "Snippet should be shorter than full long text"
  end

  def test_long_text_more_like_this_prefers_similar_doc
    ids = EdgeProduct.more_like_this(@p_long.id, fields: [:description]).limit(5).pluck(:id)
    assert_includes ids, @p_long_similar.id
  end

  # ──────────────────────────────────────────────
  # 4. Unicode (CJK, emoji, accented)
  # ──────────────────────────────────────────────

  def test_unicode_accented_matching
    ids = search(:description).matching_any("café").order(:id).pluck(:id)
    assert_includes ids, @p_unicode.id
  end

  def test_unicode_cjk_matching
    ids = search(:description).matching_any("漢字").order(:id).pluck(:id)
    assert_includes ids, @p_unicode.id
  end

  def test_unicode_phrase_with_accents
    ids = search(:description).phrase("café naïve").order(:id).pluck(:id)
    assert_includes ids, @p_unicode.id
  end

  def test_unicode_regex_accented_does_not_crash
    ids = search(:description).regex("résum.").order(:id).pluck(:id)
    assert_kind_of Array, ids
  end

  def test_unicode_term_case_sensitivity
    lower_ids = search(:description).term("mixedcasetoken").order(:id).pluck(:id)
    upper_ids = search(:description).term("MiXeDCaSeToken").order(:id).pluck(:id)

    assert_includes lower_ids, @p_unicode.id
    refute_includes upper_ids, @p_unicode.id
  end

  def test_unicode_with_snippet_does_not_produce_invalid_output
    rows = search(:description).matching_any("café")
             .with_snippet(:description, start_tag: "<b>", end_tag: "</b>")
             .order(:id).to_a

    refute_empty rows
    rows.each do |row|
      snippet = row.description_snippet.to_s
      assert snippet.valid_encoding?, "Snippet must be valid UTF-8"
    end
  end

  def test_unicode_category_appears_in_facets
    facets = search(:id).match_all.facets(:category, size: 200)
    assert_kind_of Hash, facets
    assert_includes facets, "category"
    json = facets["category"].to_json
    assert_match(/café/, json)
  end

  # ──────────────────────────────────────────────
  # 5. Punctuation-heavy text
  # ──────────────────────────────────────────────

  def test_punctuation_tokenized_at_word_boundaries
    # "end" is a token in both: @p_punct has {c,end,to,end,foo.bar,can't,json,xml,test}
    # @p_plain has {end,to,end,foo,bar,cant,json,xml,test,plain}
    ids = search(:description).matching_any("end").order(:id).pluck(:id)
    assert_includes ids, @p_punct.id
    assert_includes ids, @p_plain.id
  end

  def test_punctuation_parse_does_not_choke
    ids = search(:description).parse("test AND end", lenient: true).order(:id).pluck(:id)
    assert_kind_of Array, ids
    assert_includes ids, @p_punct.id
    assert_includes ids, @p_plain.id
  end

  def test_punctuation_regex_with_escaped_special_chars
    ids = search(:description).regex("json").order(:id).pluck(:id)
    assert_includes ids, @p_punct.id
    assert_includes ids, @p_plain.id
  end

  def test_punctuation_excluding_works
    # "plain" only exists in @p_plain, so excluding "plain" should remove @p_plain
    ids = search(:description).matching_all("test")
            .excluding("plain")
            .order(:id).pluck(:id)
    assert_includes ids, @p_punct.id
    refute_includes ids, @p_plain.id
  end

  # ──────────────────────────────────────────────
  # 6. Duplicated tokens
  # ──────────────────────────────────────────────

  def test_duplicated_tokens_both_matched
    ids = search(:description).matching_any("spam").order(:id).pluck(:id)
    assert_includes ids, @p_dupe_tokens.id
    assert_includes ids, @p_single_spam.id
    refute_includes ids, @p_no_spam.id
  end

  def test_duplicated_tokens_score_higher_for_more_occurrences
    rows = search(:description).matching_any("spam")
             .with_score.order(search_score: :desc).to_a

    dupe_row   = rows.find { |r| r.id == @p_dupe_tokens.id }
    single_row = rows.find { |r| r.id == @p_single_spam.id }

    refute_nil dupe_row
    refute_nil single_row
    assert_operator dupe_row.search_score.to_f, :>, single_row.search_score.to_f,
                    "Document with more 'spam' occurrences should score higher"
  end

  def test_duplicated_tokens_phrase_matches_repeated_adjacent
    ids = search(:description).phrase("spam spam").order(:id).pluck(:id)
    assert_includes ids, @p_dupe_tokens.id
    refute_includes ids, @p_single_spam.id
  end

  def test_duplicated_tokens_excluding_removes_correctly
    ids = search(:description).matching_all("spam")
            .excluding("eggs")
            .order(:id).pluck(:id)

    refute_includes ids, @p_single_spam.id
  end

  def test_duplicated_tokens_more_like_this_prefers_overlap
    ids = EdgeProduct.more_like_this(@p_dupe_tokens.id, fields: [:description]).limit(5).pluck(:id)
    assert_includes ids, @p_single_spam.id
  end

  # ──────────────────────────────────────────────
  # 7. Skewed cardinality
  # ──────────────────────────────────────────────

  def test_skewed_facets_reflect_counts
    facets = search(:id).match_all.facets(:category, size: 200)
    assert_kind_of Hash, facets
    json = facets["category"].to_json
    assert_match(/bulk/, json)
  end

  def test_skewed_matching_all_within_bulk_category
    ids = search(:description).matching_all("bulkneedle")
            .where(category: "bulk")
            .order(:id).pluck(:id)

    refute_empty ids
    ids.each do |id|
      assert_includes @bulk_ids, id
    end
  end

  def test_skewed_excluding_noop_term
    all_ids = search(:description).matching_all("bulkneedle").order(:id).pluck(:id)
    exc_ids = search(:description).matching_all("bulkneedle")
                .excluding("zzzneverexists")
                .order(:id).pluck(:id)

    assert_equal all_ids, exc_ids
  end

  # ──────────────────────────────────────────────
  # 8. High bucket cardinality facets (60 categories)
  # ──────────────────────────────────────────────

  def test_high_cardinality_facets_returns_all_buckets
    facets = search(:description).matching_any("facetneedle")
               .facets(:category, size: 200)

    assert_kind_of Hash, facets
    assert_includes facets, "category"
    result = facets["category"]
    json = result.to_json
    unique_cats = (0...60).select { |i| json.include?("cat_%02d" % i) }
    assert unique_cats.length >= 60,
           "Expected at least 60 unique category buckets, got #{unique_cats.length}"
  end

  def test_high_cardinality_facets_respects_size_limit
    facets = search(:description).matching_any("facetneedle")
               .facets(:category, size: 5)

    result = facets["category"]
    result_keys = result.is_a?(Array) ? result : result.keys
    assert result_keys.length <= 5,
           "Expected at most 5 buckets with size: 5, got #{result_keys.length}"
  end

  def test_high_cardinality_facets_with_where_filter
    facets = search(:description).matching_any("facetneedle")
               .where("price > ?", 25)
               .facets(:category, size: 200)

    assert_kind_of Hash, facets
    assert_includes facets, "category"
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def search(column)
    EdgeProduct.search(column)
  end

  def ensure_paradedb_setup!
    return if self.class.instance_variable_get(:@paradedb_setup_done)

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.execute("DROP INDEX IF EXISTS products_bm25_idx;")
    conn.execute(<<~SQL)
      CREATE INDEX products_bm25_idx ON products
      USING bm25 (id, description, (category::pdb.literal), rating, in_stock, price)
      WITH (key_field='id');
    SQL

    self.class.instance_variable_set(:@paradedb_setup_done, true)
  end

  def seed_edge_case_products!
    conn = ActiveRecord::Base.connection
    conn.execute("TRUNCATE TABLE products RESTART IDENTITY;")

    # -- 1. NULLs --
    @p_null_desc = EdgeProduct.create!(description: nil, category: "null-desc", rating: 3, in_stock: true, price: 10)
    @p_null_cat  = EdgeProduct.create!(description: "alpha beta gamma", category: nil, rating: 4, in_stock: true, price: 20)
    @p_both_null = EdgeProduct.create!(description: nil, category: nil, rating: 1, in_stock: false, price: 5)

    # -- 2. Empty strings --
    @p_empty_desc = EdgeProduct.create!(description: "", category: "empty-desc", rating: 2, in_stock: true, price: 10)

    # -- 3. Long text --
    filler = (1..200).map { |i| "word#{i}" }.join(" ")
    long_desc = "#{filler} ultra rare needlephrase #{filler} more content here #{filler}"
    @p_long = EdgeProduct.create!(description: long_desc, category: "long-text", rating: 5, in_stock: true, price: 50)

    similar_filler = (1..200).map { |i| "word#{i}" }.join(" ")
    @p_long_similar = EdgeProduct.create!(description: "#{similar_filler} common overlap text #{similar_filler}", category: "long-text", rating: 4, in_stock: true, price: 45)

    # -- 4. Unicode --
    @p_unicode = EdgeProduct.create!(
      description: "漢字かな交じり文 café naïve résumé MiXeDCaSeToken 🍣🔥",
      category: "café",
      rating: 5,
      in_stock: true,
      price: 30
    )

    # -- 5. Punctuation --
    @p_punct = EdgeProduct.create!(
      description: "C++ end-to-end foo.bar can't JSON/XML (test) --- !!!",
      category: "punctuation",
      rating: 3,
      in_stock: true,
      price: 15
    )
    @p_plain = EdgeProduct.create!(
      description: "end to end foo bar cant json xml test plain",
      category: "plain",
      rating: 3,
      in_stock: true,
      price: 15
    )

    # -- 6. Duplicated tokens --
    @p_dupe_tokens  = EdgeProduct.create!(description: "spam spam spam spam eggs", category: "dupes", rating: 2, in_stock: true, price: 5)
    @p_single_spam  = EdgeProduct.create!(description: "spam eggs", category: "dupes", rating: 2, in_stock: true, price: 5)
    @p_no_spam      = EdgeProduct.create!(description: "eggs only nothing else", category: "dupes", rating: 2, in_stock: true, price: 5)

    # -- 7. Skewed cardinality (30 bulk rows) --
    @bulk_ids = []
    30.times do |i|
      p = EdgeProduct.create!(
        description: i < 10 ? "bulkneedle bulk product item #{i}" : "bulk product item #{i}",
        category: "bulk",
        rating: (i % 5) + 1,
        in_stock: i.even?,
        price: 10 + i
      )
      @bulk_ids << p.id
    end

    EdgeProduct.create!(description: "rare item alpha", category: "rare_a", rating: 5, in_stock: true, price: 100)
    EdgeProduct.create!(description: "rare item beta", category: "rare_b", rating: 4, in_stock: true, price: 90)

    # -- 8. High bucket cardinality (60 unique categories) --
    60.times do |i|
      EdgeProduct.create!(
        description: "facetneedle product in cat #{i}",
        category: "cat_%02d" % i,
        rating: (i % 5) + 1,
        in_stock: i.even?,
        price: 10 + i
      )
    end

    # Force BM25 index rebuild by dropping and recreating
    self.class.instance_variable_set(:@paradedb_setup_done, false)
    ensure_paradedb_setup!
  end
end
