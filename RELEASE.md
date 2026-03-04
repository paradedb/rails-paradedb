# Release Management

This document describes how to cut a `rails-paradedb` release and what
compatibility guarantees we target.

## Versioning

`rails-paradedb` follows SemVer:

- MAJOR: Breaking API or behavior changes
- MINOR: Backward-compatible features
- PATCH: Backward-compatible fixes and docs updates

Version source of truth:

- `lib/parade_db/version.rb` (`ParadeDB::VERSION`)

The release workflow validates that the requested version matches this value.

## Compatibility Targets

- Ruby: 3.2+
- ActiveRecord: 7.2+
- PostgreSQL: ParadeDB-supported versions
- ParadeDB: latest tested minor (and previous minor when feasible)

## Pre-Release Checklist

Before running the release workflow:

1. Update `ParadeDB::VERSION` in `lib/parade_db/version.rb`.
2. Add release notes to `CHANGELOG.md`.
3. Make sure CI on `main` is green.
4. Confirm `README.md` and examples reflect shipped behavior.

## Release Workflow

Use GitHub Actions workflow `Release` (`.github/workflows/release.yml`) with:

- `version`: release version (must equal `ParadeDB::VERSION`)
- `beta`: mark as prerelease if needed
- `confirmation`: set to true

The workflow will:

1. Validate version format and release state.
2. Verify tag/release `v<version>` do not already exist.
3. Build `rails-paradedb-<version>.gem`.
4. Create and push tag `v<version>`.
5. Create a GitHub release.
6. Publish the gem to RubyGems.

RubyGems publishing secret (GitHub Actions):

- `RUBYGEMS_TOKEN`

## Feature Gating

If a feature depends on a specific ParadeDB server capability, document the
minimum ParadeDB version in:

- `README.md` (user-facing)
- `CHANGELOG.md` (release-facing)

## Deprecation Policy

- Deprecations must include the version where they were introduced.
- Remove deprecated behavior no earlier than the next MINOR release, or after
  two MINOR releases, whichever is later.
