# Changelog

## [0.11.0](https://github.com/dougyouch/client-api-builder/compare/v0.10.0...v0.11.0) (2026-10-04)


### Features

* **thread_connections:** add per-thread persistent connections ([3ad347d](https://github.com/dougyouch/client-api-builder/commit/3ad347d7a022b60dfb9e0d36de5260dd37f456be))
* **thread_connections:** add per-thread persistent connections ([4f61cd9](https://github.com/dougyouch/client-api-builder/commit/4f61cd94731ac81c0993bfbee8acf6c9c4328ce2))

## [0.10.0](https://github.com/dougyouch/client-api-builder/compare/v0.9.0...v0.10.0) (2026-10-04)


### Features

* add opt-in HTTP/2 support ([48c6f6e](https://github.com/dougyouch/client-api-builder/commit/48c6f6e37b9c346d2e8b70db30a72661ea18358e))
* **http2:** add opt-in HTTP/2 support ([10ee136](https://github.com/dougyouch/client-api-builder/commit/10ee13677d1914dd37dd5efb2afee9779e2fdbda))


### Performance Improvements

* **http2:** add HTTP/1.1 vs HTTP/2 benchmark script ([29b9add](https://github.com/dougyouch/client-api-builder/commit/29b9adde11ae6dcf55a5f2eedf0c1826774bb51a))

## [0.9.0](https://github.com/dougyouch/client-api-builder/compare/v0.8.0...v0.9.0) (2026-10-04)


### Features

* add connection pools and exponential retry backoff ([e076162](https://github.com/dougyouch/client-api-builder/commit/e076162539aa9e92c1ec9bbdb5033de4cc163a14))
* **connection-pools:** add opt-in persistent connection pools ([d172764](https://github.com/dougyouch/client-api-builder/commit/d17276410b007d15d577693677bd17f0a4be0a27))
* **connection-pools:** add opt-in persistent connection pools ([df6fe98](https://github.com/dougyouch/client-api-builder/commit/df6fe9807ae9b0afb6b8f239ced15b6d5f984eea))
* **connection-pools:** let sections configure their own connection pools ([b0e17e3](https://github.com/dougyouch/client-api-builder/commit/b0e17e34efaeaa731f854e2e58348c5ae87c7cfa))
* **router:** add exponential backoff and jitter to retries ([59daf51](https://github.com/dougyouch/client-api-builder/commit/59daf51757f0b26d19064493cc499fc2cbef8954))

## [0.8.0](https://github.com/dougyouch/client-api-builder/compare/v0.7.2...v0.8.0) (2026-10-03)


### Features

* **section:** let sections inherit root client headers, query params and connection options ([8849d98](https://github.com/dougyouch/client-api-builder/commit/8849d9875c86633639bf33c5e9b1eb486f67e921))

## [0.7.2](https://github.com/dougyouch/client-api-builder/compare/v0.7.1...v0.7.2) (2026-10-03)


### Bug Fixes

* **notifications:** report request exceptions to subscribers ([5c29e71](https://github.com/dougyouch/client-api-builder/commit/5c29e71b2ed23016fa68fce3b3aeda3cebdd1e21))
* **router:** check the base URL used for each request ([e9ea9c8](https://github.com/dougyouch/client-api-builder/commit/e9ea9c808569adf251247a849d6d5727cd3d2772))
* **router:** clear the previous response before each attempt ([861ae3e](https://github.com/dougyouch/client-api-builder/commit/861ae3e9fd73b45cbb7be33de09b3cf19ffae028))
* **router:** clear the response block when a route is redefined without one ([cca46c3](https://github.com/dougyouch/client-api-builder/commit/cca46c3e87176d37e953de1ec159b4cb3fd5f4a0))
* **router:** fill in every placeholder in query and body strings ([beb2d89](https://github.com/dougyouch/client-api-builder/commit/beb2d890f20423b792733919e4fded51fe47c5ee))
* **router:** only resolve symbols and procs for class-level headers and query params ([bfa29f1](https://github.com/dougyouch/client-api-builder/commit/bfa29f18d28e32eff4268b3dd3343162289140d1))
* **router:** reject route values that can't be compiled into the generated method ([2a5cdad](https://github.com/dougyouch/client-api-builder/commit/2a5cdad5c338ee8f05b0a3b3739c937f1fa48375))
* **router:** require a whole verb when detecting the HTTP method ([0bfa860](https://github.com/dougyouch/client-api-builder/commit/0bfa8601a454e8ecf27a496dd894a7a8c67a2351))
* **router:** stop route from modifying the caller's query and body ([faaee75](https://github.com/dougyouch/client-api-builder/commit/faaee756c81d258516422405ee3ac63fe9227771))
* **router:** treat a colon after a word as literal path text ([5dae4b0](https://github.com/dougyouch/client-api-builder/commit/5dae4b0bb3e0b850775f62541024d3e441cf87a1))
* **section:** define section methods with closures instead of generated source ([d9e23a6](https://github.com/dougyouch/client-api-builder/commit/d9e23a6c8bb010ed5a76993fd0ec6014cd0acb18))
* **stream:** check the response status before streaming the body ([eeb9e3b](https://github.com/dougyouch/client-api-builder/commit/eeb9e3b3895f4571bff147e5f75695e4f7324868))
* **stream:** reject only parent path segments in file names ([09c355d](https://github.com/dougyouch/client-api-builder/commit/09c355dc3c68dd06e07c8c9dfe003d7daf1153f6))

### Upgrade Notes

* Per-request `headers:` and `query:` values and route arguments are now sent as given. A Symbol there (e.g. `query: { order: :desc }`) is sent as the value `desc` instead of calling a method of that name. Symbols and blocks given to the class-level `header` and `query_param` are still resolved on the client.
* HTTP method detection now needs the whole verb: route names where the verb runs into the next word (`posts`, `addresses`, `deleted_users`, `updates_feed`, `changelog`) now default to GET instead of POST, PUT or DELETE. Add `method:` to such routes to keep the old method.
* Redefining a route without a block, in the same class or a subclass, no longer keeps the previous or inherited response block. Pass the block again to keep it.
* A `:name` directly after a letter, digit, `_` or `}` is now literal path text, so `/v1/items:batchGet` works; a mid-word parameter such as `/items:id` no longer becomes an argument.
* Route `query:`/`body:` values must be strings, numbers, booleans, `nil`, hashes or arrays. `Range`, `Regexp`, `BigDecimal`, `Complex`, `Time` and other objects now raise an `ArgumentError` naming the route when the class loads; write them as a string or use a `'{method}'` placeholder.

## [0.7.1](https://github.com/dougyouch/client-api-builder/compare/v0.7.0...v0.7.1) (2026-10-03)


### Bug Fixes

* **router:** detect destroy_ routes as DELETE ([85604c4](https://github.com/dougyouch/client-api-builder/commit/85604c4d974c8483e292e700eb51a2c78e312b54))
* **router:** url-encode path values ([76d6fb4](https://github.com/dougyouch/client-api-builder/commit/76d6fb4fa246b342e263322d06262cba6760c278))

### Upgrade Notes

* Path values are now percent-encoded by `escape_path`, including `/`. A value like `'a/b'` that previously expanded into two path segments is now sent as one segment (`a%2Fb`). To keep `/` as a separator, override `escape_path` in your client, e.g. `value.to_s.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')`.

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
