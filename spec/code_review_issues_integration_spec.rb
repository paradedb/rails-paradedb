# frozen_string_literal: true

require "spec_helper"

class CodeReviewIssuesIntegrationTest < Minitest::Test
  def setup
    skip "Integration test requires PostgreSQL" unless postgresql?

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :articles, force: true do |t|
          t.text :title
          t.text :body
          t.text :author
          t.jsonb :metadata, default: {}
        end
      end
    end
  end

  def teardown
    return unless postgresql?

    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:articles, if_exists: true) rescue nil
    conn.drop_table(:articles, if_exists: true) rescue nil
  end

  def test_alias_metadata_is_not_rendered_in_tokenizer_sql
    index_klass = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [
        :id,
        { title: { simple: { alias: "title_simple" } } }
      ]
    end

    conn = ActiveRecord::Base.connection
    sql = conn.send(:build_create_sql, index_klass.compiled_definition, if_not_exists: false)

    refute_includes sql, "alias="
    assert_includes sql, "pdb.simple"
  end

  def test_alias_with_tokenizer_options_emits_only_real_options
    index_klass = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [
        :id,
        { body: { ngram: { min: 2, max: 5, alias: "body_ngram" } } }
      ]
    end

    conn = ActiveRecord::Base.connection
    sql = conn.send(:build_create_sql, index_klass.compiled_definition, if_not_exists: false)

    refute_includes sql, "alias="
    assert_includes sql, "pdb.ngram"
    assert_includes sql, "2"
    assert_includes sql, "5"
  end

  def test_create_index_with_alias_and_query
    article_model = Class.new(ActiveRecord::Base) do
      self.table_name = :articles
      include ParadeDB::Model
    end

    index_klass = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [
        :id,
        { title: { simple: { alias: "title_text" } } },
        { body: { simple: {} } }
      ]
    end

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(index_klass)

    assert index_exists?(:articles, "articles_bm25_idx")

    article_model.create!(title: "Ruby Programming", body: "Learn Ruby basics")
    results = article_model.search(:title).matching_all("ruby").to_a
    assert_equal 1, results.length
  end

  def test_more_like_this_collision_detection
    error = assert_raises(ParadeDB::MethodCollisionError) do
      Class.new(ActiveRecord::Base) do
        self.table_name = :articles

        def self.more_like_this(_key, **_opts)
          :custom_implementation
        end

        include ParadeDB::Model
      end
    end

    assert_includes error.message, "more_like_this"
  end

  def test_with_facets_collision_detection
    error = assert_raises(ParadeDB::MethodCollisionError) do
      Class.new(ActiveRecord::Base) do
        self.table_name = :articles

        def self.with_facets(*_fields, **_opts)
          :custom_facets
        end

        include ParadeDB::Model
      end
    end

    assert_includes error.message, "with_facets"
  end

  def test_facets_collision_detection
    error = assert_raises(ParadeDB::MethodCollisionError) do
      Class.new(ActiveRecord::Base) do
        self.table_name = :articles

        def self.facets
          :domain_facets
        end

        include ParadeDB::Model
      end
    end

    assert_includes error.message, "facets"
  end

  def test_paradedb_arel_collision_detection
    error = assert_raises(ParadeDB::MethodCollisionError) do
      Class.new(ActiveRecord::Base) do
        self.table_name = :articles

        def self.paradedb_arel
          :custom_arel
        end

        include ParadeDB::Model
      end
    end

    assert_includes error.message, "paradedb_arel"
  end

  def test_rejects_invalid_tokenizer_name
    index_klass = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [
        { title: { "simple); DROP TABLE articles; --" => {} } }
      ]
    end

    conn = ActiveRecord::Base.connection
    error = assert_raises(ParadeDB::InvalidIndexDefinition) do
      conn.create_paradedb_index(index_klass)
    end

    assert_includes error.message, "invalid tokenizer name"
  end

  def test_build_sql_includes_key_field_with_special_chars
    index_klass = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = "user.id"
      self.fields = [:id, :title]
    end

    conn = ActiveRecord::Base.connection
    sql = conn.send(:build_create_sql, index_klass.compiled_definition, if_not_exists: false)

    assert_includes sql, "WITH (key_field='user.id')"
  end

  def test_create_paradedb_index_for_valid_definition
    index_klass = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [:id]
    end

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(index_klass, if_not_exists: true)

    assert index_exists?(:articles, "articles_bm25_idx")
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def index_exists?(table_name, index_name)
    sql = <<~SQL
      SELECT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = '#{index_name}'
        AND n.nspname = current_schema()
      )
    SQL
    ActiveRecord::Base.connection.select_value(sql)
  end
end
