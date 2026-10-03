# Client API Builder Architecture

This document describes the internal architecture and design of the Client API Builder gem.

## Overview

Client API Builder is a Ruby gem that provides a declarative way to create API clients. It uses a modular architecture with several key components working together to provide a flexible and extensible API client framework.

## File Structure

```
lib/
├── client-api-builder.rb              # Main entry point, autoloads, error classes
└── client_api_builder/
    ├── router.rb                      # Core Router module with route DSL
    ├── nested_router.rb               # NestedRouter class for hierarchical APIs
    ├── section.rb                     # Section module for creating nested routers
    ├── net_http_request.rb            # Net::HTTP request execution and streaming
    ├── query_params.rb                # Custom query parameter builder
    ├── active_support_notifications.rb # ActiveSupport instrumentation
    ├── active_support_log_subscriber.rb # ActiveSupport logging
    └── version.rb                     # Gem version, bumped by release-please
```

## Core Components

### 1. Router Module (`ClientApiBuilder::Router`)

The `Router` module is the core component that provides the main functionality for defining and executing API requests.

**Class Methods** (defined in `ClassMethods`):
- `base_url`: Sets the base URL for all requests
- `header`: Adds headers to requests (supports values, symbols, or procs)
- `route`: Defines API endpoints with dynamic method generation
- `body_builder`: Configures request body formatting (`:to_json`, `:to_query`, `:query_params`, or custom)
- `query_builder`: Configures query parameter formatting
- `query_param`: Adds query parameters to all requests
- `connection_option`: Sets Net::HTTP connection options
- `configure_retries`: Sets retry behavior (max_retries, sleep time)
- `namespace`: Groups routes under a common path prefix

**Instance Methods**:
- `build_headers`: Constructs request headers: class-level symbols/procs are resolved (`resolve_config_value`), per-request headers are merged as given, values become strings and `nil` drops a header
- `build_connection_options`: Merges default and request-specific options
- `build_query`: Resolves class-level `query_param` symbols/procs, merges route and per-request values as given, and formats them with the configured builder
- `build_body`: Formats request body using configured builder
- `build_uri`: Constructs full URI with base_url, path, and query
- `handle_response`: Processes API responses, parses JSON by default
- `request_wrapper`: Manages request execution with retry and instrumentation; clears `@request_options` and `@response` before each attempt
- `expected_response_code!`: Raises `UnexpectedResponse` unless the code is expected (any 2xx when none are configured)
- `parse_response`: Parses JSON bodies, returning `nil` for empty ones
- `retry_request?`: Decides whether an exception is retried (network errors only by default)
- `escape_path`: Percent-encodes path values (`ERB::Util.url_encode`) so each stays one segment; override to change
- `root_router`: Returns self (overridden in NestedRouter)

**Instance Attributes** (via `attr_reader`):
- `response`: The last Net::HTTP response object
- `request_options`: Hash of method, uri, body, headers, connection_options
- `total_request_time`: Duration of last request in seconds
- `request_attempts`: Number of attempts for last request

### 2. Route Code Generation

The `route` class method dynamically generates two methods per endpoint using `generate_route_code`:

```ruby
route :get_user, '/users/:id', expected_response_code: 200
```

Generates:
- `get_user_raw_response(id:, **__options__, &block)` - Makes HTTP request, sets `@response` and `@request_options`
- `get_user(id:, **__options__, &block)` - Wraps raw_response with retry logic, response code validation, and response handling

**Keyword arguments** come from `:param` segments in the path and symbol values in `body:` and `query:`. Routes that need a body but don't define one get a `body:` argument, and streaming routes get `file:` or `io:`.
**Instance values**: `{name}` in the path, or in a `body:`/`query:` string, compiles to a bare `name` reference, so it uses a route argument of that name if there is one and otherwise calls the client's method. A string that is exactly `'{name}'` passes the value through with its type; placeholders within text compile to an interpolated string (literal text escaped with `inspect`).
**Code snippets**: `get_arguments` replaces these values with `ClassMethods::CodeSnippet` objects holding Ruby source, which `value_to_code` writes into the generated method verbatim.
**Values in the generated code** are rendered by `value_to_code`, which keeps symbol keys as `key: value` so the output is the same on every Ruby version.

`generate_route_code` rejects method names that aren't plain identifiers, since the name is interpolated into the generated source.

### 3. HTTP Method Auto-Detection

When `method:` is not specified in route options, `auto_detect_http_method` infers it from the method name:

| Prefix Pattern | HTTP Method |
|---------------|-------------|
| `post`, `create`, `add`, `insert` | POST |
| `put`, `update`, `modify`, `change` | PUT |
| `patch` | PATCH |
| `delete`, `remove`, `destroy` | DELETE |
| (default) | GET |

The verb must be the whole name or be followed by `_` (`\A(?:delete|remove|destroy)(?:_|\z)`), so `deleted_users` and `posts` are GET.

### 4. Nested Router (`ClientApiBuilder::NestedRouter`)

Enables hierarchical API client organization:

```ruby
section :users do
  route :list, '/'
  route :get, '/:id'
end
# Usage: client.users.get(id: 123)
```

Key behaviors:
- Includes `ClientApiBuilder::Router` module
- Stores `root_router` reference to access shared state
- Stores `nested_router_options` passed from section definition
- Overrides `base_url` to fall back to root_router's base_url
- Delegates `handle_response` to root_router, so response blocks run on the root client
- Overrides `get_instance_method` so `{name}` path values call `root_router.name` (still passed through `escape_path`)
- Class-level header and query param symbols and procs are evaluated on root_router (as on any router)
- Has its own `default_options`: headers, query params, connection options, retries and builders are not inherited from the root router
- `nested_router_options` are stored but not read by the library

### 5. Section Module (`ClientApiBuilder::Section`)

Creates nested routers dynamically using `InheritanceHelper::ClassBuilder::Utils.create_class`:

```ruby
def section(name, nested_router_options={}, &block)
  # Creates: MyClient::UsersNestedRouter < ClientApiBuilder::NestedRouter
  # Defines: MyClient.users_router (class method)
  # Defines: MyClient#users (instance method, memoized)
end
```

### 6. NetHTTP::Request Module

Provides HTTP request execution using Net::HTTP:

**Methods**:
- `request(method:, uri:, body:, headers:, connection_options:)` - Standard request with optional block
- `stream(..., validate_response: nil)` - Streams response body in chunks via `read_body`
- `stream_to_io(..., io:, validate_response: nil)` - Writes streamed chunks to an IO object
- `stream_to_file(..., file:, validate_response: nil)` - Opens the file once the response is accepted and streams to it

`validate_response` is a callable run with the response before any of the body is read; it rejects the response by raising. The rejected body is read into `response.body` so the error can show it. Streaming routes pass `->(response) { expected_response_code!(response, codes, __options__) }`, so streaming follows the same status rules (and any `expected_response_code!` override) as other routes.

**Supported HTTP Methods** (via `METHOD_TO_NET_HTTP_CLASS`):
`copy`, `delete`, `get`, `head`, `lock`, `mkcol`, `move`, `options`, `patch`, `post`, `propfind`, `proppatch`, `put`, `trace`, `unlock`

### 7. QueryParams Class

Standalone query parameter builder (the default `query_builder` when `Hash#to_query` is unavailable, and the `:query_params` builder option):

- Handles nested hashes with bracket notation: `user[name]=John`
- Handles arrays: `ids[]=1&ids[]=2`
- Configurable separators: `name_value_separator` (default `=`), `param_separator` (default `&`)
- Supports custom escape proc

### 8. ActiveSupport Integration

**ActiveSupportNotifications** (included when `ActiveSupport` is defined at the time a class includes `Router`):
- Overrides `instrument_request` to use `ActiveSupport::Notifications.instrument`
- Event name: `client_api_builder.request`
- Payload includes `client: self`; when the attempt raises, ActiveSupport adds `:exception` and `:exception_object` and re-raises the original exception

**ActiveSupportLogSubscriber**:
- Subscribes to `client_api_builder.request` events for logging
- Logs `METHOD scheme://host/path[code] took Nms`, leaving out the query string; `[UNKNOWN]` when no response arrived, `[request not built]` when the request failed before it was built, and a trailing `(ExceptionClass: message)` when the attempt raised

Without ActiveSupport, `Router#instrument_request` only records `total_request_time`.

**`ClientApiBuilder.logger`**: when set, `retry_request` logs every exception raised by a request attempt.

## Design Patterns

### Module Inclusion Pattern

```ruby
module ClientApiBuilder
  module Router
    def self.included(base)
      base.extend InheritanceHelper::Methods
      base.extend ClassMethods
      base.include ::ClientApiBuilder::Section
      base.include ::ClientApiBuilder::NetHTTP::Request
      base.include(::ClientApiBuilder::ActiveSupportNotifications) if defined?(ActiveSupport)
      base.send(:attr_reader, :response, :request_options, :total_request_time, :request_attempts)
    end
  end
end
```

### Builder Pattern

Request components built separately then combined:
```ruby
__uri__ = build_uri(__path__, __query__, __options__)
__body__ = build_body(__body__, __options__)
__headers__ = build_headers(__options__)
__connection_options__ = build_connection_options(__options__)
```

### Configuration Inheritance

Uses `inheritance-helper` gem's `add_value_to_class_method` for configuration that properly inherits to subclasses:
```ruby
def base_url(url = nil)
  return default_options[:base_url] unless url
  add_value_to_class_method(:default_options, base_url: url)
end
```

## Configuration Hierarchy

1. **Default Options**: `ClassMethods#default_options` returns a frozen hash of defaults
2. **Class-level Configuration**: DSL methods redefine `default_options` via `add_value_to_class_method`; subclasses inherit it
3. **Instance overrides**: Clients can override instance methods such as `base_url` or the hooks above
4. **Request-level**: `**__options__` on generated methods (`headers:`, `query:`, `body:`, `connection_options:`, `retries:`, `sleep:`, `return:`)

## Error Handling

- `ClientApiBuilder::Error`: Base error class
- `ClientApiBuilder::UnexpectedResponse`: Raised when response code doesn't match expected codes
  - Stores `response` for inspection
  - Also raised for response bodies that aren't valid JSON
- Response procs: Per-route custom response handling stored in `default_options[:response_procs]`; a block passed to the call takes precedence
- Retry on exception: `retry_request?` returns true only for network errors (`Net::OpenTimeout`, `Net::ReadTimeout`, `Errno::ECONNRESET`, `Errno::ECONNREFUSED`, `Errno::ETIMEDOUT`, `SocketError`, `EOFError`); override to customize
- Retries count total attempts: `configure_retries 3` makes at most 3 attempts, and the default of 1 means no retries

## Streaming Support

Routes can specify streaming behavior:

```ruby
route :download, '/file', stream: :file    # stream_to_file, requires file: argument
route :stream, '/events', stream: :io      # stream_to_io, requires io: argument
route :process, '/data', stream: :block    # stream with block for each chunk
route :download, '/file', stream: true     # alias for :file
```

`stream_to_file` takes the file mode from the `:file_mode` connection option (default `wb`, limited to `ALLOWED_FILE_MODES`) and rejects paths containing `..` or a null byte. It opens the file only after `validate_response` accepts the response, so an error never creates, truncates or appends to it. Streaming routes return the `Net::HTTPResponse`.

## Dependencies

- `inheritance-helper`: Class inheritance and configuration management
- `json`: JSON parsing and serialization (stdlib)
- `net/http`: HTTP request handling (stdlib)
- `cgi`: URL encoding in QueryParams (stdlib)
- `active_support` (optional): Enhanced query building and instrumentation

## Thread Safety

The namespace stack used while defining routes is thread-local. Clients themselves are not thread-safe. Each client instance maintains state (`@response`, `@request_options`, etc.) that would cause race conditions if shared across threads. Create separate client instances per thread.
