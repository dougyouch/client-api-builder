# Client API Builder

A Ruby gem that provides a simple and elegant way to create API clients through configuration. It allows you to define API endpoints and their behavior declaratively, making it easy to create and maintain API clients.

## Features

- Declarative API client configuration
- Support for different request body formats (JSON, query params)
- Customizable headers
- Nested routing support
- ActiveSupport integration for logging and notifications
- Error handling with detailed response information
- Flexible parameter handling
- Automatic HTTP method detection based on method names
- Streaming support for handling large payloads
- Built-in debugging capabilities

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'client-api-builder'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install client-api-builder
```

## Usage

### Basic Usage

Create an API client by including the `ClientApiBuilder::Router` module and defining your endpoints:

```ruby
class MyApiClient
  include ClientApiBuilder::Router

  # Set the base URL for all requests
  base_url 'https://api.example.com'

  # Set default headers
  header 'Content-Type', 'application/json'
  header 'Accept', 'application/json'

  # Define an endpoint
  route :get_user, '/users/:id', method: :get, expected_response_code: 200
  route :create_user, '/users', method: :post, expected_response_code: 201, body: { name: :name, email: :email }
end

# Use the client
client = MyApiClient.new
user = client.get_user(id: 123)
new_user = client.create_user(name: 'John', email: 'john@example.com')
```

### Automatic HTTP Method Detection

The Router automatically detects the HTTP method based on the method name if not explicitly specified. This makes your API client code more intuitive and reduces boilerplate. The detection rules are:

- Methods starting with `post`, `create`, `add`, or `insert` → `POST`
- Methods starting with `put`, `update`, `modify`, or `change` → `PUT`
- Methods starting with `patch` → `PATCH`
- Methods starting with `delete` or `remove` → `DELETE`
- All other methods → `GET`

Example:

```ruby
class MyApiClient
  include ClientApiBuilder::Router
  
  base_url 'https://api.example.com'
  
  # These will automatically use the appropriate HTTP methods
  route :get_users, '/users'  # Uses GET
  route :create_user, '/users', body: { name: :name }  # Uses POST
  route :update_user, '/users/:id', body: { name: :name }  # Uses PUT
  route :delete_user, '/users/:id'  # Uses DELETE
  
  # You can still explicitly specify the method if needed
  route :custom_action, '/custom', method: :post
end
```

### Request Body Formats

By default, the client converts the body data to JSON. To use query parameters instead:

```ruby
class MyApiClient
  include ClientApiBuilder::Router
  
  # Use query parameters for the body
  body_builder :query_params
  
  base_url 'https://api.example.com'
  
  route :search, '/search', body: { q: :query, page: :page }
end
```

### Nested Routing

For APIs with nested resources, you can use the `NestedRouter`:

```ruby
class MyApiClient
  include ClientApiBuilder::Router
  
  base_url 'https://api.example.com'
  
  section :users do
    route :list, '/', method: :get
    route :get, '/:id', method: :get
  end
end

client = MyApiClient.new
users = client.users.list
user = client.users.get(id: 123)
```

### Error Handling

The gem provides custom error classes for better error handling:

```ruby
begin
  client.get_user(id: 123)
rescue ClientApiBuilder::UnexpectedResponse => e
  puts "Request failed with status #{e.response.status}"
  puts "Response body: #{e.response.body}"
end
```

### ActiveSupport Integration

The gem integrates with ActiveSupport for logging and notifications:

```ruby
# Enable logging
ClientApiBuilder.logger = Logger.new(STDOUT)

# Subscribe to notifications
ActiveSupport::Notifications.subscribe('request.client_api_builder') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  puts "Request took #{event.duration}ms"
end
```

### Streaming Support

The library supports streaming responses, which is particularly useful for handling large payloads. You can stream responses directly to a file or process them in chunks:

```ruby
class MyApiClient
  include ClientApiBuilder::Router
  
  base_url 'https://api.example.com'
  
  # Stream response directly to a file
  route :download_users, '/users', stream: :file
  
  # Stream response in chunks for custom processing
  route :stream_users, '/users', stream: true
end

# Use the client
client = MyApiClient.new

# Stream to file
client.download_users('users.json')  # Saves response directly to users.json

# Stream with custom processing
client.stream_users do |chunk|
  # Process each chunk of the response
  puts "Received #{chunk.bytesize} bytes"
end
```

When using `stream: :file`, the response is written directly to disk as it's received, which is memory-efficient for large responses. The file path is passed as an argument to the method.

For custom streaming, you can provide a block that will be called with each chunk of the response as it's received. This allows for custom processing of large responses without loading the entire response into memory.

### Thread Safety

The library is not thread-safe. You must create a separate client instance per thread to avoid race conditions and ensure proper operation:

```ruby
# Correct: Create a new client for each thread
threads = []
5.times do |i|
  threads << Thread.new do
    client = MyApiClient.new
    client.get_user(id: i)
  end
end
threads.each(&:join)

# Incorrect: Do not share a single client across threads
client = MyApiClient.new
threads = []
5.times do |i|
  threads << Thread.new do
    client.get_user(id: i)  # This will cause race conditions
  end
end
threads.each(&:join)
```

Each client instance maintains its own state, including response objects and request options. Sharing a client across threads can lead to unpredictable behavior and race conditions.

### Debugging

The Router provides built-in debugging capabilities by maintaining the response object and request options for each request. This information can be accessed after making a request:

```ruby
client = MyApiClient.new
client.get_user(id: 123)

# Access the last response
response = client.response
puts "Status: #{response.status}"
puts "Headers: #{response.headers}"
puts "Body: #{response.body}"

# Access the request options used
request_options = client.request_options
puts "Method: #{request_options[:method]}"
puts "URL: #{request_options[:url]}"
puts "Headers: #{request_options[:headers]}"
puts "Body: #{request_options[:body]}"

# Access timing information
puts "Total request time: #{client.total_request_time} seconds"
puts "Number of attempts: #{client.request_attempts}"
```

This information is particularly useful for:
- Debugging failed requests
- Understanding request/response cycles
- Performance analysis
- Logging and monitoring

The response and request options are maintained until the next request is made, so you can inspect them immediately after a request completes.

## Configuration Options

- `base_url`: Set the base URL for all requests
- `header`: Add headers to all requests
- `body_builder`: Configure how request bodies are formatted
- `route`: Define API endpoints with their paths and parameters
- `nested_route`: Define nested resource routes

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dougyouch/client-api-builder.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
