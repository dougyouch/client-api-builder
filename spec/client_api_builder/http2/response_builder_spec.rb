# frozen_string_literal: true

require 'spec_helper'
require 'zlib'

describe ClientApiBuilder::HTTP2::ResponseBuilder do
  let(:exchange) do
    body = chunks
    Class.new do
      define_method(:each_chunk) { |&block| body.each(&block) }
    end.new
  end
  let(:chunks) { ['{"ok":true}'] }
  let(:request) { Net::HTTP::Get.new('/') }

  def build(headers)
    described_class.build(headers, exchange, request)
  end

  it 'builds the Net::HTTPResponse subclass for the status with its headers' do
    response = build([[':status', '201'], %w[content-type application/json], %w[set-cookie a=1], %w[set-cookie b=2]])

    expect(response).to be_a(Net::HTTPCreated)
    expect(response.http_version).to eq('2.0')
    expect(response.code).to eq('201')
    expect(response.message).to eq('')
    expect(response['content-type']).to eq('application/json')
    expect(response.get_fields('set-cookie')).to eq(%w[a=1 b=2])
    expect(response.body).to eq('{"ok":true}')
  end

  it 'falls back to the status class, then Net::HTTPUnknownResponse' do
    expect(build([[':status', '299']])).to be_a(Net::HTTPSuccess)
    expect(build([[':status', '799']])).to be_a(Net::HTTPUnknownResponse)
  end

  it 'leaves the body nil for a response that has none' do
    expect(build([[':status', '204']]).body).to be_nil
  end

  it 'leaves the body nil for a HEAD request' do
    request = Net::HTTP::Head.new('/')

    expect(described_class.build([[':status', '200']], exchange, request).body).to be_nil
  end

  context 'with a gzip body' do
    let(:chunks) { [Zlib.gzip('{"ok":true}')] }
    let(:headers) { [[':status', '200'], %w[content-encoding gzip], %w[content-length 31]] }

    it 'inflates it when Net::HTTP chose accept-encoding' do
      response = build(headers)

      expect(response.body).to eq('{"ok":true}')
      expect(response['content-encoding']).to be_nil
      expect(response['content-length']).to be_nil
    end

    it 'leaves it compressed when the caller set accept-encoding' do
      request = Net::HTTP::Get.new('/', 'Accept-Encoding' => 'gzip')
      response = described_class.build(headers, exchange, request)

      expect(response.body).to eq(chunks.first)
      expect(response['content-encoding']).to eq('gzip')
    end
  end

  it 'leaves an encoding it cannot inflate alone' do
    response = build([[':status', '200'], %w[content-encoding br]])

    expect(response['content-encoding']).to eq('br')
  end
end
