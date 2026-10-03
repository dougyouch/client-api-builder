# Changelog

## [0.7.0](https://github.com/dougyouch/client-api-builder/compare/v0.6.1...v0.7.0) (2026-10-03)


### ⚠ BREAKING CHANGES

* client-api-builder now requires Ruby 3.2 or newer (previously 3.0). Ruby 3.0 and 3.1 are end-of-life. ([7c951e0](https://github.com/dougyouch/client-api-builder/commit/7c951e0))

### Packaging

* ship only `lib/`, `README.md`, `LICENSE` and `CHANGELOG.md` in the gem instead of every tracked file ([ca141a1](https://github.com/dougyouch/client-api-builder/commit/ca141a1))
* refresh the gem summary and description ([ca141a1](https://github.com/dougyouch/client-api-builder/commit/ca141a1))
* add `ClientApiBuilder::VERSION` ([7c951e0](https://github.com/dougyouch/client-api-builder/commit/7c951e0))

### Build

* automate versioning, changelog and RubyGems publishing with release-please ([7c951e0](https://github.com/dougyouch/client-api-builder/commit/7c951e0))
* replace Codecov with a GitHub-hosted coverage badge ([7c951e0](https://github.com/dougyouch/client-api-builder/commit/7c951e0))
* adopt the dynamic-active-model RuboCop config with rubocop-rspec ([f36ed6f](https://github.com/dougyouch/client-api-builder/commit/f36ed6f))
