# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::HTTP2::RequestHeaders do
  describe '.build' do
    it 'puts the pseudo-headers first, then the request headers' do
      request = Net::HTTP::Get.new('/items?page=2', 'X-Api-Key' => 'secret')

      expect(described_class.build(request, 'api.example.com')).to eq(
        [
          [':method', 'GET'],
          [':scheme', 'https'],
          [':authority', 'api.example.com'],
          [':path', '/items?page=2'],
          ['x-api-key', 'secret'],
          ['accept-encoding', 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3'],
          ['accept', '*/*'],
          ['user-agent', 'Ruby']
        ]
      )
    end

    it 'uses a Host header as the authority and drops connection-specific headers' do
      request = Net::HTTP::Get.new('/', 'Host' => 'other.example.com', 'Connection' => 'keep-alive',
                                        'Keep-Alive' => '30', 'Transfer-Encoding' => 'chunked', 'Upgrade' => 'h2c',
                                        'Proxy-Connection' => 'close', 'TE' => 'gzip', 'Accept' => 'text/plain',
                                        'Accept-Encoding' => 'identity', 'User-Agent' => 'spec')

      expect(described_class.build(request, 'api.example.com')).to eq(
        [
          [':method', 'GET'],
          [':scheme', 'https'],
          [':authority', 'other.example.com'],
          [':path', '/'],
          ['accept', 'text/plain'],
          ['accept-encoding', 'identity'],
          ['user-agent', 'spec']
        ]
      )
    end

    it 'keeps te: trailers' do
      request = Net::HTTP::Get.new('/', 'TE' => 'trailers')

      expect(described_class.build(request, 'a.test')).to include(%w[te trailers])
    end

    it 'adds content-length for a body' do
      request = Net::HTTP::Post.new('/items', 'Content-Type' => 'application/json')
      request.body = '{"name":"é"}'

      expect(described_class.build(request, 'a.test')).to include(%w[content-length 13])
    end

    it 'keeps a content-length the request already has' do
      request = Net::HTTP::Post.new('/items', 'Content-Length' => '2')
      request.body = '{}'

      expect(described_class.build(request, 'a.test').count { |name, _| name == 'content-length' }).to eq(1)
    end
  end
end
