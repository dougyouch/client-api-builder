# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::HTTP2::Exchange do
  let(:stream) do
    Class.new do
      attr_reader :id

      def initialize
        @id = 3
        @listeners = {}
      end

      def on(event, &block)
        @listeners[event] = block
      end

      def emit(event, *args)
        @listeners.fetch(event).call(*args)
      end
    end.new
  end
  let!(:exchange) { described_class.new(stream, 1) }

  describe '#response_headers' do
    it 'returns the final headers, skipping informational ones' do
      stream.emit(:headers, [[':status', '103'], %w[link </style.css>]])
      stream.emit(:headers, [[':status', '200'], %w[content-type text/plain]])

      expect(exchange.response_headers).to eq([[':status', '200'], %w[content-type text/plain]])
    end

    it 'raises StreamRefused when the server refuses the stream' do
      stream.emit(:close, :refused_stream)

      expect { exchange.response_headers }
        .to raise_error(ClientApiBuilder::HTTP2::StreamRefused, 'server refused HTTP/2 stream 3')
    end

    it 'raises StreamError when the stream is reset' do
      stream.emit(:close, :internal_error)

      expect { exchange.response_headers }.to raise_error(
        ClientApiBuilder::HTTP2::StreamError, 'HTTP/2 stream 3 closed before the response finished (internal_error)'
      )
    end

    it 'raises StreamError when the stream ends without headers' do
      stream.emit(:close, nil)

      expect { exchange.response_headers }.to raise_error(ClientApiBuilder::HTTP2::StreamError, /\(no_error\)/)
    end

    it 'raises the error the connection failed it with' do
      exchange.fail(ClientApiBuilder::HTTP2::ConnectionLost.new('gone'))

      expect { exchange.response_headers }.to raise_error(ClientApiBuilder::HTTP2::ConnectionLost, 'gone')
    end

    it 'raises Net::ReadTimeout when nothing arrives within read_timeout' do
      exchange = described_class.new(stream, 0.01)

      expect { exchange.response_headers }
        .to raise_error(Net::ReadTimeout, %r{no response on HTTP/2 stream 3 within 0.01s})
    end
  end

  describe '#each_chunk' do
    it 'yields data until the stream closes, ignoring trailers' do
      stream.emit(:data, 'he')
      stream.emit(:data, 'llo')
      stream.emit(:headers, [%w[x-checksum abc]])
      stream.emit(:close, :no_error)

      chunks = []
      exchange.each_chunk { |chunk| chunks << chunk }

      expect(chunks).to eq(%w[he llo])
    end

    it 'raises when the stream is reset mid-body' do
      stream.emit(:data, 'he')
      stream.emit(:close, :cancel)

      expect { exchange.each_chunk { |_chunk| nil } }.to raise_error(ClientApiBuilder::HTTP2::StreamError, /cancel/)
    end
  end
end
