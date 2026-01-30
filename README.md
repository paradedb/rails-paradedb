# ParadeDB for Rails (ActiveRecord)

Rails-native integration for ParadeDB focused on ActiveRecord.

## Status

Work in progress. See `design-doc.md` for the current API proposal and scope.

## Goals

- Provide an idiomatic ActiveRecord API for ParadeDB search
- Keep index definitions in migrations
- Introspect index metadata from PostgreSQL at runtime

## Non-Goals

- Maintain a separate DSL for index configuration
- Replace ActiveRecord query semantics
