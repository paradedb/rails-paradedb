# Contributing to rails-paradedb

Thanks for your interest in contributing to `rails-paradedb`.

## Technical Info

Before opening a PR, please read this guide for workflow and quality expectations.
If anything is unclear, ask in the ParadeDB Slack community.

### Selecting Issues

External contributions should be linked to a GitHub issue.
If no issue exists for your bug/feature, please open one first.

Good starter issues are usually labeled `good first issue`.

### Claiming Issues

This repository supports self-assignment:

1. Confirm the issue is unassigned and not already being worked.
2. Comment `/take` to assign it to yourself.

If you can no longer work on it, remove yourself from assignees.

### Development Setup

```bash
git clone https://github.com/paradedb/rails-paradedb.git
cd rails-paradedb

bundle install
pre-commit install
```

### Running Tests

Unit tests:

```bash
bash scripts/run_unit_tests.sh
```

Integration tests (starts ParadeDB via Docker):

```bash
bash scripts/run_integration_tests.sh
```

You can also run one spec file:

```bash
bash scripts/run_unit_tests.sh spec/user_api_unit_spec.rb
```

### Linting and Formatting

This repo currently enforces markdown/style checks via `pre-commit`.
If you change Ruby code, keep style consistent with existing files and tests.

### Pull Request Workflow

1. Ensure your change has an issue.
2. Branch from `main`.
3. Add or update tests for behavior changes.
4. Update docs/examples when public API changes.
5. Open a PR to `main`.
6. Ensure CI passes.

The repository enforces PR title linting and follows Conventional Commits.

### Documentation

If you add a user-facing feature, include docs updates in the same PR:

- `README.md` for public API behavior
- `examples/` for practical usage
- inline comments/docstrings when needed for maintainability

## Legal

### Contributor License Agreement

ParadeDB uses CLA Assistant. You must sign the CLA before your contribution can
be merged. This is a one-time step per repository.

### License

By contributing, you agree your contributions are licensed under MIT.
