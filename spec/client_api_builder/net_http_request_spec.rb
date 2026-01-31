# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

describe ClientApiBuilder::NetHTTP::Request do
  let(:test_class) do
    Class.new do
      include ClientApiBuilder::NetHTTP::Request
    end
  end

  let(:instance) { test_class.new }

  describe 'ALLOWED_FILE_MODES' do
    it 'includes common write modes' do
      expect(ClientApiBuilder::NetHTTP::Request::ALLOWED_FILE_MODES).to include('wb', 'w', 'ab', 'a')
    end
  end

  describe 'DEFAULT_SECURE_OPTIONS' do
    it 'includes SSL verification' do
      expect(ClientApiBuilder::NetHTTP::Request::DEFAULT_SECURE_OPTIONS[:verify_mode]).to eq(OpenSSL::SSL::VERIFY_PEER)
    end

    it 'includes default timeouts' do
      expect(ClientApiBuilder::NetHTTP::Request::DEFAULT_SECURE_OPTIONS[:open_timeout]).to eq(30)
      expect(ClientApiBuilder::NetHTTP::Request::DEFAULT_SECURE_OPTIONS[:read_timeout]).to eq(60)
    end
  end

  describe '#stream_to_file' do
    let(:uri) { URI('http://example.com/file') }
    let(:method) { :get }
    let(:body) { nil }
    let(:headers) { {} }
    let(:connection_options) { {} }

    before do
      allow(instance).to receive(:stream_to_io)
    end

    context 'with valid file mode' do
      it 'accepts nil file_mode and defaults to wb' do
        tempfile = Tempfile.new('test')
        begin
          expect do
            instance.stream_to_file(
              method: method, uri: uri, body: body, headers: headers,
              connection_options: {}, file: tempfile.path
            )
          end.not_to raise_error
        ensure
          tempfile.close
          tempfile.unlink
        end
      end

      it 'accepts valid file modes' do
        ClientApiBuilder::NetHTTP::Request::ALLOWED_FILE_MODES.each do |mode|
          tempfile = Tempfile.new('test')
          begin
            expect do
              instance.stream_to_file(
                method: method, uri: uri, body: body, headers: headers,
                connection_options: { file_mode: mode }, file: tempfile.path
              )
            end.not_to raise_error
          ensure
            tempfile.close
            tempfile.unlink
          end
        end
      end
    end

    context 'with invalid file mode' do
      it 'raises ArgumentError for invalid mode' do
        expect do
          instance.stream_to_file(
            method: method, uri: uri, body: body, headers: headers,
            connection_options: { file_mode: 'rx' }, file: '/tmp/test'
          )
        end.to raise_error(ArgumentError, /Invalid file mode/)
      end
    end

    context 'with path traversal attempt' do
      it 'raises ArgumentError for .. in path' do
        expect do
          instance.stream_to_file(
            method: method, uri: uri, body: body, headers: headers,
            connection_options: {}, file: '/tmp/../etc/passwd'
          )
        end.to raise_error(ArgumentError, /path traversal/)
      end

      it 'raises ArgumentError for null byte in path' do
        expect do
          instance.stream_to_file(
            method: method, uri: uri, body: body, headers: headers,
            connection_options: {}, file: "/tmp/test\0.txt"
          )
        end.to raise_error(ArgumentError)
      end
    end

    context 'does not mutate connection_options' do
      it 'preserves the original hash' do
        tempfile = Tempfile.new('test')
        begin
          original_options = { file_mode: 'wb', other_option: 'value' }
          options_copy = original_options.dup

          instance.stream_to_file(
            method: method, uri: uri, body: body, headers: headers,
            connection_options: original_options, file: tempfile.path
          )

          expect(original_options).to eq(options_copy)
        ensure
          tempfile.close
          tempfile.unlink
        end
      end
    end
  end

  describe '#request' do
    let(:uri) { URI('https://example.com/api') }
    let(:method) { :get }
    let(:body) { nil }
    let(:headers) { {} }
    let(:connection_options) { {} }

    before do
      stub_request(:get, 'https://example.com/api').to_return(status: 200, body: '{}')
    end

    it 'makes HTTPS requests with SSL verification enabled' do
      # The request should succeed (WebMock doesn't actually verify SSL)
      instance.request(
        method: method, uri: uri, body: body, headers: headers,
        connection_options: connection_options
      )

      expect(WebMock).to have_requested(:get, 'https://example.com/api')
    end

    context 'with HTTP URI' do
      let(:uri) { URI('http://example.com/api') }

      before do
        stub_request(:get, 'http://example.com/api').to_return(status: 200, body: '{}')
      end

      it 'makes HTTP requests without SSL options' do
        instance.request(
          method: method, uri: uri, body: body, headers: headers,
          connection_options: connection_options
        )

        expect(WebMock).to have_requested(:get, 'http://example.com/api')
      end
    end
  end
end
