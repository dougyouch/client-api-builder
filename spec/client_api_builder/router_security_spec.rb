# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::Router, 'security features' do
  let(:router_class) do
    Class.new do
      include ClientApiBuilder::Router

      base_url 'http://example.com'
      header 'Content-Type', 'application/json'
    end
  end

  let(:router) { router_class.new }

  describe '.deep_dup_hash' do
    it 'creates a deep copy of nested hashes' do
      original = { a: { b: { c: 1 } } }
      copy = router_class.deep_dup_hash(original)

      copy[:a][:b][:c] = 2

      expect(original[:a][:b][:c]).to eq(1)
      expect(copy[:a][:b][:c]).to eq(2)
    end

    it 'creates a deep copy of arrays containing hashes' do
      original = { items: [{ id: 1 }, { id: 2 }] }
      copy = router_class.deep_dup_hash(original)

      copy[:items][0][:id] = 999

      expect(original[:items][0][:id]).to eq(1)
      expect(copy[:items][0][:id]).to eq(999)
    end

    it 'preserves non-hash, non-array values' do
      original = { name: 'test', count: 5, active: true }
      copy = router_class.deep_dup_hash(original)

      expect(copy).to eq(original)
    end
  end

  describe '.validate_base_url!' do
    it 'accepts http URLs' do
      expect { router_class.validate_base_url!('http://example.com') }.not_to raise_error
    end

    it 'accepts https URLs' do
      expect { router_class.validate_base_url!('https://example.com') }.not_to raise_error
    end

    it 'rejects file URLs' do
      expect { router_class.validate_base_url!('file:///etc/passwd') }
        .to raise_error(ArgumentError, /Invalid base_url scheme/)
    end

    it 'rejects ftp URLs' do
      expect { router_class.validate_base_url!('ftp://example.com') }
        .to raise_error(ArgumentError, /Invalid base_url scheme/)
    end

    it 'rejects URLs without scheme' do
      expect { router_class.validate_base_url!('example.com') }
        .to raise_error(ArgumentError, /Invalid base_url scheme/)
    end

    it 'rejects invalid URIs' do
      expect { router_class.validate_base_url!('http://[invalid') }
        .to raise_error(ArgumentError, /Invalid base_url/)
    end
  end

  describe '.base_url with validation' do
    it 'sets valid http base_url' do
      test_class = Class.new do
        include ClientApiBuilder::Router
      end

      test_class.base_url 'http://api.example.com'
      expect(test_class.base_url).to eq('http://api.example.com')
    end

    it 'raises error for invalid scheme' do
      test_class = Class.new do
        include ClientApiBuilder::Router
      end

      expect { test_class.base_url 'ftp://example.com' }
        .to raise_error(ArgumentError, /Invalid base_url scheme/)
    end
  end

  describe '.generate_route_code method name validation' do
    it 'accepts valid method names' do
      expect { router_class.generate_route_code(:get_user, '/users/:id') }.not_to raise_error
      expect { router_class.generate_route_code(:create_user, '/users') }.not_to raise_error
      expect { router_class.generate_route_code(:_private_method, '/private') }.not_to raise_error
    end

    it 'rejects method names with special characters' do
      expect { router_class.generate_route_code(:'get-user', '/users/:id') }
        .to raise_error(ArgumentError, /Invalid method name/)
    end

    it 'rejects method names starting with numbers' do
      expect { router_class.generate_route_code(:'123method', '/users') }
        .to raise_error(ArgumentError, /Invalid method name/)
    end

    it 'rejects method names with injection attempts' do
      expect { router_class.generate_route_code(:"method; system('rm -rf /')", '/users') }
        .to raise_error(ArgumentError, /Invalid method name/)
    end
  end

  describe '#retry_request?' do
    it 'returns true for network timeout errors' do
      expect(router.retry_request?(Net::OpenTimeout.new, {})).to be true
      expect(router.retry_request?(Net::ReadTimeout.new, {})).to be true
    end

    it 'returns true for connection errors' do
      expect(router.retry_request?(Errno::ECONNRESET.new, {})).to be true
      expect(router.retry_request?(Errno::ECONNREFUSED.new, {})).to be true
      expect(router.retry_request?(Errno::ETIMEDOUT.new, {})).to be true
    end

    it 'returns true for socket errors' do
      expect(router.retry_request?(SocketError.new, {})).to be true
      expect(router.retry_request?(EOFError.new, {})).to be true
    end

    it 'returns false for standard errors' do
      expect(router.retry_request?(StandardError.new, {})).to be false
      expect(router.retry_request?(RuntimeError.new, {})).to be false
    end

    it 'returns false for application errors' do
      expect(router.retry_request?(ArgumentError.new, {})).to be false
      expect(router.retry_request?(JSON::ParserError.new, {})).to be false
    end
  end

  describe '#parse_response' do
    let(:response) { instance_double(Net::HTTPResponse) }

    context 'with valid JSON' do
      it 'parses the response body' do
        allow(response).to receive(:body).and_return('{"key": "value"}')
        result = router.parse_response(response, {})
        expect(result).to eq({ 'key' => 'value' })
      end
    end

    context 'with nil body' do
      it 'returns nil' do
        allow(response).to receive(:body).and_return(nil)
        result = router.parse_response(response, {})
        expect(result).to be_nil
      end
    end

    context 'with empty body' do
      it 'returns nil' do
        allow(response).to receive(:body).and_return('')
        result = router.parse_response(response, {})
        expect(result).to be_nil
      end
    end

    context 'with invalid JSON' do
      it 'raises UnexpectedResponse with helpful message' do
        allow(response).to receive(:body).and_return('not valid json')
        expect { router.parse_response(response, {}) }
          .to raise_error(ClientApiBuilder::UnexpectedResponse, /Invalid JSON in response/)
      end
    end
  end

  describe '#request_log_message' do
    context 'with nil request_options' do
      it 'returns empty string' do
        expect(router.request_log_message).to eq('')
      end
    end

    context 'with request_options but no URI' do
      before do
        router.instance_variable_set(:@request_options, { method: :get, uri: nil })
      end

      it 'returns partial message' do
        expect(router.request_log_message).to eq('GET [no URI]')
      end
    end

    context 'with full request_options' do
      let(:uri) { URI('http://example.com/users') }
      let(:response) { instance_double(Net::HTTPResponse, code: '200') }

      before do
        router.instance_variable_set(:@request_options, { method: :get, uri: uri })
        router.instance_variable_set(:@response, response)
        router.instance_variable_set(:@total_request_time, 0.123)
      end

      it 'returns full log message' do
        message = router.request_log_message
        expect(message).to include('GET')
        expect(message).to include('http://example.com/users')
        expect(message).to include('[200]')
        expect(message).to include('123ms')
      end
    end

    context 'with nil total_request_time' do
      let(:uri) { URI('http://example.com/users') }

      before do
        router.instance_variable_set(:@request_options, { method: :get, uri: uri })
        router.instance_variable_set(:@total_request_time, nil)
      end

      it 'uses 0 for duration' do
        message = router.request_log_message
        expect(message).to include('0ms')
      end
    end
  end

  describe '#build_uri' do
    context 'URL joining' do
      it 'handles base_url without trailing slash' do
        uri = router.build_uri('/users', nil, {})
        expect(uri.to_s).to eq('http://example.com/users')
      end

      it 'handles path without leading slash' do
        uri = router.build_uri('users', nil, {})
        expect(uri.to_s).to eq('http://example.com/users')
      end

      it 'handles base_url with trailing slash' do
        test_class = Class.new do
          include ClientApiBuilder::Router

          base_url 'http://example.com/'
        end
        test_router = test_class.new

        uri = test_router.build_uri('/users', nil, {})
        expect(uri.to_s).to eq('http://example.com/users')
      end
    end
  end
end
