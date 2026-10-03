# Client API Builder

[![Gem Version](https://img.shields.io/gem/v/client-api-builder)](https://rubygems.org/gems/client-api-builder)
[![CI](https://github.com/dougyouch/client-api-builder/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/dougyouch/client-api-builder/actions/workflows/ci.yml)
[![Coverage](https://raw.githubusercontent.com/dougyouch/client-api-builder/badges/coverage.svg)](https://github.com/dougyouch/client-api-builder/actions/workflows/ci.yml)
[![Branch Coverage](https://raw.githubusercontent.com/dougyouch/client-api-builder/badges/branches.svg)](https://github.com/dougyouch/client-api-builder/actions/workflows/ci.yml)

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
| `method:` | HTTP method. Auto-detected from the route name if omitted. Any of `:get`, `:post`, `:put`, `:patch`, `:delete`, `:head`, `:options`, `:trace`, `:copy`, `:lock`, `:unlock`, `:mkcol`, `:move`, `:propfind`, `:proppatch`. |
| `query:` | Hash defining query parameters. Use symbols for dynamic values. |
| `body:` | Request body: a Hash or Array (symbols become arguments) or a literal String. |
| `no_body:` | `true` to send no body, even for POST/PUT/PATCH. |
| `has_body:` | `true` to add a `body:` argument to any method, e.g. a GET with a body. |
| `expected_response_code:` | Single expected HTTP status code. Without one, any 2xx response is accepted. |
| `expected_response_codes:` | Array of expected HTTP status codes |
| `stream:` | Enable streaming (`:file`, `:io`, `:block`, or `true`) |
| `return:` | Return type (`:response`, `:body`, or parsed JSON by default) |

POST, PUT and PATCH routes without a `body:` option take the request body as a `body:` argument:

```ruby
route :create_user, '/users'

client.create_user(body: { name: 'Ann' })
```

### Per-Request Options

Every generated method also accepts options that apply to that call only:

```ruby
client.get_user(
  id: 1,
  headers: { 'X-Trace-Id' => 'abc' },   # merged over the class headers; nil removes one
  query: { expand: 'teams' },           # merged over the route's query params
  body: { name: 'Ann' },                # replaces the route's body
  connection_options: { read_timeout: 5 },
  retries: 3,                           # attempts for this call
  sleep: 0.5,                           # seconds between attempts
  return: :body                         # :body or :response instead of parsed JSON
)
```

### Automatic HTTP Method Detection

The Router detects the HTTP method from how the route name starts:

| Name starts with | HTTP Method |
|------------------|-------------|
| `post`, `create`, `add`, `insert` | POST |
| `put`, `update`, `modify`, `change` | PUT |
| `patch` | PATCH |
| `delete`, `remove`, `destroy` | DELETE |
| anything else | GET |

The match is on the start of the name only, so `address_lookup` is a POST. Pass `method:` when the name doesn't say it.

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

**1. Path Parameters** (using `:param` syntax):

```ruby
route :get_user, '/users/:id'
# client.get_user(id: 1)
```

`{name}` is filled from the client's own `name` method rather than an argument, which suits values like account IDs that are set once:

```ruby
attr_accessor :account_id

route :get_invoices, '/accounts/{account_id}/invoices'
# client.get_invoices
```

The same `'{name}'` form works as a value inside `query:` and `body:`.

Path values, from arguments and `{name}` alike, are percent-encoded so each stays a single segment: `get_file(name: 'a/b c')` requests `/files/a%2Fb%20c`. Only RFC 3986 unreserved characters (`A-Z a-z 0-9 - . _ ~`) are left as is. To change this, override `escape_path`:

```ruby
# Allow '/' in values, e.g. for nested object keys
def escape_path(value)
  value.to_s.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')
end
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

A symbol or block given to `header` or `query_param` is evaluated on the client for every request. Values passed when calling a route, including per-request `headers:` and `query:`, are always sent as given, so `client.list_items(sort: :asc)` sends `sort=asc`. Header values are sent as strings; setting one to `nil` for a request leaves it out.

### Request Body Formats

Configure how request bodies are serialized:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  # Default: JSON (using to_json)
  body_builder :to_json

  # URL-encoded form data (using to_query, requires ActiveSupport)
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

String bodies are sent as is. Query strings are built the same way with `query_builder`, which accepts `:to_query`, `:query_params`, a method name or a block. It defaults to `:to_query` when ActiveSupport is loaded and to `:query_params` otherwise.

### Nested Routing (Sections)

Organize complex APIs with nested routes:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'
  header 'Authorization', :authorization

  attr_accessor :auth_token

  def authorization
    "Bearer #{auth_token}"
  end

  section :users do
    base_url 'https://api.example.com/v2'  # Override base URL
    header 'Authorization', :authorization

    route :list, '/users'
    route :get, '/users/:id'
    route :create, '/users', body: { name: :name, email: :email }
  end

  section :posts do
    header 'Authorization', :authorization

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

A section is its own router class. It uses the parent's `base_url` unless it sets one, but headers, query params, connection options, retries and builders are not inherited, so declare the ones it needs inside the section. Symbol and block values given to `header` and `query_param`, `{name}` path values, and response blocks are evaluated on the root client, so they can use its methods and state.

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

Any `Net::HTTP.start` option can be set this way. Your options are applied over the secure HTTPS defaults, so setting `verify_mode` yourself replaces `VERIFY_PEER`.

### Retry Configuration

Configure automatic retries for transient failures:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  base_url 'https://api.example.com'

  # Make up to 3 attempts in total, waiting 0.5 seconds between them
  configure_retries 3, 0.5
end
```

The first argument is the total number of attempts, not extra retries. The default is 1, so requests are not retried unless you configure it. `retries:` and `sleep:` can also be passed per request.

Only these network errors are retried by default:
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

Streaming routes return the `Net::HTTPResponse`. Files are written in `wb` mode by default; pass `connection_options: { file_mode: 'ab' }` to append.

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

# A block passed to the call replaces the route's block
client.get_user(id: 1) { |data| data['name'] }
```

Blocks run on the client, so they can call its methods and set its state. Empty response bodies return `nil`.

### Error Handling

`ClientApiBuilder::UnexpectedResponse` is raised when the status code isn't expected (any non-2xx by default, or anything outside `expected_response_code(s)`) and when a response body isn't valid JSON. It carries the response:

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

When ActiveSupport is loaded before your client class includes `ClientApiBuilder::Router`, every request is instrumented as a `client_api_builder.request` event:

```ruby
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

Separately, `ClientApiBuilder.logger` receives every exception raised during a request attempt, including ones that are retried:

```ruby
ClientApiBuilder.logger = Logger.new($stdout)
```

#### Production Logging

The built-in log subscriber already leaves out query strings, which may hold credentials. To customize the format, subscribe directly:

```ruby
ActiveSupport::Notifications.subscribe('client_api_builder.request') do |_, start_time, end_time, _, payload|
  client = payload[:client]
  method = client.request_options[:method].to_s.upcase
  uri = client.request_options[:uri]
  response_code = client.response ? client.response.code : 'UNKNOWN'

  duration = ((end_time - start_time) * 1000).to_i
  Rails.logger.info "#{method} #{uri.scheme}://#{uri.host}#{uri.path}[#{response_code}] took #{duration}ms"
end
```

This produces clean log entries like:
```
GET https://api.example.com/users/123[200] took 45ms
POST https://api.example.com/auth/token[201] took 120ms
```

## Security Features

Client API Builder includes several security features enabled by default:

### SSL/TLS Verification

HTTPS connections verify SSL certificates using `OpenSSL::SSL::VERIFY_PEER` and default to a 30 second open timeout and 60 second read timeout. Plain HTTP connections use Net::HTTP's own defaults.

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

### Path Value Encoding

Values inserted into a route's path are percent-encoded, so input such as `../admin` or `a/b?x=1` can't add path segments or a query string to the request.

### Path Traversal Protection

File streaming rejects any path containing `..` or a null byte:

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
| `header(name, value = nil, &block)` | Add a header to all requests (value, method name symbol, or block) |
| `body_builder(builder)` | Configure request body serialization |
| `query_builder(builder)` | Configure query string serialization |
| `query_param(name, value = nil, &block)` | Add a query parameter to all requests (value, method name symbol, or block) |
| `connection_option(name, value)` | Set Net::HTTP connection options |
| `configure_retries(max_attempts, sleep = 0.05)` | Configure retry behavior |
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
| `base_url` | Base URL used for requests |

### Overridable Hooks

Define these in your client to change default behavior:

| Method | Default |
|--------|---------|
| `retry_request?(exception, options)` | `true` for the network errors listed under Retry Configuration |
| `escape_path(value)` | Percent-encodes path values (`ERB::Util.url_encode`) |
| `parse_response(response, options)` | Parses the body as JSON, `nil` when empty |
| `handle_response(response, options, &block)` | Applies `return:`, parsing and the response block |
| `expected_response_code!(response, codes, options)` | Raises `UnexpectedResponse` for unexpected codes |
| `get_retry_request_max_retries(options)` | `retries:` option, then `configure_retries`, then 1 |
| `get_retry_request_sleep_time(exception, options)` | `sleep:` option, then `configure_retries`, then 0.05 |

## Requirements

- Ruby 3.2+
- `inheritance-helper` gem (>= 0.2.5)
- `activesupport` (optional) for `to_query` builders and instrumentation

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dougyouch/client-api-builder.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure all tests pass with full line and branch coverage (`CI=true bundle exec rspec`)
5. Ensure code style compliance (`bundle exec rubocop`)
6. Commit your changes using [conventional commits](https://www.conventionalcommits.org/) (`git commit -am 'feat(router): add my feature'`); release notes and version bumps are generated from them
7. Push to the branch (`git push origin feature/my-feature`)
8. Create a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
