# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Client API Builder is a Ruby gem for creating API clients through declarative configuration. It uses Ruby's module inclusion pattern with `ClientApiBuilder::Router` as the core component.

## Common Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/client_api_builder/router_spec.rb

# Run a specific test by line number
bundle exec rspec spec/client_api_builder/router_spec.rb:42

# Run linter
bundle exec rubocop

# Build the gem
gem build client-api-builder.gemspec
```

## Architecture

### Core Components

- **Router** (`lib/client_api_builder/router.rb`): Main module providing `route`, `base_url`, `header`, `body_builder`, `query_builder`, and `configure_retries` class methods. Uses `InheritanceHelper::Methods` for configuration inheritance.

- **NestedRouter** (`lib/client_api_builder/nested_router.rb`): Enables hierarchical API organization. Maintains reference to `root_router` and shares configuration with parent.

- **Section** (`lib/client_api_builder/section.rb`): Provides `section` class method for creating nested route groups via dynamically generated classes.

- **NetHTTP::Request** (`lib/client_api_builder/net_http_request.rb`): HTTP request execution using `Net::HTTP`. Handles standard requests and streaming (`:file`, `:io`, `:block` modes).

- **QueryParams** (`lib/client_api_builder/query_params.rb`): Custom query parameter builder used when ActiveSupport's `to_query` is unavailable.

- **ActiveSupportNotifications/LogSubscriber**: Optional integration for logging and instrumentation when ActiveSupport is present.

### Route Code Generation

The `route` class method in Router uses `generate_route_code` to dynamically create two methods per route:
1. `method_name_raw_response` - Makes the HTTP request
2. `method_name` - Wraps the request with retry logic and response handling

### HTTP Method Auto-Detection

Methods are auto-detected from route names: `post/create/add/insert` → POST, `put/update/modify/change` → PUT, `patch` → PATCH, `delete/remove` → DELETE, others → GET.

### Configuration Hierarchy

1. `default_options` class method (base defaults)
2. Class-level configuration via DSL methods
3. Instance-level overrides
4. Request-level options (`**__options__`)

## Key Patterns

- Module inclusion with `self.included(base)` extending ClassMethods and including InstanceMethods
- `add_value_to_class_method` from `inheritance-helper` for configuration inheritance
- Response procs stored per method name for custom response handling
- `root_router` method for accessing the top-level router from nested routers

## Dependencies

- `inheritance-helper` (runtime): Class inheritance and method management
- `webmock` (test): HTTP request stubbing
- `activesupport` (optional): Enhanced query param building and instrumentation

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
- **Code comments** - Update inline documentation when changing method signatures or behavior
