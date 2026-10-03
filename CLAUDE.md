# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Client API Builder is a Ruby gem for creating API clients through declarative configuration. It uses Ruby's module inclusion pattern with `ClientApiBuilder::Router` as the core component.

## Common Commands

Development uses the Ruby in `.ruby-version` (4.0.x), which `Gemfile.lock` is resolved against. The gem itself supports Ruby 3.2+ (`required_ruby_version` and RuboCop's `TargetRubyVersion`).

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run all tests with the CI coverage gate (fails below 100% line or branch coverage)
CI=true bundle exec rspec

# Run a single test file
bundle exec rspec spec/client_api_builder/router_spec.rb

# Run a specific test by line number
bundle exec rspec spec/client_api_builder/router_spec.rb:42

# Run linter
bundle exec rubocop

# Build the gem
gem build client-api-builder.gemspec

# IRB with the gem and the example clients loaded
script/console
```

## Testing

- Line and branch coverage must stay at **100%**. `spec/spec_helper.rb` sets `minimum_coverage line: 100, branch: 100` when `CI` is set, so CI fails on any uncovered line or branch. Local runs skip the gate so single spec files can run; use `CI=true bundle exec rspec` before pushing.
- Every new line or branch in `lib/` needs a spec. Coverage is measured over `lib/**/*.rb`, except `lib/client_api_builder/version.rb`, which loads before SimpleCov starts.
- HTTP is stubbed with WebMock; real connections are disabled.
- Spec layout: `router_spec.rb` (DSL and generated code against known output), `router_code_generation_spec.rb` (code generation branches), `router_requests_spec.rb` (end-to-end request behavior), `router_security_spec.rb`, plus one spec per remaining class.
- RuboCop runs with `rubocop-rspec`; keep `bundle exec rubocop` clean.

## Architecture

### Core Components

- **Router** (`lib/client_api_builder/router.rb`): Main module. Its `ClassMethods` provide the DSL (`base_url`, `header`, `query_param`, `connection_option`, `body_builder`, `query_builder`, `configure_retries`, `namespace`, `route`) and the code generator; the request/response instance methods are defined on `Router` itself. Uses `InheritanceHelper::Methods` for configuration inheritance.

- **NestedRouter** (`lib/client_api_builder/nested_router.rb`): Base class for sections. Holds a `root_router` reference: it falls back to the root's `base_url`, delegates `handle_response` to it, and resolves `{name}` path values on it. By default it does **not** inherit the root's headers, query params, connection options or retry settings; `section :x, inherit: [...]` / `inherit_from_root` opts into the root's headers, query params and/or connection options (merged beneath the section's own via the `configured_*` methods).

- **Section** (`lib/client_api_builder/section.rb`): Provides `section` class method for creating nested route groups via dynamically generated classes. `<name>_router` and `<name>` are defined with closures (not generated source), so sections work on anonymous classes.

- **NetHTTP::Request** (`lib/client_api_builder/net_http_request.rb`): HTTP request execution using `Net::HTTP`. Handles standard requests and streaming (`:file`, `:io`, `:block` modes).

- **RouteValueValidator** (`lib/client_api_builder/route_value_validator.rb`): Checks a route's `query:`/`body:` values can be compiled into generated source (strings, numbers, booleans, nil, hashes, arrays, argument symbols); raises `ArgumentError` naming the route otherwise.

- **QueryParams** (`lib/client_api_builder/query_params.rb`): Custom query parameter builder used when ActiveSupport's `to_query` is unavailable.

- **ActiveSupportNotifications/LogSubscriber**: Optional instrumentation (`client_api_builder.request` events) and logging. Notifications are included only if `ActiveSupport` is defined when a class includes `Router`.

- **Version** (`lib/client_api_builder/version.rb`): `ClientApiBuilder::VERSION`, read by the gemspec and bumped by release-please.

### Route Code Generation

The `route` class method in Router uses `generate_route_code` to dynamically create two methods per route:
1. `method_name_raw_response` - Makes the HTTP request
2. `method_name` - Wraps the request with retry logic and response handling

Keyword arguments come from `:param` in the path (`PATH_PARAMETER`; a colon after a letter, digit, `_` or `}` is literal, e.g. `items:batchGet`) and symbol values in `query:`/`body:`. `{name}` in the path or in `query:`/`body:` strings becomes a bare `name` reference: the route argument if one exists, otherwise the client's method (sections' path values always call `root_router.name`). Exactly `'{name}'` keeps the value's type; placeholders within text are interpolated. `get_arguments` swaps these values for `CodeSnippet` objects that `value_to_code` writes verbatim. `router_spec.rb` asserts exact generated source, so changes to the generator usually need those expectations updated. `get_arguments` rewrites values in place, so the generator works on `deep_dup` copies; never pass the caller's `query:`/`body:` to it directly.

### HTTP Method Auto-Detection

Methods are auto-detected from the start of route names: `post/create/add/insert` → POST, `put/update/modify/change` → PUT, `patch` → PATCH, `delete/remove/destroy` → DELETE, others → GET. The verb must be the whole name or followed by `_` (`deleted_users`, `posts` → GET).

### Behaviors Worth Knowing

- Without `expected_response_code(s)`, any 2xx is accepted; with them, only the listed codes.
- `response`/`request_options` are cleared at the start of each attempt, so after a failure they are `nil` rather than the previous call's.
- Streaming routes validate the status (via `validate_response:` → `expected_response_code!`) before streaming; error bodies go to `response.body`, never the file/IO/block.
- `configure_retries(n)` sets total attempts (default 1, so no retries). Only network errors are retried (`retry_request?`).
- Symbols/procs are resolved (on `root_router`) only for class-level `header`/`query_param` values. Route arguments and per-request `headers:`/`query:` are data and are sent as given.
- `escape_path` percent-encodes every path value (arguments and `{name}`), including `/`, so each stays one segment.
- HTTPS gets `VERIFY_PEER` and 30s/60s timeouts by default; user connection options override them.

### Configuration Hierarchy

1. `default_options` class method (base defaults)
2. Class-level configuration via DSL methods (inherited by subclasses)
3. Instance method overrides (e.g. `base_url`, `escape_path`, `retry_request?`)
4. Request-level options (`**__options__`: `headers:`, `query:`, `body:`, `connection_options:`, `retries:`, `sleep:`, `return:`)

## Key Patterns

- Module inclusion with `self.included(base)`: extends `ClassMethods`, includes `Section`, `NetHTTP::Request` and (with ActiveSupport) `ActiveSupportNotifications`
- `add_value_to_class_method` from `inheritance-helper` for configuration inheritance
- Response procs stored per method name for custom response handling
- `root_router` method for accessing the top-level router from nested routers

## Dependencies

- `inheritance-helper` (runtime): Class inheritance and method management
- `activesupport` (optional at runtime, installed for development): `to_query` builders and instrumentation
- Development: `rspec`, `webmock`, `simplecov`, `rubocop`, `rubocop-rspec`, `rake`

## CI

`.github/workflows/ci.yml` runs RuboCop and the specs on the `.ruby-version` Ruby. On pushes to `master`, it publishes `coverage.svg` and `branches.svg` (from `script/coverage_badge.rb`) to the orphan `badges` branch for the README badges.

## Releases

Releases are automated by release-please (`.github/workflows/release.yml`). Conventional commits on `master` (`fix:` → patch, `feat:` → minor, `!`/`BREAKING CHANGE` → major) update an open release PR that bumps `lib/client_api_builder/version.rb`, `Gemfile.lock`, and `CHANGELOG.md`. Merging that PR tags `vX.Y.Z`, creates the GitHub release, and publishes the gem to RubyGems. Don't bump the version by hand.

## Code Commits

Format using angular formatting:
```
<type>(<scope>): <short summary>
```
- **type**: build|ci|docs|feat|fix|perf|refactor|test
- **scope**: The feature or component of the service we're working on
- **summary**: Summary in present tense. Not capitalized. No period at the end.

## Documentation Maintenance

When modifying the codebase, keep documentation in sync:
- **ARCHITECTURE.md** - Update when adding/removing classes, changing component relationships, or altering data flow patterns
- **README.md** - Update when adding new features, changing public APIs, or modifying usage examples
- **CHANGELOG.md** - Generated by release-please from commit messages; don't edit by hand except to fix release notes
- **Code comments** - Update inline documentation when changing method signatures or behavior
