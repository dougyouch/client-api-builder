# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'stringio'
require 'tempfile'

describe ClientApiBuilder::Router do
  let(:router_class) do
    Class.new do
      include ClientApiBuilder::Router

      base_url 'http://example.com'
      configure_retries 1, 0

      route :get_items, '/items'
      route :create_raw, '/raw', body: 'raw payload'
      route :create_list, '/list', body: [:first, '{second}']
      route :create_settings, '/settings', body: { 'name' => :name, 1 => '{label}', enabled: true, disabled: false, extra: nil, tags: [], meta: {} }
      route :ping, '/ping', method: :post, no_body: true
      route :search, '/search', has_body: true
      route :get_text, '/text', return: :body
      route :get_text_response, '/text', return: :response
      route :download, '/file', stream: :file
      route :download_io, '/file', stream: :io
      route :download_chunks, '/file', stream: :block
      route :get_file, '/folders/{folder}/files/:name'

      def second
        'two'
      end

      def label
        'lbl'
      end

      def folder
        'my docs'
      end
    end
  end

  let(:router) { router_class.new }

  describe 'request bodies' do
    it 'sends a string body as is' do
      stub = stub_request(:post, 'http://example.com/raw').with(body: 'raw payload')

      router.create_raw
      expect(stub).to have_been_requested
    end

    it 'builds an array body from arguments and instance methods' do
      stub = stub_request(:post, 'http://example.com/list').with(body: '["one","two"]')

      router.create_list(first: 'one')
      expect(stub).to have_been_requested
    end

    it 'builds a hash body with string keys, other keys and literal values' do
      expected = { 'name' => 'bob', '1' => 'lbl', 'enabled' => true, 'disabled' => false, 'extra' => nil, 'tags' => [], 'meta' => {} }
      stub = stub_request(:post, 'http://example.com/settings').with(body: expected.to_json)

      router.create_settings(name: 'bob')
      expect(stub).to have_been_requested
    end

    it 'sends no body when no_body is set' do
      stub_request(:post, 'http://example.com/ping')

      router.ping
      expect(router.request_options[:body]).to be_nil
    end

    it 'accepts a body argument when has_body is set' do
      stub = stub_request(:get, 'http://example.com/search').with(body: '{"q":"term"}')

      router.search(body: { q: 'term' })
      expect(stub).to have_been_requested
    end

    it 'lets the request options override the body' do
      stub = stub_request(:post, 'http://example.com/raw').with(body: '{"a":1}')

      router.create_raw(body: { a: 1 })
      expect(stub).to have_been_requested
    end
  end

  describe 'path values' do
    before { stub_request(:get, %r{http://example.com/folders/}) }

    it 'URL-encodes arguments and instance values so each stays one segment' do
      router.get_file(name: '../a/b?c#d*é')
      expect(router.request_options[:uri].path).to eq('/folders/my%20docs/files/..%2Fa%2Fb%3Fc%23d%2A%C3%A9')
    end

    it 'leaves unreserved characters as is' do
      router.get_file(name: 'Report-2024_v1.~pdf')
      expect(router.request_options[:uri].path).to eq('/folders/my%20docs/files/Report-2024_v1.~pdf')
    end

    it 'accepts non-string values' do
      router.get_file(name: 42)
      expect(router.request_options[:uri].path).to eq('/folders/my%20docs/files/42')
    end

    it 'uses an overridden escape_path' do
      router.define_singleton_method(:escape_path) { |value| value.to_s.tr(' ', '-') }
      router.get_file(name: 'a/b')
      expect(router.request_options[:uri].path).to eq('/folders/my-docs/files/a/b')
    end
  end

  describe 'placeholders in query and body strings' do
    let(:router_class) do
      Class.new do
        include ClientApiBuilder::Router

        base_url 'http://example.com'

        route :search, '/search', query: { q: 'user:{user_id} state:{state}' }
        route :create_doc, '/docs', body: { title: 'Report for {user_id}', count: '{count}', tags: ['{state}', 'v{count}'] }
        route :create_note, '/notes', body: { text: %q(say "hi" \ #{ x } for {user_id}) }
        route :get_user_items, '/users/:user_id/items', query: { owner: '{user_id}' }

        def user_id
          42
        end

        def state
          'open'
        end

        def count
          3
        end
      end
    end

    before { stub_request(:any, /example.com/) }

    it 'fills in every placeholder and keeps the surrounding text' do
      router.search
      expect(URI.decode_www_form(router.request_options[:uri].query).to_h).to eq('q' => 'user:42 state:open')
    end

    it 'keeps the value type for a whole-string placeholder and interpolates text, including in arrays' do
      router.create_doc
      expect(JSON.parse(router.request_options[:body])).to eq('title' => 'Report for 42', 'count' => 3, 'tags' => %w[open v3])
    end

    it 'sends quotes, backslashes and interpolation syntax in the text literally' do
      router.create_note
      expect(JSON.parse(router.request_options[:body])).to eq('text' => %q(say "hi" \ #{ x } for 42))
    end

    it 'prefers a route argument over the client method of the same name' do
      router.get_user_items(user_id: 7)
      expect(router.request_options[:uri].query).to eq('owner=7')
    end
  end

  describe 'state after a failed attempt' do
    it 'clears the previous response when a request times out' do
      stub_request(:get, 'http://example.com/items')
      stub_request(:get, 'http://example.com/text').to_timeout
      router.get_items

      expect { router.get_text }.to raise_error(Net::OpenTimeout)
      expect(router.response).to be_nil
      expect(router.request_options[:uri].path).to eq('/text')
    end

    it 'clears the request options when the request cannot be built' do
      stub_request(:get, 'http://example.com/items')
      router.get_items
      router_class.body_builder { |_| raise ArgumentError, 'bad body' }

      expect { router.search(body: { q: 1 }) }.to raise_error(ArgumentError, 'bad body')
      expect(router.request_options).to be_nil
      expect(router.response).to be_nil
    end

    it 'does not keep a response from an earlier attempt of the same call' do
      stub_request(:get, 'http://example.com/items').to_return(status: 503).then.to_timeout
      router.define_singleton_method(:retry_request?) { |_exception, _options| true }

      expect { router.get_items(retries: 2) }.to raise_error(Net::OpenTimeout)
      expect(router.request_attempts).to eq(2)
      expect(router.response).to be_nil
    end
  end

  describe 'literal colons in paths' do
    let(:router_class) do
      Class.new do
        include ClientApiBuilder::Router

        base_url 'http://example.com'

        route :batch_get_items, '/v1/items:batchGet', method: :post, body: { ids: :ids }
        route :cancel_operation, '/v1/{operation}:cancel', method: :post, no_body: true
        route :get_slot, '/slots/12:30'

        def operation
          'operations/op 1'
        end
      end
    end

    it 'sends a custom method suffix as is' do
      stub = stub_request(:post, 'http://example.com/v1/items:batchGet').with(body: '{"ids":[1,2]}')

      router.batch_get_items(ids: [1, 2])
      expect(stub).to have_been_requested
    end

    it 'keeps the suffix after an escaped placeholder' do
      stub = stub_request(:post, 'http://example.com/v1/operations%2Fop%201:cancel')

      router.cancel_operation
      expect(stub).to have_been_requested
    end

    it 'defines routes with numbers after a colon' do
      stub = stub_request(:get, 'http://example.com/slots/12:30')

      router.get_slot
      expect(stub).to have_been_requested
    end
  end

  describe 'routes sharing a query hash' do
    let(:router_class) do
      shared = { app_id: :app_id }.freeze

      Class.new do
        include ClientApiBuilder::Router

        base_url 'http://example.com'

        route :get_a, '/a', query: shared
        route :get_b, '/b', query: shared
      end
    end

    it 'sends the argument from every route' do
      stub_a = stub_request(:get, 'http://example.com/a?app_id=1')
      stub_b = stub_request(:get, 'http://example.com/b?app_id=2')

      router.get_a(app_id: 1)
      router.get_b(app_id: 2)
      expect([stub_a, stub_b]).to all(have_been_requested)
    end
  end

  describe 'symbol values' do
    let(:router_class) do
      Class.new do
        include ClientApiBuilder::Router

        base_url 'http://example.com'
        header 'X-Key', :api_key
        query_param :key, :api_key

        route :list_items, '/items', query: { sort: :sort }

        def api_key
          'k1'
        end
      end
    end

    before { stub_request(:get, %r{http://example.com/items}) }

    it 'sends route arguments as values, not method names' do
      router.list_items(sort: :api_key)
      expect(URI.decode_www_form(router.request_options[:uri].query).to_h).to eq('key' => 'k1', 'sort' => 'api_key')
    end

    it 'sends per-request query and header values as given' do
      router.list_items(sort: :asc, query: { order: :desc }, headers: { 'X-Mode' => :fast })
      expect(URI.decode_www_form(router.request_options[:uri].query).to_h).to eq('key' => 'k1', 'sort' => 'asc', 'order' => 'desc')
      expect(router.request_options[:headers]).to eq('X-Key' => 'k1', 'X-Mode' => 'fast')
    end

    it 'drops a class-level header when the request sets it to nil' do
      stub = stub_request(:get, 'http://example.com/items?key=k1&sort=asc').with { |request| !request.headers.key?('X-Key') }

      router.list_items(sort: 'asc', headers: { 'X-Key' => nil })
      expect(stub).to have_been_requested
    end
  end

  describe 'request options' do
    it 'adds query params from the request options' do
      stub = stub_request(:get, 'http://example.com/items?page=2')

      router.get_items(query: { page: 2 })
      expect(stub).to have_been_requested
    end

    it 'merges connection options from the request options' do
      stub_request(:get, 'http://example.com/items')

      router.get_items(connection_options: { read_timeout: 5 })
      expect(router.request_options[:connection_options]).to eq(read_timeout: 5)
    end
  end

  describe 'responses' do
    before { stub_request(:get, %r{http://example.com/(items|text)}).to_return(body: 'hello') }

    it 'returns the body for return: :body routes' do
      expect(router.get_text).to eq('hello')
    end

    it 'returns the response for return: :response routes' do
      expect(router.get_text_response).to be_a(Net::HTTPOK)
    end

    it 'returns the body when the request options ask for it' do
      expect(router.get_items(return: :body)).to eq('hello')
    end

    it 'returns the response when the request options ask for it' do
      expect(router.get_items(return: :response).body).to eq('hello')
    end

    it 'raises on an unexpected response code' do
      stub_request(:get, 'http://example.com/items').to_return(status: 500)

      expect { router.get_items }.to raise_error(ClientApiBuilder::UnexpectedResponse, 'unexpected response code 500')
    end
  end

  describe 'streaming' do
    before { stub_request(:get, 'http://example.com/file').to_return(body: 'file contents') }

    it 'streams to a file' do
      Tempfile.create('download') do |file|
        router.download(file: file.path)
        expect(File.read(file.path)).to eq('file contents')
      end
    end

    it 'streams to an IO' do
      io = StringIO.new
      router.download_io(io: io)
      expect(io.string).to eq('file contents')
    end

    it 'streams chunks to the block' do
      chunks = []
      response = router.download_chunks { |_response, chunk| chunks << chunk }

      expect(chunks.join).to eq('file contents')
      expect(response).to be_a(Net::HTTPOK)
    end
  end

  describe 'streaming an error response' do
    let(:router_class) do
      Class.new do
        include ClientApiBuilder::Router

        base_url 'http://example.com'

        route :download, '/file', stream: :file
        route :download_io, '/file', stream: :io
        route :download_chunks, '/file', stream: :block
        route :download_partial, '/file', stream: :io, expected_response_code: 206
      end
    end

    before { stub_request(:get, 'http://example.com/file').to_return(status: 404, body: 'not found page') }

    it 'keeps an existing file and puts the error body on the exception' do
      Tempfile.create('download') do |file|
        File.write(file.path, 'existing contents')

        expect { router.download(file: file.path) }.to raise_error(ClientApiBuilder::UnexpectedResponse) do |error|
          expect(error.response.body).to eq('not found page')
        end
        expect(File.read(file.path)).to eq('existing contents')
      end
    end

    it 'writes nothing to the IO' do
      io = StringIO.new
      expect { router.download_io(io: io) }.to raise_error(ClientApiBuilder::UnexpectedResponse)
      expect(io.string).to eq('')
    end

    it 'yields nothing to the block' do
      chunks = []
      expect { router.download_chunks { |_, chunk| chunks << chunk } }.to raise_error(ClientApiBuilder::UnexpectedResponse)
      expect(chunks).to be_empty
    end

    it 'uses the route\'s expected response codes' do
      stub_request(:get, 'http://example.com/file').to_return(status: 200, body: 'whole file')
      io = StringIO.new

      expect { router.download_partial(io: io) }.to raise_error(ClientApiBuilder::UnexpectedResponse, /200/)
      expect(io.string).to eq('')
    end
  end

  describe 'retries' do
    it 'retries network errors and succeeds' do
      stub_request(:get, 'http://example.com/items').to_timeout.then.to_return(body: '{"ok":true}')

      expect(router.get_items(retries: 2)).to eq('ok' => true)
      expect(router.request_attempts).to eq(2)
    end

    it 'sleeps between retries' do
      stub_request(:get, 'http://example.com/items').to_timeout.then.to_return(body: '{}')
      allow(router).to receive(:sleep)

      router.get_items(retries: 2, sleep: 0.25)
      expect(router).to have_received(:sleep).with(0.25)
    end

    it 'skips sleeping when no sleep time is configured' do
      stub_request(:get, 'http://example.com/items').to_timeout.then.to_return(body: '{}')
      allow(router).to receive(:get_retry_request_sleep_time).and_return(nil)
      allow(router).to receive(:sleep)

      router.get_items(retries: 2)
      expect(router).not_to have_received(:sleep)
    end

    it 'raises once the retries are exhausted' do
      stub_request(:get, 'http://example.com/items').to_timeout

      expect { router.get_items(retries: 2) }.to raise_error(Net::OpenTimeout)
      expect(router.request_attempts).to eq(2)
    end

    it 'does not retry application errors' do
      stub_request(:get, 'http://example.com/items').to_return(status: 500)

      expect { router.get_items(retries: 3) }.to raise_error(ClientApiBuilder::UnexpectedResponse)
      expect(router.request_attempts).to eq(1)
    end

    context 'with a logger' do
      let(:log_output) { StringIO.new }

      around do |example|
        ClientApiBuilder.logger = Logger.new(log_output)
        example.run
      ensure
        ClientApiBuilder.logger = nil
      end

      it 'logs request exceptions' do
        stub_request(:get, 'http://example.com/items').to_timeout

        expect { router.get_items }.to raise_error(Net::OpenTimeout)
        expect(log_output.string).to include('execution expired')
      end
    end
  end

  describe '#instrument_request' do
    it 'times the request without ActiveSupport' do
      result = described_class.instance_method(:instrument_request).bind_call(router) { :done }

      expect(result).to eq(:done)
      expect(router.total_request_time).to be_a(Float)
    end
  end
end
