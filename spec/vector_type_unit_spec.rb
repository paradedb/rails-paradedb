# frozen_string_literal: true

require "spec_helper"

RSpec.describe "VectorTypeUnitTest" do
  before do
    @type = ParadeDB::Vector.new
  end

  it "reports the vector type" do
    assert_equal :vector, @type.type
    assert_nil @type.limit
    assert_equal 3, ParadeDB::Vector.new(limit: 3).limit
  end

  it "is registered in the postgresql adapter type map" do
    map = ActiveRecord::Type::HashLookupTypeMap.new
    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.initialize_type_map(map)

    resolved = map.lookup("vector", nil, "vector(3)")
    assert_instance_of ParadeDB::Vector, resolved
    assert_equal 3, resolved.limit

    unlimited = map.lookup("vector", nil, "vector")
    assert_nil unlimited.limit
  end

  it "casts arrays to floats" do
    assert_equal [1.0, 2.0, 3.0], @type.cast([1, 2, 3])
    assert_equal [1.5, -2.25], @type.cast(["1.5", "-2.25"])
    assert_nil @type.cast(nil)
  end

  it "casts pgvector text literals" do
    assert_equal [1.0, 2.0, 3.0], @type.cast("[1,2,3]")
    assert_equal [0.25, -1.0], @type.cast(" [0.25, -1] ")
  end

  it "rejects malformed literals" do
    error = assert_raises(ArgumentError) { @type.cast("1,2,3") }
    assert_includes error.message, "malformed vector literal"
  end

  it "rejects uncastable values" do
    error = assert_raises(ArgumentError) { @type.cast(1.0) }
    assert_includes error.message, "cannot cast"
  end

  it "serializes to pgvector text form" do
    assert_equal "[1.0,2.0,3.0]", @type.serialize([1, 2, 3])
    assert_equal "[1.0,2.0,3.0]", @type.serialize("[1,2,3]")
    assert_nil @type.serialize(nil)
  end

  it "deserializes database values" do
    assert_equal [1.0, 2.0, 3.0], @type.deserialize("[1,2,3]")
  end

  it "validates dimensions against the limit" do
    limited = ParadeDB::Vector.new(limit: 3)
    assert_equal [1.0, 2.0, 3.0], limited.cast([1, 2, 3])

    error = assert_raises(ArgumentError) { limited.cast([1, 2]) }
    assert_includes error.message, "expected 3 dimensions, got 2"
  end

  it "detects in-place changes" do
    assert @type.changed_in_place?("[1,2,3]", [1.0, 2.0, 4.0])
    assert_not @type.changed_in_place?("[1,2,3]", [1.0, 2.0, 3.0])
  end

  it "renders vector(n) in DDL type SQL" do
    conn = ActiveRecord::Base.connection
    assert_equal "vector(3)", conn.type_to_sql(:vector, limit: 3)
    assert_equal "vector", conn.type_to_sql(:vector)
    assert conn.valid_type?(:vector)
  end

  it "exposes t.vector in table definitions" do
    assert ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.method_defined?(:vector)
  end

  it "normalizes metrics" do
    assert_equal :l2, ParadeDB::Vector.normalize_metric(:l2)
    assert_equal :cosine, ParadeDB::Vector.normalize_metric("cosine")
    assert_equal :ip, ParadeDB::Vector.normalize_metric(:ip)
    assert_equal :ip, ParadeDB::Vector.normalize_metric(:inner_product)

    error = assert_raises(ArgumentError) { ParadeDB::Vector.normalize_metric(:manhattan) }
    assert_includes error.message, "unknown vector metric"
  end

  it "builds pgvector literals" do
    assert_equal "[1.0,2.0,3.0]", ParadeDB::Vector.literal([1, 2, 3])
  end
end
