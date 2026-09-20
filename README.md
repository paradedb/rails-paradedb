<h1 align="center">
  <a href="https://paradedb.com">
    <picture align=center>
      <source media="(prefers-color-scheme: dark)" srcset="https://github.com/paradedb/paradedb/raw/main/docs/logo/paradedb-logo-dark-large.svg">
      <source media="(prefers-color-scheme: light)" srcset="https://github.com/paradedb/paradedb/raw/main/docs/logo/paradedb-logo-light-large.svg">
      <img alt="The ParadeDB logo." src="https://github.com/paradedb/paradedb/raw/main/docs/logo/paradedb-logo-light-large.svg">
    </picture>
  </a>
  <br>
</h1>

<p align="center">
  <b>Just use Postgres.</b><br/>
  One Postgres for your application data, full-text search, vector retrieval, and aggregations.
</p>

<h3 align="center">
  <a href="https://paradedb.com">Website</a> &bull;
  <a href="https://www.paradedb.com/docs/start/introduction">Docs</a> &bull;
  <a href="https://paradedb.com/slack/">Community</a> &bull;
  <a href="https://paradedb.com/blog/">Blog</a> &bull;
  <a href="https://www.paradedb.com/docs/project/changelog">Changelog</a>
</h3>

<p align="center">
  <a href="https://rubygems.org/gems/rails-paradedb"><img src="https://img.shields.io/gem/v/rails-paradedb" alt="Gem Version"></a>&nbsp;
  <a href="https://rubygems.org/gems/rails-paradedb"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Frubygems.org%2Fapi%2Fv1%2Fversions%2Frails-paradedb.json&query=%24%5B0%5D.ruby_version&label=ruby&logo=ruby" alt="Ruby Requirement"></a>&nbsp;
  <a href="https://rubygems.org/gems/rails-paradedb"><img src="https://img.shields.io/gem/dt/rails-paradedb" alt="Gem Downloads"></a>&nbsp;
  <a href="https://codecov.io/gh/paradedb/rails-paradedb"><img src="https://codecov.io/gh/paradedb/rails-paradedb/graph/badge.svg" alt="Codecov"></a>&nbsp;
  <a href="https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme"><img src="https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue" alt="License"></a>&nbsp;
  <a href="https://paradedb.com/slack"><img src="https://img.shields.io/badge/Join%20Slack-purple?logo=slack" alt="Community"></a>&nbsp;
  <a href="https://x.com/paradedb"><img src="https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Fparadedb&label=Follow%20%40paradedb" alt="Follow @paradedb"></a>
</p>

---

## ParadeDB for Rails

The official [ActiveRecord](https://guides.rubyonrails.org/active_record_basics.html) integration for [ParadeDB](https://paradedb.com) (powered by the [`pg_search`](https://github.com/paradedb/paradedb) Postgres extension). Follow the [getting started guide](https://www.paradedb.com/docs/start/connect-your-app#rails) to begin.

## Requirements & Compatibility

| Component  | Supported                                                          |
| ---------- | ------------------------------------------------------------------ |
| Ruby       | 3.2+                                                               |
| Rails      | 7.2+                                                               |
| ParadeDB   | 0.25.0+                                                            |
| PostgreSQL | 15+ (with the ParadeDB pg_search extension)                        |
| pgvector   | Required for vector search (included in the ParadeDB Docker image) |

## Examples

Follow the [example setup guide](https://www.paradedb.com/docs/guides/setup), then choose a guide and select the Rails tab:

- [Quickstart](https://www.paradedb.com/docs/start/connect-your-app)
- [Vector Search](https://www.paradedb.com/docs/guides/vector-search)
- [Faceted Search](https://www.paradedb.com/docs/guides/faceted-search)
- [Hybrid Search (RRF)](https://www.paradedb.com/docs/guides/hybrid-search)
- [Retrieval-Augmented Generation (RAG)](https://www.paradedb.com/docs/guides/rag-and-agents)
- [Autocomplete](https://www.paradedb.com/docs/guides/search-as-you-type)
- [More Like This](https://www.paradedb.com/docs/guides/more-like-this)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, running tests, linting, and the PR workflow.

## Support

If you're missing a feature or have found a bug, please open a
[GitHub Issue](https://github.com/paradedb/rails-paradedb/issues/new/choose).

To get community support, you can:

- Post a question in the [ParadeDB Slack Community](https://paradedb.com/slack)
- Ask for help on our [GitHub Discussions](https://github.com/paradedb/paradedb/discussions)

If you need commercial support, please [contact the ParadeDB team](mailto:sales@paradedb.com).

## Acknowledgments

We would like to thank the following members of the community for their valuable feedback and reviews during the development of this package:

- [Eric Barendt](https://github.com/ebarendt) - Engineering at Modern Treasury
- [Matthew Higgins](https://github.com/matthuhiggins) - Engineering at Modern Treasury
- [Patrick Schmitz](https://github.com/bullfight) - Engineering at Modern Treasury

## License

ParadeDB for Rails is licensed under the [MIT License](LICENSE).
