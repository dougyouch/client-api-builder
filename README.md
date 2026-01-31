# Client API Builder

[![Gem Version](https://badge.fury.io/rb/client-api-builder.svg)](https://badge.fury.io/rb/client-api-builder)
[![CI](https://github.com/dougyouch/client-api-builder/actions/workflows/ci.yml/badge.svg)](https://github.com/dougyouch/client-api-builder/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/dougyouch/client-api-builder/branch/master/graph/badge.svg)](https://codecov.io/gh/dougyouch/client-api-builder)

A Ruby gem for building robust, secure API clients through declarative configuration. Define your API endpoints and their behavior with minimal boilerplate while benefiting from built-in security features, automatic retries, and comprehensive error handling.

## Features

- **Declarative Configuration** - Define API endpoints with a clean DSL
- **Security by Default** - SSL/TLS verification, path traversal protection, SSRF prevention
- **Automatic HTTP Method Detection** - Intelligently determines HTTP methods from route names
- **Flexible Request Building** - Support for JSON, query params, and custom body builders
- **Nested Routing** - Organize complex APIs with hierarchical route structures
- **Retry Logic** - Configurable automatic retries for transient network failures
- **Streaming Support** - Handle large payloads efficiently with streaming to files or IO
- **ActiveSupport Integration** - Optional logging and instrumentation
- **Comprehensive Error Handling** - Detailed error information for debugging

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'client-api-builder'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself:

```bash
$ gem install client-api-builder
```

## Quick Start

```ruby
class GitHubClient
  include ClientApiBuilder::Router

  base_url 'https://api.github.com'

  header 'Accept', 'application/vnd.github.v3+json'
  header 'User-Agent', 'MyApp/1.0'

  # Authentication header from instance method
  header 'Authorization' do
    "Bearer #{access_token}"
  end

  attr_accessor :access_token

  # GET /users/:username
  route :get_user, '/users/:username'

  # GET /users/:username/repos
  route :get_repos, '/users/:username/repos', query: { per_page: :per_page }

  # POST /user/repos
  route :create_repo, '/user/repos', body: { name: :name, private: :private }
end

client = GitHubClient.new
client.access_token = 'ghp_xxxxxxxxxxxx'

# Fetch a user
user = client.get_user(username: 'octocat')

# List repositories with pagination
repos = client.get_repos(username: 'octocat', per_page: 10)

# Create a new repository
new_repo = client.create_repo(name: 'my-new-repo', private: true)
```

## Usage Guide

### Defining Routes

Routes are defined using the `route` class method:

```ruby
route :method_name, '/path/:param', options
```

**Options:**

| Option | Description |
|--------|-------------|
| `method:` | HTTP method (`:get`, `:post`, `:put`, `:patch`, `:delete`). Auto-detected if omitted. |
| `query:` | Hash defining query parameters. Use symbols for dynamic values. |
| `body:` | Hash defining request body. Use symbols for dynamic values. |
| `expected_response_code:` | Single expected HTTP status code |
| `expected_response_codes:` | Array of expected HTTP status codes |
| `stream:` | Enable streaming (`:file`, `:io`, `:block`, or `true`) |
| `return:` | Return type (`:response`, `:body`, or parsed JSON by default) |

### Automatic HTTP Method Detection

The Router automatically detects HTTP methods based on route names:

| Prefix | HTTP Method |
|--------|-------------|
| `get_`, `find_`, `fetch_`, `list_`, `search_` | GET |
| `post_`, `create_`, `add_`, `insert_` | POST |
| `put_`, `update_`, `modify_`, `change_` | PUT |
| `patch_` | PATCH |
| `delete_`, `remove_`, `destroy_` | DELETE |

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'

  # Automatically uses appropriate HTTP methods
  route :get_users, '/users'                    # GET
  route :create_user, '/users', body: { name: :name }  # POST
  route :update_user, '/users/:id', body: { name: :name }  # PUT
  route :patch_user, '/users/:id', body: { name: :name }   # PATCH
  route :delete_user, '/users/:id'              # DELETE
end
```

### Dynamic Parameters

Parameters can be defined in three ways:

**1. Path Parameters** (using `:param` or `{param}` syntax):

```ruby
route :get_user, '/users/:id'
route :get_post, '/users/{user_id}/posts/{post_id}'
```

**2. Query Parameters:**

```ruby
route :search_users, '/users', query: { q: :query, page: :page, limit: :limit }
# Generates: GET /users?q=...&page=...&limit=...
```

**3. Body Parameters:**

```ruby
route :create_user, '/users', body: { user: { name: :name, email: :email } }
# Sends JSON: {"user": {"name": "...", "email": "..."}}
```

### Headers

Define headers at the class level or dynamically:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'

  # Static header
  header 'Content-Type', 'application/json'

  # Dynamic header from instance method
  header 'Authorization', :auth_header

  # Dynamic header from block
  header 'X-Request-ID' do
    SecureRandom.uuid
  end

  attr_accessor :api_key

  def auth_header
    "Bearer #{api_key}"
  end
end
```

### Request Body Formats

Configure how request bodies are serialized:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  # Default: JSON (using to_json)
  body_builder :to_json

  # URL-encoded form data (using to_query)
  body_builder :to_query

  # Custom query params builder (no ActiveSupport dependency)
  body_builder :query_params

  # Custom builder method
  body_builder :my_custom_builder

  # Custom builder with block
  body_builder do |data|
    data.to_xml
  end

  def my_custom_builder(data)
    # Custom serialization logic
  end
end
```

### Nested Routing (Sections)

Organize complex APIs with nested routes:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'
  header 'Authorization', :auth_token

  attr_accessor :auth_token

  section :users do
    base_url 'https://api.example.com/v2'  # Override base URL

    route :list, '/users'
    route :get, '/users/:id'
    route :create, '/users', body: { name: :name, email: :email }
  end

  section :posts do
    route :list, '/posts'
    route :get, '/posts/:id'
  end
end

client = MyApiClient.new
client.auth_token = 'secret'

# Access nested routes
users = client.users.list
user = client.users.get(id: 123)
posts = client.posts.list
```

### Connection Options

Configure connection settings:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'

  # Set timeouts
  connection_option :open_timeout, 10
  connection_option :read_timeout, 30

  # SSL options (verify_mode is enabled by default)
  connection_option :ssl_timeout, 10
end
```

### Retry Configuration

Configure automatic retries for transient failures:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'

  # Retry up to 3 times with 0.5 second delay between attempts
  configure_retries 3, 0.5
end
```

By default, retries are performed only for network-related errors:
- `Net::OpenTimeout`, `Net::ReadTimeout`
- `Errno::ECONNRESET`, `Errno::ECONNREFUSED`, `Errno::ETIMEDOUT`
- `SocketError`, `EOFError`

Customize retry behavior by overriding `retry_request?`:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  def retry_request?(exception, options)
    case exception
    when Net::OpenTimeout, Net::ReadTimeout
      true
    when ClientApiBuilder::UnexpectedResponse
      # Retry on 503 Service Unavailable
      exception.response.code == '503'
    else
      false
    end
  end
end
```

### Streaming Support

Handle large responses efficiently:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'

  # Stream directly to a file
  route :download_file, '/files/:id/download', stream: :file

  # Stream to an IO object
  route :stream_to_io, '/files/:id/stream', stream: :io

  # Stream with block processing
  route :process_stream, '/events/stream', stream: :block
end

client = MyApiClient.new

# Download to file
client.download_file(id: 123, file: '/path/to/output.zip')

# Stream to IO
File.open('/path/to/output.dat', 'wb') do |file|
  client.stream_to_io(id: 123, io: file)
end

# Process stream in chunks
client.process_stream do |response, chunk|
  puts "Received #{chunk.bytesize} bytes"
  process_data(chunk)
end
```

### Response Handling

Customize how responses are processed:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'

  # Return parsed JSON (default)
  route :get_user, '/users/:id'

  # Return raw response body
  route :get_raw, '/raw/:id', return: :body

  # Return Net::HTTPResponse object
  route :get_response, '/data/:id', return: :response

  # Custom response handling with block
  route :get_token, '/auth/token' do |data|
    self.auth_token = data['access_token']
    data
  end
end
```

### Error Handling

The gem provides detailed error information:

```ruby
begin
  client.get_user(id: 999)
rescue ClientApiBuilder::UnexpectedResponse => e
  puts "HTTP Status: #{e.response.code}"
  puts "Response Body: #{e.response.body}"
  puts "Error Message: #{e.message}"
end
```

### Debugging

Access request and response details after each call:

```ruby
client = MyApiClient.new
client.get_user(id: 123)

# Response information
puts client.response.code        # HTTP status code
puts client.response.body        # Response body
puts client.response.to_hash     # Response headers

# Request information
puts client.request_options[:method]  # HTTP method used
puts client.request_options[:uri]     # Full URI
puts client.request_options[:body]    # Request body
puts client.request_options[:headers] # Request headers

# Performance metrics
puts client.total_request_time   # Time in seconds
puts client.request_attempts     # Number of attempts (including retries)
```

### ActiveSupport Integration

When ActiveSupport is available, the gem provides instrumentation and logging:

```ruby
# Set up logging
ClientApiBuilder.logger = Logger.new(STDOUT)

# Subscribe to request events
ActiveSupport::Notifications.subscribe('client_api_builder.request') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  client = event.payload[:client]

  puts "#{client.request_options[:method]} #{client.request_options[:uri]}"
  puts "Status: #{client.response&.code}"
  puts "Duration: #{event.duration.round(2)}ms"
end

# Or use the built-in log subscriber
subscriber = ClientApiBuilder::ActiveSupportLogSubscriber.new(Rails.logger)
subscriber.subscribe!
```

## Security Features

Client API Builder includes several security features enabled by default:

### SSL/TLS Verification

All HTTPS connections verify SSL certificates by default using `OpenSSL::SSL::VERIFY_PEER`. Default timeouts are also configured to prevent hanging connections.

### SSRF Protection

Base URLs are validated to only allow `http` and `https` schemes, preventing Server-Side Request Forgery attacks:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'  # Valid
  base_url 'http://api.example.com'   # Valid
  base_url 'file:///etc/passwd'       # Raises ArgumentError
  base_url 'ftp://example.com'        # Raises ArgumentError
end
```

### Path Traversal Protection

File streaming operations validate paths to prevent directory traversal attacks:

```ruby
# These will raise ArgumentError
client.download_file(id: 1, file: '/tmp/../etc/passwd')
client.download_file(id: 1, file: "/tmp/file\0.txt")
```

### Safe File Modes

Only safe file modes are allowed for streaming to files: `w`, `wb`, `a`, `ab`, `w+`, `wb+`, `a+`, `ab+`.

## Thread Safety

Client instances are **not thread-safe**. Create a separate client instance per thread:

```ruby
# Correct: Create a new client for each thread
threads = 5.times.map do |i|
  Thread.new do
    client = MyApiClient.new
    client.get_user(id: i)
  end
end
threads.each(&:join)

# Incorrect: Do not share clients across threads
client = MyApiClient.new
threads = 5.times.map do |i|
  Thread.new do
    client.get_user(id: i)  # Race condition!
  end
end
```

## Configuration Reference

### Class-Level Methods

| Method | Description |
|--------|-------------|
| `base_url(url)` | Set the base URL for all requests |
| `header(name, value)` | Add a header to all requests |
| `body_builder(builder)` | Configure request body serialization |
| `query_builder(builder)` | Configure query string serialization |
| `query_param(name, value)` | Add a query parameter to all requests |
| `connection_option(name, value)` | Set Net::HTTP connection options |
| `configure_retries(max, sleep)` | Configure retry behavior |
| `route(name, path, options)` | Define an API endpoint |
| `section(name, options, &block)` | Define nested routes |
| `namespace(path, &block)` | Add path prefix to routes in block |

### Instance Methods

| Method | Description |
|--------|-------------|
| `response` | Last Net::HTTPResponse object |
| `request_options` | Options used for last request |
| `total_request_time` | Duration of last request in seconds |
| `request_attempts` | Number of attempts for last request |
| `root_router` | Returns the root router (for nested routers) |

## Requirements

- Ruby 3.0+
- `inheritance-helper` gem (>= 0.2.5)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dougyouch/client-api-builder.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Ensure code style compliance (`bundle exec rubocop`)
6. Commit your changes (`git commit -am 'Add my feature'`)
7. Push to the branch (`git push origin feature/my-feature`)
8. Create a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
