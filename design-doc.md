# ParadeDB for Rails: Option B (Base ActiveRecord API)

### Overview

A Rails-native integration for ParadeDB that follows established patterns like the `neighbor` gem (pgvector). Models declare their ParadeDB index to gain search capabilities.

Core abstractions:

1. `has_paradedb_index` - Model declaration that enables ParadeDB search methods (similar to `has_neighbors` in pgvector)
2. `.search()` - Available on the model and relations; returns an `ActiveRecord::Relation` with ParadeDB search methods
3. `.matching()`, `.excluding()`, `.phrase()`, `.fuzzy()`, `.regex()`, `.term()` - Search methods on the relation
4. `add_bm25_index` / `remove_bm25_index` - Migration helpers for creating BM25 indexes

## Setup & Indexing

BM25 indexes are created using Rails migrations, following the same patterns as standard ActiveRecord indexes.

> **Note:** ParadeDB allows only one BM25 index per table. The index name is automatically derived as `{table_name}_bm25_idx` (e.g., `products_bm25_idx`). You can override this with the optional `name:` parameter.

### Creating a Table with BM25 Index

```ruby
# db/migrate/20260101000000_create_products.rb
class CreateProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :products do |t|
      t.text :description
      t.string :category
      t.integer :rating
      t.boolean :in_stock, default: false
      t.decimal :price, precision: 10, scale: 2
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    # Name defaults to "products_bm25_idx"
    add_bm25_index :products,
      fields: {
        id: {},
        description: { tokenizer: "simple", stemmer: "English", lowercase: true },
        category: { tokenizer: "simple", lowercase: true },
      },
      key_field: :id
  end
end
```

Generated SQL:

```sql
CREATE INDEX products_bm25_idx ON products
  USING bm25 (
    id,
    (description::pdb.simple('stemmer=English', 'lowercase=true')),
    (category::pdb.simple('lowercase=true'))
  )
  WITH (key_field='id');
```

### Adding BM25 Index to Existing Table

```ruby
# db/migrate/20260115000000_add_search_index_to_products.rb
class AddSearchIndexToProducts < ActiveRecord::Migration[7.1]
  def change
    add_bm25_index :products,
      fields: {
        id: {},
        description: { tokenizer: "simple", stemmer: "English", lowercase: true },
        category: { tokenizer: "simple", lowercase: true },
      },
      key_field: :id
  end
end
```

### Removing a BM25 Index

```ruby
# db/migrate/20260201000000_remove_search_index_from_products.rb
class RemoveSearchIndexFromProducts < ActiveRecord::Migration[7.1]
  def change
    # No name needed - only one BM25 index per table
    remove_bm25_index :products
  end
end
```

### Idempotent Migrations

Use `if_not_exists` and `if_exists` options for idempotent migrations:

```ruby
# Only create if index doesn't exist
add_bm25_index :products, fields: { ... }, if_not_exists: true

# Only remove if index exists
remove_bm25_index :products, if_exists: true
```

Generated SQL:

```sql
CREATE INDEX IF NOT EXISTS products_bm25_idx ON products USING bm25 (...);
DROP INDEX IF EXISTS products_bm25_idx;
```

### Reindexing

Use `reindex_bm25` to rebuild an index after schema changes (e.g., adding fields, changing tokenizers):

```ruby
# Blocking reindex (locks table for writes)
reindex_bm25 :products

# Non-blocking reindex (slower but allows concurrent writes)
reindex_bm25 :products, concurrently: true
```

Generated SQL:

```sql
REINDEX INDEX products_bm25_idx;
REINDEX INDEX CONCURRENTLY products_bm25_idx;
```

> **Note:** `REINDEX CONCURRENTLY` requires the session to remain open until completion. If using a connection pooler like PgBouncer, ensure the session isn't terminated mid-reindex.

### Reversible Migrations (Up/Down)

For complex migrations where automatic reversal isn't possible:

```ruby
# db/migrate/20260201000000_rebuild_search_index.rb
class RebuildSearchIndex < ActiveRecord::Migration[7.1]
  def up
    remove_bm25_index :products, if_exists: true

    add_bm25_index :products,
      fields: {
        id: {},
        description: { tokenizer: "simple", filters: ["lowercase", "stemmer"] },
        category: { tokenizer: "simple", filters: ["lowercase"] },
        # Adding new field to index
        brand: { tokenizer: "simple", filters: ["lowercase"] },
      },
      key_field: :id
  end

  def down
    remove_bm25_index :products

    add_bm25_index :products,
      fields: {
        id: {},
        description: { tokenizer: "simple", filters: ["lowercase", "stemmer"] },
        category: { tokenizer: "simple", filters: ["lowercase"] },
      },
      key_field: :id
  end
end
```

### Schema Dumping

The BM25 index will be represented in `db/schema.rb`:

```ruby
# db/schema.rb (auto-generated)
create_table "products", force: :cascade do |t|
  t.text "description"
  t.string "category"
  t.integer "rating"
  t.boolean "in_stock", default: false
  t.decimal "price", precision: 10, scale: 2
  t.jsonb "metadata", default: {}
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
end

add_bm25_index "products",
  fields: { id: {}, description: { tokenizer: "simple" }, category: { tokenizer: "simple" } },
  key_field: "id"
```

## Model Configuration

After creating the BM25 index in a migration, declare it in your model using `has_paradedb_index`. Since only one BM25 index can exist per table, no additional configuration is needed - fields and key_field are introspected from the database.

### Basic Declaration

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  has_paradedb_index  # All metadata introspected from database
end
```

### What `has_paradedb_index` Provides

| Feature | Description |
|---------|-------------|
| **`.search()` method** | Adds class + relation methods that return a chainable ActiveRecord relation |
| **Field validation** | Raises `ParadeDB::FieldNotIndexed` if you search on a non-indexed field |
| **Lazy introspection** | Index metadata (fields, key_field) introspected from DB on first use |
| **Introspection API** | `Product.paradedb_indexed_fields`, `Product.paradedb_key_field`, etc. |

### Validation Example

Validation uses introspected fields to check that searched columns are actually indexed.

```ruby
# This works - description is indexed
Product.search(:description).matching("shoes")

# This raises ParadeDB::FieldNotIndexed - title is not in the index
Product.search(:title).matching("shoes")
#=> ParadeDB::FieldNotIndexed: Field 'title' is not included in the
#   'products_bm25_idx' index. Indexed fields: [:description, :category]
```

### Introspection API

```ruby
Product.paradedb_indexed_fields
#=> [:id, :description, :category]  # Introspected from database

Product.paradedb_key_field
#=> :id  # Introspected from WITH (key_field='id')

Product.paradedb_index_name
#=> "products_bm25_idx"  # Auto-derived from table name

Product.has_paradedb_index?
#=> true
```

### Database Introspection (Implementation Note)

The gem will introspect BM25 index metadata from PostgreSQL system catalogs using `pg_get_indexdef()`:

1. **Query `pg_class` + `pg_index`** to find BM25 indexes on the table (where `pg_am.amname = 'bm25'`)
2. **Use `pg_get_indexdef(oid)`** to get the full CREATE INDEX statement
3. **Parse the SQL** to extract:
   - `key_field` from `WITH (key_field='...')`
   - Indexed fields/expressions from the column list
   - Tokenizer configurations from casts like `::pdb.literal`
4. **Cache results** on the model class after first introspection

This approach avoids duplicating field definitions between migrations and models, following ActiveRecord's pattern of introspecting columns from the database rather than requiring explicit declarations.

## BM25 Index Options

### Text Fields with Tokenizer Options

```ruby
add_bm25_index :products,
  fields: {
    id: {},
    description: {
      tokenizer: "simple",
      filters: ["lowercase", "stemmer"],
    },
    category: {
      tokenizer: "simple",
      filters: ["lowercase"],
    },
  },
  key_field: :id,
  name: "product_search_idx"
```

Generated SQL:

```sql
CREATE INDEX product_search_idx ON products
  USING bm25 (
    id,
    (description::pdb.simple('lowercase=true', 'stemmer=English')),
    (category::pdb.simple('lowercase=true'))
  )
  WITH (key_field='id');
```

### JSON Fields

ParadeDB supports two patterns for indexing JSON:

**Option 1: Index entire JSON (all subfields auto-indexed with same tokenizer)**

```ruby
add_bm25_index :products,
  fields: {
    id: {},
    metadata: {},  # All JSON subfields indexed with default tokenizer
  },
  key_field: :id,
  name: "product_search_idx"

# Or with a specific tokenizer for all subfields:
add_bm25_index :products,
  fields: {
    id: {},
    metadata: { tokenizer: "simple" },
  },
  key_field: :id,
  name: "product_search_idx"
```

Generated SQL:

```sql
-- Default tokenizer
CREATE INDEX product_search_idx ON products
  USING bm25 (id, metadata)
  WITH (key_field='id');

-- With specific tokenizer
CREATE INDEX product_search_idx ON products
  USING bm25 (id, (metadata::pdb.simple))
  WITH (key_field='id');
```

**Option 2: Index specific JSON subfields (different tokenizers per subfield)**

Use the `expressions` key to index individual JSON paths with their own tokenizers. These expressions are the searchable field names.

```ruby
add_bm25_index :products,
  fields: {
    id: {},
    description: { tokenizer: "simple" },
  },
  expressions: {
    "metadata->>'title'" => { tokenizer: "simple" },
    "metadata->>'brand'" => { tokenizer: "ngram", min: 2, max: 3 },
  },
  key_field: :id,
  name: "product_search_idx"
```

Generated SQL:

```sql
CREATE INDEX product_search_idx ON products
  USING bm25 (
    id,
    (description::pdb.simple),
    ((metadata->>'title')::pdb.simple),
    ((metadata->>'brand')::pdb.ngram(2,3))
  )
  WITH (key_field='id');
```

Querying JSON expressions:

```ruby
# Search using the same expression that was indexed
Product.search("metadata->>'title'").matching("wireless")
```

## Query Builder API

The `.search()` method is scope-like and works on both the model and relations, returning an `ActiveRecord::Relation` with ParadeDB search methods (like standard Rails scopes). Chaining methods adds conditions with AND semantics.

### Single-Field Search

```ruby
# Returns a relation - no query executed yet
Product.search(:description)

# Executes when enumerated
Product.search(:description).matching("shoes").to_a
```

### Multi-Field Search (Chaining)

Chain `.search()` calls to add AND conditions across fields:

```ruby
Product.search(:description).matching("running shoes")
  .search(:category).matching("Footwear")
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description &&& 'running shoes'
  AND category &&& 'Footwear';
```

## Basic Search Methods

> **Note: Tokenization Semantics**
> 
> ParadeDB handles strings and arrays differently:
> - **String** (`'running shoes'`): Gets tokenized into individual terms (`running`, `shoes`)
> - **Array** (`ARRAY['running', 'shoes']`): Each element is a pre-tokenized term (no further tokenization)
> 
> This means `ARRAY['running shoes']` (single element) looks for the literal term "running shoes" and won't match "Sleek running shoes". The Rails API handles this correctly: `.matching("running", "shoes")` generates an array of separate terms, while `.matching("running shoes")` passes a string that gets tokenized.

### Conjunction (AND) with `.matching()`

Search for products containing all specified terms. Chaining `.matching()` adds more AND conditions.

```ruby
# Single term
Product.search(:description).matching("shoes")
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes">,
#     #<Product id: 9, description: "Casual shoes for everyday wear">
#   ]>

# Multiple terms (AND)
Product.search(:description).matching("running", "shoes")
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes">
#   ]>

# Chaining adds more AND conditions
Product.search(:description).matching("running").matching("shoes")
# Same as: .matching("running", "shoes")
```

Generated SQL:

```sql
-- Single term
SELECT * FROM products
WHERE description &&& 'shoes';

-- Multiple terms
SELECT * FROM products
WHERE description &&& ARRAY['running', 'shoes'];
```

### Disjunction (OR) with `any:` keyword

Search for products containing any of the specified terms:

```ruby
Product.search(:description).matching(any: ["wireless", "bluetooth"])
#=> #<ActiveRecord::Relation [
#     #<Product id: 3, description: "Compact wireless bluetooth speaker">,
#     #<Product id: 5, description: "Wireless noise-cancelling headphones">,
#     #<Product id: 8, description: "Bluetooth gaming mouse with RGB lighting">,
#     #<Product id: 14, description: "Wireless charging pad for smartphones">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description ||| ARRAY['wireless', 'bluetooth'];
```

### Exclusion with `.excluding()`

Exclude products containing specified terms:

```ruby
Product.search(:description).matching("shoes").excluding("cheap")
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes">
#   ]>

# Multiple exclusions
Product.search(:description).matching("shoes").excluding("cheap", "budget")
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description &&& 'shoes'
  AND NOT (description &&& 'cheap');
```

## Special Query Types

### Phrase Search with `.phrase()`

Search for exact phrases where word order and position matter:

```ruby
Product.search(:description).phrase("running shoes")
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description ### 'running shoes';
```

Phrase with slop (allows terms to be within a certain distance):

```ruby
Product.search(:description).phrase("running shoes", slop: 2)
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes">,
#     #<Product id: 10, description: "Running athletic shoes with cushioning">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description ### 'running shoes'::pdb.slop(2);
```

### Fuzzy Matching with `.fuzzy()`

Search for terms with typos or variations:

```ruby
Product.search(:description).fuzzy("sheos", distance: 1)
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes">,
#     #<Product id: 9, description: "Casual shoes for everyday wear">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description === 'sheos'::pdb.fuzzy(1);
```

Fuzzy with prefix matching:

```ruby
Product.search(:description).fuzzy("runn", distance: 1, prefix: true)
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description === 'runn'::pdb.fuzzy(1, t);
```

### Regex Search with `.regex()`

> **Security:** Validate user-provided patterns to prevent ReDoS attacks.

Search with regular expressions:

```ruby
Product.search(:description).regex("run.*shoes")
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes">
#   ]>
```

Generated SQL:

```sql
-- Note: pdb.regex() matches single tokens. For multi-token patterns, use pdb.regex_phrase()
SELECT * FROM products
WHERE description @@@ pdb.regex_phrase(ARRAY['run.*', 'shoes']);
```

### Term Search with `.term()`

Exact term matching (no tokenization):

```ruby
Product.search(:description).term("shoes")
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description @@@ pdb.term('shoes');
```

## Proximity Queries with `.near()`

Search for terms within a specified distance of each other:

```ruby
Product.search(:description).near("sleek", "shoes", distance: 1)
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description @@@ ('sleek' ## 1 ## 'shoes');
```

## More Like This with `.similar_to()`

Find documents similar to a given record:

```ruby
# Find products similar to product with id 3
Product.similar_to(3)
#=> #<ActiveRecord::Relation [
#     #<Product id: 3, description: "Sleek running shoes">,
#     #<Product id: 4, description: "White jogging shoes">,
#     #<Product id: 5, description: "Generic shoes">
#   ]>

# Limit similarity matching to specific fields
Product.similar_to(3, fields: [:description])

# Can also pass a record
product = Product.find(3)
Product.similar_to(product)
```

Generated SQL:

```sql
-- All indexed fields
SELECT * FROM products
WHERE id @@@ pdb.more_like_this(3);

-- Specific fields
SELECT * FROM products
WHERE id @@@ pdb.more_like_this(3, ARRAY['description']);
```

## Phrase Prefix with `.phrase_prefix()`

Search for phrases where the last term is a prefix (useful for autocomplete):

```ruby
Product.search(:description).phrase_prefix("running", "sh")
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description @@@ pdb.phrase_prefix(ARRAY['running', 'sh']);
```

## Boosting with `boost:` Option

Increase or decrease the relevance weight of a query:

```ruby
Product.search(:description).matching("shoes", boost: 2)
  .select("products.*", "pdb.score(id) AS search_score")
  .order("search_score DESC")
#=> #<ActiveRecord::Relation [
#     #<Product id: 5, description: "Generic shoes", search_score: 5.84>,
#     #<Product id: 3, description: "Sleek running shoes", search_score: 5.04>
#   ]>
```

Generated SQL:

```sql
SELECT products.*, pdb.score(id) AS search_score
FROM products
WHERE description ||| 'shoes'::pdb.boost(2)
ORDER BY search_score DESC;
```

Boosting can be combined with fuzzy matching:

```ruby
Product.search(:description).fuzzy("shose", distance: 2, boost: 2)
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description === 'shose'::pdb.fuzzy(2)::pdb.boost(2);
```

## Combining Search Methods

Chain multiple methods on the same field (AND semantics):

```ruby
# Phrase with exclusion
Product.search(:description)
  .phrase("running shoes")
  .excluding("cheap")

# Matching with exclusion
Product.search(:description)
  .matching("running", "shoes")
  .excluding("cheap", "budget")
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description ### 'running shoes'
  AND NOT (description &&& 'cheap');
```

## Cross-Field OR Logic

Use ActiveRecord's `.or()` for OR conditions across different fields or scopes:

```ruby
# "shoes in description" OR "footwear in category"
Product.search(:description).matching("shoes")
  .or(Product.search(:category).matching("footwear"))
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 3, description: "Leather boots", category: "Footwear">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description &&& 'shoes'
   OR category &&& 'footwear';
```

## Complex Boolean Logic

### Combining Search with Filters

```ruby
Product.search(:description).phrase("running shoes")
  .where(rating: 4..)
  .or(
    Product.search(:category).matching("Electronics")
      .search(:description).matching("wireless")
  )
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes", rating: 5>,
#     #<Product id: 3, description: "Compact wireless bluetooth speaker", category: "Electronics">,
#     #<Product id: 5, description: "Wireless noise-cancelling headphones", category: "Electronics">
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE (
  (description ### 'running shoes' AND rating >= 4)
  OR (category &&& 'Electronics' AND description &&& 'wireless')
);
```

### Nested Conditions

Find athletic running shoes that aren't cheap, OR electronics under $100:

```ruby
Product.search(:description)
  .matching("running", "athletic")
  .excluding("cheap")
  .or(
    Product.search(:category).phrase("Electronics")
      .where(price: ...100)
  )
#=> #<ActiveRecord::Relation [
#     #<Product id: 2, description: "Premium athletic running shoes">,
#     #<Product id: 3, description: "Compact wireless bluetooth speaker", price: 49.99>,
#     #<Product id: 8, description: "Bluetooth gaming mouse with RGB lighting", price: 79.99>
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE (
  (description &&& ARRAY['running', 'athletic'] AND NOT (description &&& 'cheap'))
  OR (category ### 'Electronics' AND price < 100)
);
```

### Multiple Conditions with Different Priorities

```ruby
# (running shoes AND in stock) OR (electronics AND wireless AND price < 200)
Product.search(:description).matching("running", "shoes")
  .where(in_stock: true)
  .or(
    Product.search(:category).matching("Electronics")
      .search(:description).matching("wireless")
      .where(price: ...200)
  )
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes", in_stock: true>,
#     #<Product id: 3, description: "Compact wireless bluetooth speaker", category: "Electronics", price: 49.99>,
#     #<Product id: 14, description: "Wireless charging pad for smartphones", category: "Electronics", price: 29.99>
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE (
    (description &&& ARRAY['running', 'shoes'] AND in_stock = true)
    OR (category &&& 'Electronics' AND description &&& 'wireless' AND price < 200)
);
```

## Scoring and Ordering

### Convenience Helper: `.with_score`

The `.with_score` helper automatically adds the BM25 relevance score to results:

```ruby
Product.search(:description).matching("running", "shoes")
  .with_score
  .order(search_score: :desc)
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes", search_score: 4.5>,
#     #<Product id: 7, description: "Comfortable running shoes for athletes", search_score: 4.2>
#   ]>

# Access the score
product = results.first
product.search_score  #=> 4.5
```

Generated SQL:

```sql
SELECT products.*, pdb.score(id) AS search_score
FROM products
WHERE description &&& ARRAY['running', 'shoes']
ORDER BY search_score DESC;
```

### Using Raw `.select()` (Alternative)

For more control, use standard `.select()`:

```ruby
Product.search(:description).matching("running", "shoes")
  .select("products.*", "pdb.score(id) AS search_score")
  .order("search_score DESC")
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes", search_score: 4.5>,
#     #<Product id: 7, description: "Comfortable running shoes for athletes", search_score: 4.2>,
#     #<Product id: 12, description: "Running shoes with advanced cushioning", search_score: 3.8>
#   ]>
```

Generated SQL:

```sql
SELECT products.*, pdb.score(id) AS search_score
FROM products
WHERE description &&& ARRAY['running', 'shoes']
ORDER BY search_score DESC;
```

## Snippets and Highlighting

### Convenience Helper: `.with_snippet`

The `.with_snippet` helper automatically adds highlighted snippets to results:

```ruby
Product.search(:description).matching("running", "shoes")
  .with_snippet(:description)
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes",
#               description_snippet: "Sleek <b>running</b> <b>shoes</b>">,
#     #<Product id: 7, description: "Comfortable running shoes for athletes",
#               description_snippet: "Comfortable <b>running</b> <b>shoes</b> for athletes">
#   ]>

# Access the snippet
product.description_snippet  #=> "Sleek <b>running</b> <b>shoes</b>"
```

With custom formatting options:

```ruby
Product.search(:description).matching("running", "shoes")
  .with_snippet(:description, start_tag: '<mark>', end_tag: '</mark>', max_chars: 100)
```

Generated SQL:

```sql
SELECT products.*, pdb.snippet(description, '<mark>', '</mark>', 100) AS description_snippet
FROM products
WHERE description &&& ARRAY['running', 'shoes'];
```

### Chaining Helpers

Combine `.with_score` and `.with_snippet` for rich search results:

```ruby
Product.search(:description).matching("running", "shoes")
  .with_score
  .with_snippet(:description)
  .order(search_score: :desc)
#=> Results include both search_score and description_snippet attributes
```

### Using Raw `.select()` (Alternative)

For more control, use standard `.select()`:

```ruby
Product.search(:description).matching(any: ["wireless", "bluetooth"])
  .select(
    "products.id",
    "products.description",
    "pdb.snippet(description) AS snippet"
  )
#=> #<ActiveRecord::Relation [
#     #<Product id: 3, description: "Compact wireless bluetooth speaker",
#               snippet: "Compact <b>wireless</b> <b>bluetooth</b> speaker">,
#     #<Product id: 5, description: "Wireless noise-cancelling headphones",
#               snippet: "<b>Wireless</b> noise-cancelling headphones">,
#     #<Product id: 8, description: "Bluetooth gaming mouse with RGB lighting",
#               snippet: "<b>Bluetooth</b> gaming mouse with RGB lighting">
#   ]>
```

Generated SQL:

```sql
SELECT id, description, pdb.snippet(description) AS snippet
FROM products
WHERE description ||| ARRAY['wireless', 'bluetooth'];
```

### Custom Snippet Formatting

```ruby
Product.search(:description).matching("running", "shoes")
  .select(
    "products.description",
    "pdb.snippet(description, '<mark>', '</mark>', 100) AS snippet"
  )
#=> #<ActiveRecord::Relation [
#     #<Product description: "Sleek running shoes with advanced cushioning",
#               snippet: "Sleek <mark>running</mark> <mark>shoes</mark> with advanced...">,
#     #<Product description: "Comfortable running shoes for athletes",
#               snippet: "Comfortable <mark>running</mark> <mark>shoes</mark> for athletes">
#   ]>
```

Generated SQL:

```sql
SELECT description, pdb.snippet(description, '<mark>', '</mark>', 100)
FROM products
WHERE description &&& ARRAY['running', 'shoes'];
```

## Combining with ActiveRecord Filters

Mix ParadeDB search with standard ActiveRecord query methods:

```ruby
# Search with price and stock filters
Product.search(:description).matching("shoes")
  .where(
    price: ...100,
    in_stock: true,
    rating: 4..
  )
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes", price: 89.99, in_stock: true, rating: 5>,
#     #<Product id: 7, description: "Comfortable running shoes for athletes", price: 79.99, in_stock: true, rating: 4>
#   ]>
```

Generated SQL:

```sql
SELECT * FROM products
WHERE description &&& 'shoes'
  AND price < 100
  AND in_stock = true
  AND rating >= 4;
```

### Conditional Search Based on User Input

```ruby
query = Product.all
query = query.search(:description).matching(*search_terms) if search_terms&.any?
query = query.search(:category).phrase(category) if category
query = query.where(rating: min_rating..) if min_rating
results = query.to_a
#=> #<ActiveRecord::Relation [
#     #<Product id: 1, description: "Sleek running shoes">,
#     #<Product id: 3, description: "Compact wireless bluetooth speaker">,
#     #<Product id: 11, description: "Premium wireless bluetooth headphones">
#   ]>
```

Generated SQL (example with all conditions):

```sql
SELECT * FROM products
WHERE (
    description &&& ARRAY['running', 'shoes']
    AND category ### 'Footwear'
    AND rating >= 4
);
```

## Combine CTE with ParadeDB

You can combine ParadeDB searches with advanced database features like Common Table Expressions (CTEs):

```ruby
footwear_categories_cte = Category.search(:name).matching(any: ["shoes", "sandals", "boots"])
  .select(:id)

# The .with() method makes the CTE available to be referenced
in_stock_footwear = Product.with(
  footwear_categories_cte: footwear_categories_cte
).where(
  in_stock: true,
  category_id: Category.from("footwear_categories_cte").select(:id)
)
```

Generated SQL:

```sql
-- The ActiveRecord ORM translates this into a WITH clause
WITH footwear_categories_cte AS (
   SELECT id FROM categories
   WHERE name ||| ARRAY['shoes', 'sandals', 'boots']
)
-- The main query can then reference the CTE
SELECT * FROM products
WHERE in_stock = true
  AND category_id IN (SELECT id FROM footwear_categories_cte);
```

## Faceted Search (Aggregations)

Two methods are provided for faceted search:

- **`.facets()`** - Terminal method, returns Hash only (no rows)
- **`.with_facets()`** - Chainable, returns decorated Relation with rows + `.facets` accessor

### Facets Only with `.facets()`

The `.facets()` method executes immediately and returns a hash of aggregation results (no rows):

```ruby
# Get facet counts for "category" and "brand"
facets = Product.search(:description).matching("shoes")
  .facets(:category, :brand)

# The result is a hash containing the facet counts
puts facets
# => {
#   "category" => {
#     "buckets" => [
#       { "key" => "Running", "doc_count" => 50 },
#       { "key" => "Casual", "doc_count" => 35 },
#       { "key" => "Hiking", "doc_count" => 20 }
#     ]
#   },
#   "brand" => {
#     "buckets" => [
#       { "key" => "Nike", "doc_count" => 45 },
#       { "key" => "Adidas", "doc_count" => 30 },
#       { "key" => "New Balance", "doc_count" => 30 }
#     ]
#   }
# }
```

With options:

```ruby
facets = Product.search(:description).matching("shoes")
  .facets(
    :category,
    :brand,
    size: 10,
    order: "-count",
    missing: "(missing)"
  )
```

Generated SQL:

```sql
-- Aggregate-only query (one pdb.agg per field)
SELECT
  pdb.agg('{"terms": {"field": "category", "size": 10, "order": {"_count": "desc"}}}') AS category_facet,
  pdb.agg('{"terms": {"field": "brand", "size": 10, "order": {"_count": "desc"}}}') AS brand_facet
FROM products
WHERE description &&& ARRAY['shoes'];
```

#### `.facets()` Signature

```ruby
def facets(
  *fields,
  size: 10,
  order: "-count",
  missing: nil,
  agg: nil
)
  # Returns Hash (terminal method, executes immediately)
end
```

**Parameters:**

- `fields`: List of model field names to facet on (text, keyword, or numeric)
- `size`: Max buckets per field; `nil` emits no size clause
- `order`: `"-count"` or `"count"` or `"key"`/`"-key"` to align with Rails ordering style
- `missing`: Value for missing bucket (optional)
- `agg`: Advanced escape hatch to pass raw Elasticsearch-style JSON for power users; when provided, `fields`/`size`/`order`/`missing` are ignored

### Rows + Facets with `.with_facets()`

The `.with_facets()` method returns a decorated Relation that includes both rows and facet data. **For clarity, place `.with_facets()` last in the chain.**

```ruby
results = Product.search(:description).matching("shoes")
  .where(in_stock: true)
  .order(rating: :desc)
  .limit(10)
  .with_facets(:category, :brand)

# Iterate rows (respects order/limit)
results.each { |product| puts product.description }

# Access facet data (computed on FULL filtered set, ignores limit)
results.facets[:category]
# => {
#   "buckets" => [
#     { "key" => "Running", "doc_count" => 50 },
#     { "key" => "Casual", "doc_count" => 35 }
#   ]
# }
```

**Key behavior:**
- Facets are computed on the **full filtered set** (ignores LIMIT/OFFSET)
- ORDER/LIMIT only affect which **rows** you get back
- This matches Elasticsearch aggregation behavior

#### `.with_facets()` Signature

```ruby
def with_facets(
  *fields,
  size: 10,
  order: "-count",
  missing: nil,
  agg: nil
)
  # Returns decorated Relation (chainable, with .facets accessor)
end
```

Generated SQL:

```sql
-- Window aggregates return rows + facet data (one pdb.agg per field)
SELECT
  *,
  pdb.agg('{"terms": {"field": "category", "size": 10}}') OVER () AS _category_facet,
  pdb.agg('{"terms": {"field": "brand", "size": 10}}') OVER () AS _brand_facet
FROM products
WHERE description &&& ARRAY['shoes'] AND in_stock = true
ORDER BY rating DESC
LIMIT 10;
```

#### ORM Integration Points

- Implement `facets()` on a custom `ParadeDB::Relation` module that extends `ActiveRecord::Relation`
- Use `Relation#where_clause` to extract existing WHERE clauses (including `.search(...)`) and attach `pdb.agg(...)`
- If no ParadeDB operator is present in the query, inject `@@@ pdb.all()` on the indexed key field to force aggregate pushdown
- For windowed facets, use a custom Arel node:

```ruby
module ParadeDB
  class Agg < Arel::Nodes::SqlLiteral
    def initialize(json_spec)
      super("pdb.agg('#{json_spec}') OVER ()")
    end
  end
end
```

This allows `.select(ParadeDB::Agg.new(json_spec))` when needed.

#### Rails-like Behavior

- `.facets(...)` executes immediately and returns a Hash (similar to `.count` or `.sum`)
- `.with_facets(...)` returns a decorated Relation with `.facets` accessor for aggregation data
- Facets are computed against the full filtered set (window semantics). `LIMIT/OFFSET` affect rows, not facet buckets

#### ParadeDB Operator Detection ("Sentinel")

ParadeDB aggregate pushdown requires a ParadeDB operator in the WHERE clause. The relation should be inspected before executing facets:

- If the WHERE tree contains a ParadeDB predicate (i.e., from `.search()`), proceed as-is
- Otherwise, append a no-op ParadeDB predicate using the BM25 key field: `key_field @@@ pdb.all()`

This "all" query is a sentinel that forces ParadeDB to execute the aggregate without changing results.

## Using Window Functions

You can combine ParadeDB search with standard SQL window functions:

```ruby
ranked_shoes = Product.search(:description).matching("shoes")
  .select(
    "products.*",
    "ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS rank_in_category"
  )
#=> #<ActiveRecord::Relation [
#     #<Product id: 2, description: "Premium running shoes", category: "Running", price: 199.99, rank_in_category: 1>,
#     #<Product id: 1, description: "Sleek running shoes", category: "Running", price: 89.99, rank_in_category: 2>,
#     #<Product id: 9, description: "Casual shoes for everyday wear", category: "Casual", price: 59.99, rank_in_category: 1>
#   ]>
```

Generated SQL:

```sql
SELECT *,
  ROW_NUMBER() OVER (PARTITION BY category ORDER BY price DESC) AS rank_in_category
FROM products
WHERE description &&& 'shoes';
```

## API Summary

| Method | SQL Operator | Description |
|--------|--------------|-------------|
| `.matching("a", "b")` | `&&& ARRAY['a', 'b']` | Match all terms (AND) |
| `.matching(any: ["a", "b"])` | `\|\|\| ARRAY['a', 'b']` | Match any term (OR) |
| `.matching("a", boost: 2)` | `\|\|\| 'a'::pdb.boost(2)` | Match with relevance boost |
| `.excluding("a")` | `NOT (&&& 'a')` | Exclude terms |
| `.phrase("a b")` | `### 'a b'` | Phrase match (order enforced) |
| `.phrase("a b", slop: 2)` | `### 'a b'::pdb.slop(2)` | Phrase with distance |
| `.fuzzy("a", distance: 1)` | `=== 'a'::pdb.fuzzy(1)` | Fuzzy match |
| `.near("a", "b", distance: 1)` | `@@@ ('a' ## 1 ## 'b')` | Proximity search |
| `.similar_to(id)` | `@@@ pdb.more_like_this(id)` | More Like This |
| `.phrase_prefix("a", "b")` | `@@@ pdb.phrase_prefix(ARRAY[...])` | Autocomplete |
| `.regex("a.*b")` | `@@@ pdb.regex('a.*b')` | Regex match |
| `.term("a")` | `@@@ pdb.term('a')` | Exact term match |

## Pending and Other Concerns

### Pagination

Standard ActiveRecord pagination (via `.limit()` and `.offset()`, or gems like Kaminari/Pagy) works naturally with ParadeDB queries since they return `ActiveRecord::Relation`.

### Open Questions

- **Mixed special queries on same field**: Should chaining different query types on the same field be supported? For example:
  ```ruby
  Product.search(:description).phrase("running shoes").fuzzy("sneakerz", distance: 1)
  ```
  This would generate: `WHERE description ### 'running shoes' AND description ||| 'sneakerz'::pdb.fuzzy(1)`
  
  ParadeDB SQL supports this, but should the Rails API allow it or require separate `.search()` calls?

### Other Concerns

- Add BM25Index to existing tables with data?
- Handle index recreation after schema changes?
- Deal with Rails' migration system and schema.rb dumping?
- Errors and notices from PostgreSQL communicated to Rails
- Validation errors that can be generated by plugin/ORM layer
