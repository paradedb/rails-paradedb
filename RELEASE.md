# Release Management and Compatibility

This document defines release policies for `rails-paradedb`, including version
source, compatibility expectations, and release workflow.

## Version Source of Truth

The canonical gem version is:

- `lib/parade_db/version.rb` (`ParadeDB::VERSION`)

The gemspec (`rails-paradedb.gemspec`) reads this constant.

Release automation validates that the requested release version matches
`ParadeDB::VERSION`.

## Versioning Policy

`rails-paradedb` follows SemVer:

- MAJOR: Breaking public API/behavior changes.
- MINOR: Backward-compatible features.
- PATCH: Backward-compatible fixes/documentation updates.

## Compatibility Targets

Current policy target:

- Ruby: 3.2+
- Rails / ActiveRecord: 8.x
- PostgreSQL: ParadeDB-supported versions
- ParadeDB: latest tested minor and previous minor where feasible

## Release Checklist

Before triggering a release workflow:

1. Bump `ParadeDB::VERSION` in `lib/parade_db/version.rb`.
2. Add a changelog entry in `CHANGELOG.md`.
3. Ensure CI is green on `main`.
4. Confirm README/docs/examples are consistent with release behavior.

## Automated Release Workflow

The `Release` workflow (manual dispatch):

1. Validates confirmation and version format.
2. Verifies requested version equals `ParadeDB::VERSION`.
3. Verifies `v<version>` tag/release do not already exist.
4. Builds the gem.
5. Creates and pushes the tag `v<version>`.
6. Creates a GitHub release.
7. Publishes gem to RubyGems.

Required secret:

- `RUBYGEMS_API_KEY`

## Feature Availability Notes

When introducing behavior gated by ParadeDB server capabilities, document the
minimum ParadeDB version in:

- `README.md` (user-facing)
- `CHANGELOG.md` (release-facing)

## Deprecation Policy

- Deprecations must be documented with an introduction version.
- Remove deprecated behavior no earlier than the next MINOR release, or after
  two MINOR releases, whichever is later.
