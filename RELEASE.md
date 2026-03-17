# Release Management and Compatibility

This document describes how `rails-paradedb` releases are cut and what
compatibility guarantees the project provides.

## Goals

- Keep the ActiveRecord integration stable and predictable.
- Add ParadeDB features quickly without forcing unnecessary upgrades.
- Keep support expectations clear for users and maintainers.

## Current Status (ParadeDB Pre-1.0)

ParadeDB is still pre-1.0, so minor releases may include breaking changes.
During this phase:

- Feature availability is documented by ParadeDB version.
- New functionality should use capability checks when practical.
- Errors for unsupported capabilities should be explicit.

## Versioning Policy

`rails-paradedb` follows SemVer:

- MAJOR: Breaking API or behavior changes
- MINOR: Backward-compatible features
- PATCH: Backward-compatible fixes and docs updates

Version source of truth:

- `lib/parade_db/version.rb` (`ParadeDB::VERSION`)

The release workflow validates that the requested version matches this value.

## Compatibility Principles

1. Major-version alignment after ParadeDB 1.0: we plan to align majors where
   practical (for example, ParadeDB 1.x with `rails-paradedb` 1.x).
2. Minor forward compatibility: a given library minor should support the same
   ParadeDB major and later ParadeDB minors.
3. Capability gating: if a feature depends on a ParadeDB version, expose a
   stable API and return a clear error when unsupported.

## Support Matrix

The canonical support matrix lives in `README.md` under
**Requirements & Compatibility** and should be kept up to date.

Today, the maintained minimum ParadeDB version is `0.21.10`. Update the README
matrix, CI image tags, schema-compat expectations, and any version-gated
examples in the same PR whenever that floor changes.

## Compatibility Targets

- Ruby: 3.2+
- ActiveRecord: 7.2+
- PostgreSQL: 15+ with the PostgreSQL adapter
- ParadeDB: 0.21.10+

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
4. Publish the gem to RubyGems.
5. Create the GitHub release, which tags the target commit and attaches the built gem.

RubyGems publishing secret (GitHub Actions):

- `RUBYGEMS_TOKEN`

## Testing and CI Expectations

CI should cover the published support matrix.

The source of truth is the matrix in `.github/workflows/ci.yml`. When
compatibility changes, update that matrix first and keep `README.md` in sync in
the same PR.

## Feature Gating

If a feature depends on a specific ParadeDB server capability, document the
minimum ParadeDB version in:

- `README.md` (user-facing)
- `CHANGELOG.md` (release-facing)

## Deprecation Policy

- Deprecations must include the version where they were introduced.
- Remove deprecated behavior no earlier than the next MINOR release, or after
  two MINOR releases, whichever is later.

## Decisions for ParadeDB 1.0

Revisit these points once ParadeDB reaches 1.0:

- Final major-version alignment policy.
- Long-term support window for older ParadeDB majors.
- Whether to duplicate the support matrix in `README.md`.
