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
    └── active_support_log_subscriber.rb # ActiveSupport logging
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
- `build_headers`: Constructs request headers, evaluating procs/symbols
- `build_connection_options`: Merges default and request-specific options
- `build_query`: Formats query parameters using configured builder
- `build_body`: Formats request body using configured builder
- `build_uri`: Constructs full URI with base_url, path, and query
- `handle_response`: Processes API responses, parses JSON by default
- `request_wrapper`: Manages request execution with retry and instrumentation
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
- `get_user_raw_response(id:, **options, &block)` - Makes HTTP request, sets `@response` and `@request_options`
- `get_user(id:, **options, &block)` - Wraps raw_response with retry logic, response code validation, and response handling

**Path Parameters**: Extracted from `:param` or `{param}` syntax in path
**Body/Query Parameters**: Extracted from `body:` and `query:` options using symbol values

### 3. HTTP Method Auto-Detection

When `method:` is not specified in route options, `auto_detect_http_method` infers it from the method name:

| Prefix Pattern | HTTP Method |
|---------------|-------------|
| `post`, `create`, `add`, `insert` | POST |
| `put`, `update`, `modify`, `change` | PUT |
| `patch` | PATCH |
| `delete`, `remove` | DELETE |
| (default) | GET |

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
- Delegates `handle_response` to root_router
- Overrides `get_instance_method` to access root_router's instance variables in paths

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
- `stream(...)` - Streams response body in chunks via `read_body`
- `stream_to_io(..., io:)` - Writes streamed chunks to an IO object
- `stream_to_file(..., file:)` - Opens file and streams to it

**Supported HTTP Methods** (via `METHOD_TO_NET_HTTP_CLASS`):
`copy`, `delete`, `get`, `head`, `lock`, `mkcol`, `move`, `options`, `patch`, `post`, `propfind`, `proppatch`, `put`, `trace`, `unlock`

### 7. QueryParams Class

Standalone query parameter builder (used when ActiveSupport unavailable):

- Handles nested hashes with bracket notation: `user[name]=John`
- Handles arrays: `ids[]=1&ids[]=2`
- Configurable separators: `name_value_separator` (default `=`), `param_separator` (default `&`)
- Supports custom escape proc

### 8. ActiveSupport Integration

**ActiveSupportNotifications** (conditionally included when ActiveSupport defined):
- Overrides `instrument_request` to use `ActiveSupport::Notifications.instrument`
- Event name: `client_api_builder.request`
- Payload includes `client: self`

**ActiveSupportLogSubscriber**:
- Subscribes to `client_api_builder.request` events for logging

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

1. **Default Options**: `Router.default_options` returns frozen hash with defaults
2. **Class-level Configuration**: Set through DSL methods, stored via `add_value_to_class_method`
3. **Instance-level**: Access class config, can override in method calls
4. **Request-level**: `**__options__` parameter on generated methods

## Error Handling

- `ClientApiBuilder::Error`: Base error class
- `ClientApiBuilder::UnexpectedResponse`: Raised when response code doesn't match expected codes
  - Stores `response` for inspection
- Response procs: Per-route custom response handling stored in `default_options[:response_procs]`
- Retry on exception: `retry_request?` method (always returns true by default, override to customize)

## Streaming Support

Routes can specify streaming behavior:

```ruby
route :download, '/file', stream: :file    # stream_to_file, requires file: argument
route :stream, '/events', stream: :io      # stream_to_io, requires io: argument
route :process, '/data', stream: :block    # stream with block for each chunk
route :download, '/file', stream: true     # alias for :file
```

## Dependencies

- `inheritance-helper`: Class inheritance and configuration management
- `json`: JSON parsing and serialization (stdlib)
- `net/http`: HTTP request handling (stdlib)
- `cgi`: URL encoding in QueryParams (stdlib)
- `active_support` (optional): Enhanced query building and instrumentation

## Thread Safety

The library is not thread-safe. Each client instance maintains state (`@response`, `@request_options`, etc.) that would cause race conditions if shared across threads. Create separate client instances per thread.
