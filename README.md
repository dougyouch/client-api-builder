# client-api-builder

Utility for creating API clients through configuration

Example:

```
class LoremIpsumClient
  include ClientApiBuilder::Router

  # by default it converts the body data to JSON
  # to convert the body to query params (x=1&y=2) use the following
  # if using active support change this to :to_query
  body_builder :query_params

  base_url 'https://www.lipsum.com'

  header 'Content-Type', 'application/x-www-form-urlencoded'
  header 'Accept', 'application/json'

  # this creates a method called create_lorem_ipsum with 2 named arguments amont and what
  route :create_lorem_ipsum, '/feed/json', body: {amount: :amount, what: :what, start: 'yes', generate: 'Generate Lorem Ipsum'}
end
```

How to use:

```
client = LoremIpsumClient.new
payload = client.create_lorem_ipsum(amount: 10, what: 'words')
puts payload.dig('feed', 'lipsum')
# outputs: Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nam at.
```
