# frozen_string_literal: true

require "spec_helper"

class HybridRrfProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

RSpec.describe "HybridRrfIntegrationTest" do
  before do
    skip "Hybrid RRF integration test requires PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_products!
  end
  it "union all hybrid relation sql and weight behavior" do
    base_relation = hybrid_relation("running shoes", top_k: 5, limit: 10, rrf_k: 60, fulltext_weight: 1.0, structured_weight: 1.0)
    sql = base_relation.to_sql

    debug_log_sql(sql)

    normalized_sql = normalize_sql(sql).downcase
    assert_includes normalized_sql, "union all"
    assert_includes normalized_sql, "with fulltext as"
    assert_includes normalized_sql, "structured as"
    assert_includes normalized_sql, "sum(contributions.hybrid_rrf) as hybrid_score"

    base_rows = base_relation.to_a
    fulltext_boost_rows = hybrid_relation("running shoes", top_k: 5, limit: 10, rrf_k: 60, fulltext_weight: 3.0, structured_weight: 1.0).to_a
    structured_boost_rows = hybrid_relation("running shoes", top_k: 5, limit: 10, rrf_k: 60, fulltext_weight: 1.0, structured_weight: 3.0).to_a

    debug_log_rows("base (1.0/1.0)", base_rows)
    debug_log_rows("fulltext boost (3.0/1.0)", fulltext_boost_rows)
    debug_log_rows("structured boost (1.0/3.0)", structured_boost_rows)

    refute_empty base_rows
    refute_empty fulltext_boost_rows
    refute_empty structured_boost_rows

    [base_rows, fulltext_boost_rows, structured_boost_rows].each do |rows|
      rows.each do |row|
        assert_in_delta row.fulltext_rrf.to_f + row.structured_rrf.to_f, row.hybrid_score.to_f, 1e-12
      end
    end

    base_by_id = rows_by_id(base_rows)
    fulltext_boost_by_id = rows_by_id(fulltext_boost_rows)
    structured_boost_by_id = rows_by_id(structured_boost_rows)

    common_ids = base_by_id.keys & fulltext_boost_by_id.keys & structured_boost_by_id.keys
    refute_empty common_ids

    fulltext_only_id = common_ids.find do |id|
      row = base_by_id[id]
      !row.fulltext_rank.nil? && row.structured_rank.nil?
    end
    refute_nil fulltext_only_id, "Expected one fulltext-only row"

    structured_only_id = common_ids.find do |id|
      row = base_by_id[id]
      row.fulltext_rank.nil? && !row.structured_rank.nil?
    end
    refute_nil structured_only_id, "Expected one structured-only row"

    both_id = common_ids.find do |id|
      row = base_by_id[id]
      !row.fulltext_rank.nil? && !row.structured_rank.nil?
    end
    refute_nil both_id, "Expected one row present in both branches"

    base_fulltext_only = base_by_id.fetch(fulltext_only_id)
    fulltext_boost_fulltext_only = fulltext_boost_by_id.fetch(fulltext_only_id)
    structured_boost_fulltext_only = structured_boost_by_id.fetch(fulltext_only_id)

    assert_operator fulltext_boost_fulltext_only.hybrid_score.to_f, :>, base_fulltext_only.hybrid_score.to_f
    assert_in_delta base_fulltext_only.hybrid_score.to_f, structured_boost_fulltext_only.hybrid_score.to_f, 1e-12

    base_structured_only = base_by_id.fetch(structured_only_id)
    fulltext_boost_structured_only = fulltext_boost_by_id.fetch(structured_only_id)
    structured_boost_structured_only = structured_boost_by_id.fetch(structured_only_id)

    assert_in_delta base_structured_only.hybrid_score.to_f, fulltext_boost_structured_only.hybrid_score.to_f, 1e-12
    assert_operator structured_boost_structured_only.hybrid_score.to_f, :>, base_structured_only.hybrid_score.to_f

    base_both = base_by_id.fetch(both_id)
    fulltext_boost_both = fulltext_boost_by_id.fetch(both_id)
    structured_boost_both = structured_boost_by_id.fetch(both_id)

    assert_operator fulltext_boost_both.hybrid_score.to_f, :>, base_both.hybrid_score.to_f
    assert_operator structured_boost_both.hybrid_score.to_f, :>, base_both.hybrid_score.to_f
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def ensure_paradedb_setup!
    return if self.class.instance_variable_get(:@paradedb_setup_done)

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.execute("DROP INDEX IF EXISTS products_bm25_idx;")
    conn.execute(<<~SQL)
      CREATE INDEX products_bm25_idx ON products
      USING bm25 (id, description, category, rating, in_stock, price)
      WITH (key_field='id');
    SQL

    self.class.instance_variable_set(:@paradedb_setup_done, true)
  end

  def seed_products!
    conn = ActiveRecord::Base.connection
    conn.execute("TRUNCATE TABLE products RESTART IDENTITY;")

    HybridRrfProduct.create!(description: "running shoes lightweight", category: "footwear", rating: 5, in_stock: true, price: 120)
    HybridRrfProduct.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 90)
    HybridRrfProduct.create!(description: "wireless bluetooth earbuds", category: "audio", rating: 5, in_stock: true, price: 80)
    HybridRrfProduct.create!(description: "budget wired earbuds", category: "audio", rating: 3, in_stock: false, price: 20)
    HybridRrfProduct.create!(description: "hiking boots waterproof", category: "footwear", rating: 4, in_stock: true, price: 110)
    HybridRrfProduct.create!(description: "running socks breathable", category: "apparel", rating: 2, in_stock: true, price: 15)
  end

  def fulltext_ranked_cte(query, top_k:)
    fulltext_source = HybridRrfProduct.search(:description)
                                      .matching_all(*query.to_s.split(/\s+/))
                                      .with_score
                                      .order(search_score: :desc)
                                      .limit(top_k)

    HybridRrfProduct.unscoped
                    .from("(#{fulltext_source.to_sql}) AS fulltext_source")
                    .select("fulltext_source.id")
                    .select("ROW_NUMBER() OVER (ORDER BY fulltext_source.search_score DESC) AS rank_position")
  end

  def structured_ranked_cte(top_k:)
    structured_source = HybridRrfProduct.unscoped
                                        .order(price: :asc, id: :asc)
                                        .limit(top_k)

    HybridRrfProduct.unscoped
                    .from("(#{structured_source.to_sql}) AS structured_source")
                    .select("structured_source.id")
                    .select("ROW_NUMBER() OVER (ORDER BY structured_source.price ASC, structured_source.id ASC) AS rank_position")
  end

  def fulltext_contribution_cte(weight:, rrf_k:)
    weight_f = weight.to_f
    rrf_k_f = rrf_k.to_f
    contribution_sql = "#{weight_f}::float8 / (#{rrf_k_f}::float8 + fulltext.rank_position)"

    HybridRrfProduct.unscoped
                    .from("fulltext")
                    .select("fulltext.id")
                    .select("fulltext.rank_position AS fulltext_rank")
                    .select("NULL::integer AS structured_rank")
                    .select("#{contribution_sql} AS fulltext_rrf")
                    .select("0.0::float8 AS structured_rrf")
                    .select("#{contribution_sql} AS hybrid_rrf")
  end

  def structured_contribution_cte(weight:, rrf_k:)
    weight_f = weight.to_f
    rrf_k_f = rrf_k.to_f
    contribution_sql = "#{weight_f}::float8 / (#{rrf_k_f}::float8 + structured.rank_position)"

    HybridRrfProduct.unscoped
                    .from("structured")
                    .select("structured.id")
                    .select("NULL::integer AS fulltext_rank")
                    .select("structured.rank_position AS structured_rank")
                    .select("0.0::float8 AS fulltext_rrf")
                    .select("#{contribution_sql} AS structured_rrf")
                    .select("#{contribution_sql} AS hybrid_rrf")
  end

  def combined_scores_cte
    contributions_union_sql = "SELECT * FROM fulltext_contrib UNION ALL SELECT * FROM structured_contrib"

    HybridRrfProduct.unscoped
                    .from("(#{contributions_union_sql}) AS contributions")
                    .select("contributions.id")
                    .select("MAX(contributions.fulltext_rank) AS fulltext_rank")
                    .select("MAX(contributions.structured_rank) AS structured_rank")
                    .select("SUM(contributions.fulltext_rrf) AS fulltext_rrf")
                    .select("SUM(contributions.structured_rrf) AS structured_rrf")
                    .select("SUM(contributions.hybrid_rrf) AS hybrid_score")
                    .group("contributions.id")
  end

  def hybrid_relation(query, top_k:, limit:, rrf_k:, fulltext_weight:, structured_weight:)
    fulltext_cte = fulltext_ranked_cte(query, top_k: top_k)
    structured_cte = structured_ranked_cte(top_k: top_k)
    fulltext_contrib_cte = fulltext_contribution_cte(weight: fulltext_weight, rrf_k: rrf_k)
    structured_contrib_cte = structured_contribution_cte(weight: structured_weight, rrf_k: rrf_k)
    scores_cte = combined_scores_cte

    HybridRrfProduct.unscoped
                    .with(
                      fulltext: fulltext_cte,
                      structured: structured_cte,
                      fulltext_contrib: fulltext_contrib_cte,
                      structured_contrib: structured_contrib_cte,
                      hybrid_scores: scores_cte
                    )
                    .from("hybrid_scores")
                    .joins("JOIN products ON products.id = hybrid_scores.id")
                    .select(
                      "products.id",
                      "products.description",
                      "hybrid_scores.fulltext_rank",
                      "hybrid_scores.structured_rank",
                      "hybrid_scores.fulltext_rrf",
                      "hybrid_scores.structured_rrf",
                      "hybrid_scores.hybrid_score"
                    )
                    .order("hybrid_scores.hybrid_score DESC, products.id ASC")
                    .limit(limit)
  end

  def rows_by_id(rows)
    rows.each_with_object({}) { |row, hash| hash[row.id.to_i] = row }
  end

  def debug_log_sql(sql)
    return unless ENV["HYBRID_RRF_TEST_LOG_SQL"] == "1"

    puts "\n[HYBRID_RRF_TEST] SQL"
    puts sql
  end

  def debug_log_rows(label, rows)
    return unless ENV["HYBRID_RRF_TEST_LOG_SQL"] == "1"

    puts "\n[HYBRID_RRF_TEST] #{label}"
    rows.each_with_index do |row, index|
      puts format(
        "  %<rank>d. id=%<id>d hybrid=%<hybrid>.6f fulltext_rrf=%<fulltext>.6f structured_rrf=%<structured>.6f fulltext_rank=%<fulltext_rank>s structured_rank=%<structured_rank>s",
        rank: index + 1,
        id: row.id.to_i,
        hybrid: row.hybrid_score.to_f,
        fulltext: row.fulltext_rrf.to_f,
        structured: row.structured_rrf.to_f,
        fulltext_rank: row.fulltext_rank || "--",
        structured_rank: row.structured_rank || "--"
      )
    end
  end
end
