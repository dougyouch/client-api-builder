# frozen_string_literal: true

require 'spec_helper'
require 'zlib'

describe ClientApiBuilder::HTTP2::ResponseBody do
  let(:chunks) { %w[hel lo] }
  let(:exchange) do
    source = chunks
    Class.new do
      define_method(:each_chunk) { |&block| source.each(&block) }
    end.new
  end
  let(:response) do
    Net::HTTPOK.new('2.0', '200', '').tap do |response|
      response.extend(described_class)
      response.http2_body(exchange, inflate: false, expected: true)
    end
  end

  it 'reads the body into a string' do
    expect(response.read_body).to eq('hello')
    expect(response.body).to eq('hello')
  end

  it 'reads the body into a given buffer' do
    buffer = +'> '
    response.read_body(buffer)

    expect(buffer).to eq('> hello')
  end

  it 'yields the body chunks to a block' do
    received = []
    response.read_body { |chunk| received << chunk }

    expect(received).to eq(%w[hel lo])
  end

  it 'refuses both a buffer and a block' do
    expect { response.read_body(+'') { nil } }.to raise_error(ArgumentError, /both arg and block/)
  end

  it 'refuses to read the body twice into a buffer or block' do
    response.read_body

    expect { response.read_body(+'') }.to raise_error(IOError, 'Net::HTTPOK#read_body called twice')
    expect { response.read_body { nil } }.to raise_error(IOError, 'Net::HTTPOK#read_body called twice')
  end

  context 'when the body is compressed' do
    let(:compressed) { Zlib.gzip('hello hello hello') }
    let(:chunks) { [compressed[0, 5], compressed[5..]] }

    it 'inflates it' do
      response.http2_body(exchange, inflate: true, expected: true)

      expect(response.body).to eq('hello hello hello')
    end
  end

  context 'when no body is expected' do
    it 'drains the stream and leaves the body nil' do
      response.http2_body(exchange, inflate: false, expected: false)

      expect(response.body).to be_nil
    end
  end
end
