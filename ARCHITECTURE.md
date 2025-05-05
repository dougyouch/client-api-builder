# Client API Builder Architecture

This document describes the internal architecture and design of the Client API Builder gem.

## Overview

Client API Builder is a Ruby gem that provides a declarative way to create API clients. It uses a modular architecture with several key components working together to provide a flexible and extensible API client framework.

## Core Components

### 1. Router Module (`ClientApiBuilder::Router`)

The `Router` module is the core component that provides the main functionality for defining and executing API requests. It includes:

- **Class Methods**: Configuration methods for setting up the API client
  - `base_url`: Sets the base URL for all requests
  - `header`: Adds headers to requests
  - `route`: Defines API endpoints
  - `body_builder`: Configures how request bodies are formatted
  - `query_builder`: Configures how query parameters are formatted
  - `configure_retries`: Sets retry behavior for failed requests

- **Instance Methods**: Methods for executing requests and handling responses
  - `build_headers`: Constructs request headers
  - `build_connection_options`: Sets up connection options
  - `build_query`: Formats query parameters
  - `build_body`: Formats request body
  - `handle_response`: Processes API responses
  - `request_wrapper`: Manages request execution and retries

### 2. Nested Router (`ClientApiBuilder::NestedRouter`)

The `NestedRouter` class enables hierarchical API client organization by allowing routes to be grouped under namespaces. It:

- Inherits from the base Router functionality
- Maintains a reference to its root router
- Allows for nested route definitions
- Shares configuration with its parent router

### 3. Section Module (`ClientApiBuilder::Section`)

The `Section` module provides the mechanism for creating nested routers. It:

- Defines the `section` class method for creating nested route groups
- Dynamically generates methods for accessing nested routers
- Handles the creation of nested router classes

### 4. Request Handling

The request handling system is built on top of Ruby's `Net::HTTP` and includes:

- **Request Building**: Constructs HTTP requests with proper headers, body, and query parameters
- **Response Processing**: Handles different response formats and status codes
- **Error Handling**: Provides custom error classes for API-specific errors
- **Retry Mechanism**: Implements configurable retry logic for failed requests

### 5. ActiveSupport Integration

The gem integrates with ActiveSupport for:

- **Logging**: Provides request/response logging
- **Notifications**: Implements instrumentation for request timing and monitoring
- **Query Parameter Building**: Uses ActiveSupport's parameter formatting when available

## Design Patterns

### 1. Module Inclusion Pattern

The gem uses Ruby's module inclusion pattern extensively:

```ruby
module ClientApiBuilder
  module Router
    def self.included(base)
      base.extend ClassMethods
      base.include InstanceMethods
    end
  end
end
```

This pattern allows for clean separation of class and instance methods while maintaining a single namespace.

### 2. Builder Pattern

The request building process follows the builder pattern:

```ruby
def build_headers(options)
  headers = {}
  # ... build headers
  headers
end
```

Each component (headers, body, query) is built separately and then combined into the final request.

### 3. Decorator Pattern

The nested router implementation uses a decorator-like pattern:

```ruby
class NestedRouter
  include ::ClientApiBuilder::Router
  attr_reader :root_router
  # ... adds additional functionality while delegating to root_router
end
```

## Configuration Management

The gem uses a hierarchical configuration system:

1. **Default Options**: Defined in `Router.default_options`
2. **Class-level Configuration**: Set through class methods
3. **Instance-level Configuration**: Can override class-level settings
4. **Request-level Configuration**: Specific to individual requests

## Error Handling

The error handling system includes:

- `ClientApiBuilder::Error`: Base error class
- `ClientApiBuilder::UnexpectedResponse`: For handling unexpected API responses
- Custom error handling through response procs

## Extensibility

The architecture is designed to be extensible through:

1. **Custom Body Builders**: Implement custom body formatting
2. **Custom Query Builders**: Implement custom query parameter formatting
3. **Response Processors**: Add custom response handling
4. **Nested Routers**: Create custom nested router implementations

## Dependencies

- `inheritance-helper`: For class inheritance and method management
- `json`: For JSON parsing and serialization
- `net/http`: For HTTP request handling
- `active_support` (optional): For additional functionality when available

## Performance Considerations

1. **Request Caching**: No built-in request caching
2. **Connection Pooling**: Uses standard Net::HTTP connection handling
3. **Memory Usage**: Minimal object creation during request processing
4. **Thread Safety**: No explicit thread safety mechanisms 