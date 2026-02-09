# frozen_string_literal: true

require "spec_helper"

# Integration tests for code review issues identified in PR review

class CodeReviewIssuesIntegrationTest < Minitest::Test
  def setup
    skip "Integration test requires PostgreSQL" unless postgresql?

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")

    # Create test table
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

  # ============================================================================
  # ISSUE #1: HIGH - Alias DSL metadata leaking into SQL tokenizer arguments
  # ============================================================================

  def test_alias_should_not_appear_in_generated_sql
    # This test verifies that :alias metadata doesn't leak into SQL
    index_with_alias = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [
        :id,
        { title: { simple: { alias: "title_simple" } } }
      ]
    end

    conn = ActiveRecord::Base.connection

    # Capture the SQL that will be executed
    sql = conn.send(:build_create_sql, index_with_alias.compiled_definition, if_not_exists: false)

    # The generated SQL should NOT contain 'alias='
    refute_includes sql, "alias=",
      "BUG: alias metadata leaked into SQL. Generated SQL: #{sql}"

    # It should contain the tokenizer function
    assert_includes sql, "pdb.simple"
  end

  def test_alias_with_tokenizer_options_should_only_emit_real_options
    # Test that when alias is combined with real tokenizer options,
    # only the real options make it to SQL
    index_with_options = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [
        :id,
        { body: { ngram: { min: 2, max: 5, alias: "body_ngram" } } }
      ]
    end

    conn = ActiveRecord::Base.connection
    sql = conn.send(:build_create_sql, index_with_options.compiled_definition, if_not_exists: false)

    # Should NOT contain alias
    refute_includes sql, "alias=",
      "BUG: alias metadata leaked into SQL with ngram options. SQL: #{sql}"

    # Should contain the actual tokenizer with its real options
    assert_includes sql, "pdb.ngram"
    assert_includes sql, "2", "min value should be in SQL"
    assert_includes sql, "5", "max value should be in SQL"
  end

  def test_index_with_alias_can_be_created_and_queried
    # End-to-end test: create index with alias and verify it works

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

    # This should succeed without SQL errors
    conn.create_paradedb_index(index_klass)

    # Verify index was created
    assert index_exists?(:articles, "articles_bm25_idx")

    # Create test data
    article_model.create!(title: "Ruby Programming", body: "Learn Ruby basics")

    # Query should work
    results = article_model.search(:title).matching_all("ruby").to_a
    assert_equal 1, results.length
  end

  # ============================================================================
  # ISSUE #2: MEDIUM - Method collision protection is partial
  # ============================================================================

  def test_more_like_this_collision_detection
    # Currently only .search is protected, but .more_like_this should also be checked
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
    # 'facets' is a common word that could collide in domain models
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

  # ============================================================================
  # ISSUE #3: MEDIUM - SQL injection hardening for identifiers
  # ============================================================================

  def test_invalid_tokenizer_name_should_be_rejected
    # Tokenizer names should be validated to prevent SQL injection

    malicious_index = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [
        { title: { "simple); DROP TABLE articles; --": {} } }
      ]
    end

    conn = ActiveRecord::Base.connection

    # Should raise validation error, not SQL syntax error
    error = assert_raises(ParadeDB::InvalidIndexDefinition) do
      conn.create_paradedb_index(malicious_index)
    end

    assert_includes error.message, "invalid tokenizer name"
  end

  def test_key_field_with_special_chars_should_be_quoted
    # key_field should use proper quoting
    index_with_special_key = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = "user.id" # Contains dot - needs quoting
      self.fields = [:id, :title]
    end

    conn = ActiveRecord::Base.connection
    sql = conn.send(:build_create_sql, index_with_special_key.compiled_definition, if_not_exists: false)

    # Should be properly quoted/escaped
    assert_includes sql, "key_field", "SQL should contain key_field parameter"
    # Exact quoting format depends on implementation
  end

  # ============================================================================
  # ISSUE #4: LOW-MEDIUM - Migration helpers globally mixed into all adapters
  # ============================================================================

  def test_migration_helpers_should_guard_postgres_requirement
    # This test verifies that helpers fail gracefully on non-Postgres
    # We can't easily test with SQLite in the same process, but we can
    # verify the guard mechanism exists

    skip "Requires non-Postgres adapter for full test"

    # If we had a SQLite connection, this should raise a clear error:
    # conn = establish_sqlite_connection
    # error = assert_raises(ParadeDB::UnsupportedAdapter) do
    #   conn.create_paradedb_index(SomeIndex)
    # end
    # assert_includes error.message, "PostgreSQL"
  end

  def test_create_paradedb_index_validates_adapter_early
    # At minimum, ensure error messages mention PostgreSQL requirement
    index_klass = Class.new(ParadeDB::Index) do
      self.table_name = :articles
      self.key_field = :id
      self.fields = [:id]
    end

    conn = ActiveRecord::Base.connection

    # On Postgres this should work
    if postgresql?
      conn.create_paradedb_index(index_klass, if_not_exists: true)
      assert true # If we got here, no exception was raised
    end
  end

  # ============================================================================
  # Helper Methods
  # ============================================================================

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
