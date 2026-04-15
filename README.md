<!-- ParadeDB: Postgres for Search and Analytics -->
<h1 align="center">
  <a href="https://paradedb.com"><img src="https://github.com/paradedb/paradedb/raw/main/docs/logo/readme.svg" alt="ParadeDB"></a>
<br>
</h1>

<p align="center">
  <b>Simple, Elastic-quality search for Postgres</b><br/>
</p>

<h3 align="center">
  <a href="https://paradedb.com">Website</a> &bull;
  <a href="https://docs.paradedb.com">Docs</a> &bull;
  <a href="https://paradedb.com/slack/">Community</a> &bull;
  <a href="https://paradedb.com/blog/">Blog</a> &bull;
  <a href="https://docs.paradedb.com/changelog/">Changelog</a>
</h3>

---

# rails-paradedb

[![Gem Version](https://img.shields.io/gem/v/rails-paradedb)](https://rubygems.org/gems/rails-paradedb)
[![Ruby Requirement](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Frubygems.org%2Fapi%2Fv1%2Fversions%2Frails-paradedb.json&query=%24%5B0%5D.ruby_version&label=ruby&logo=ruby)](https://rubygems.org/gems/rails-paradedb)
[![Gem Downloads](https://img.shields.io/gem/dt/rails-paradedb)](https://rubygems.org/gems/rails-paradedb)
[![Codecov](https://codecov.io/gh/paradedb/rails-paradedb/graph/badge.svg)](https://codecov.io/gh/paradedb/rails-paradedb)
[![License](https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue)](https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme)
[![Slack URL](https://img.shields.io/badge/Join%20Slack-purple?logo=slack&link=https%3A%2F%2Fparadedb.com%2Fslack)](https://paradedb.com/slack)
[![X URL](https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Fparadedb&label=Follow%20%40paradedb)](https://x.com/paradedb)

The official ActiveRecord integration for [ParadeDB](https://paradedb.com) including first class support for for managing BM25 indexes and running queries using the full ParadeDB API.

## Usage

Follow the [getting started guide](https://docs.paradedb.com/documentation/getting-started/environment#rails) to begin.

## Requirements & Compatibility

| Component  | Supported                                        |
| ---------- | ------------------------------------------------ |
| Ruby       | 3.2+                                             |
| Rails      | 7.2+                                             |
| ParadeDB   | 0.22.0+                                          |
| PostgreSQL | 15+ (PostgreSQL adapter with ParadeDB extension) |

## Examples

- [Quick Start](examples/quickstart/quickstart.rb)
- [Faceted Search](examples/faceted_search/faceted_search.rb)
- [Autocomplete](examples/autocomplete/autocomplete.rb)
- [More Like This](examples/more_like_this/more_like_this.rb)
- [Hybrid RRF](examples/hybrid_rrf/hybrid_rrf.rb)
- [RAG](examples/rag/rag.rb)
- [Examples README](examples/README.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, test commands, linting, and PR workflow.

## Support

If you're missing a feature or found a bug, open a
[GitHub Issue](https://github.com/paradedb/rails-paradedb/issues/new/choose).

For community support:

- Join the [ParadeDB Slack Community](https://paradedb.com/slack)
- Ask in [ParadeDB Discussions](https://github.com/paradedb/paradedb/discussions)

For commercial support, contact [sales@paradedb.com](mailto:sales@paradedb.com).

## Acknowledgments

We would like to thank the following members of the community for their valuable feedback and reviews during the development of this package:

- [Eric Barendt](https://github.com/ebarendt) - Engineering at Modern Treasury
- [Matthew Higgins](https://github.com/matthuhiggins) - Engineering at Modern Treasury
- [Patrick Schmitz](https://github.com/bullfight) - Engineering at Modern Treasury

## License

rails-paradedb is licensed under the [MIT License](LICENSE).
