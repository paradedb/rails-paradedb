# frozen_string_literal: true

require "spec_helper"

RSpec.describe "AggregationsUnitTest" do
  it "builds named payload with helper specs" do
    payload = ParadeDB::Aggregations.build_named_payload(
      docs: ParadeDB::Aggregations.value_count(:id),
      avg_rating: ParadeDB::Aggregations.avg(:rating),
      by_rating: ParadeDB::Aggregations.range(:rating, ranges: [{ to: 3 }, { from: 3, to: 6 }])
    )

    assert_equal ["docs", "avg_rating", "by_rating"], payload.keys
    assert_equal({ "value_count" => { "field" => "id" } }, payload["docs"])
    assert_equal({ "avg" => { "field" => "rating" } }, payload["avg_rating"])
    assert_includes payload["by_rating"], "range"
  end

  it "supports histogram and date_histogram helpers" do
    histogram = ParadeDB::Aggregations.histogram(:rating, interval: 1)
    date_histogram = ParadeDB::Aggregations.date_histogram(:created_at, fixed_interval: "30d")

    assert_equal({ "histogram" => { "field" => "rating", "interval" => 1 } }, histogram)
    assert_equal({ "date_histogram" => { "field" => "created_at", "fixed_interval" => "30d" } }, date_histogram)
  end

  it "rejects empty named payload" do
    error = assert_raises(ArgumentError) { ParadeDB::Aggregations.build_named_payload({}) }
    assert_includes error.message, "at least one named aggregation"
  end

  it "rejects specs with multiple top-level keys" do
    error = assert_raises(ArgumentError) do
      ParadeDB::Aggregations.build_named_payload(
        broken: { "value_count" => { "field" => "id" }, "avg" => { "field" => "rating" } }
      )
    end
    assert_includes error.message, "exactly one top-level key"
  end
end
