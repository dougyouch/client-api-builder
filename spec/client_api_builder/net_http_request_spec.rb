# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tempfile'
require 'tmpdir'

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
      stub_request(:get, 'http://example.com/file').to_return(status: 200, body: 'data')
    end

    context 'with validate_response' do
      let(:reject) { ->(response) { raise ClientApiBuilder::UnexpectedResponse.new('rejected', response) } }
      let(:path) { File.join(Dir.mktmpdir, 'download.bin') }

      before { stub_request(:get, 'http://example.com/file').to_return(status: 404, body: 'not found page') }

      it 'leaves an existing file untouched when the response is rejected' do
        File.write(path, 'existing contents')

        expect do
          instance.stream_to_file(method: method, uri: uri, body: body, headers: headers,
                                  connection_options: { file_mode: 'ab' }, file: path, validate_response: reject)
        end.to raise_error(ClientApiBuilder::UnexpectedResponse) { |error| expect(error.response.body).to eq('not found page') }
        expect(File.read(path)).to eq('existing contents')
      end

      it 'does not create the file when the response is rejected' do
        expect do
          instance.stream_to_file(method: method, uri: uri, body: body, headers: headers,
                                  connection_options: {}, file: path, validate_response: reject)
        end.to raise_error(ClientApiBuilder::UnexpectedResponse)
        expect(File).not_to exist(path)
      end

      it 'writes the file when the response is accepted' do
        stub_request(:get, 'http://example.com/file').to_return(status: 200, body: 'data')

        response = instance.stream_to_file(method: method, uri: uri, body: body, headers: headers,
                                           connection_options: {}, file: path, validate_response: ->(_) {})
        expect(File.read(path)).to eq('data')
        expect(response).to be_a(Net::HTTPOK)
      end
    end

    context 'with an empty response body' do
      let(:path) { File.join(Dir.mktmpdir, 'download.bin') }

      before { stub_request(:get, 'http://example.com/file').to_return(status: 200, body: '') }

      it 'still creates or truncates the file' do
        File.write(path, 'old contents')

        instance.stream_to_file(method: method, uri: uri, body: body, headers: headers, connection_options: {}, file: path)
        expect(File.read(path)).to eq('')
      end
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

    it 'yields the response to a block' do
      yielded = nil
      instance.request(
        method: method, uri: uri, body: body, headers: headers,
        connection_options: connection_options
      ) { |response| yielded = response }

      expect(yielded.body).to eq('{}')
    end
  end

  describe '#stream_to_io' do
    let(:uri) { URI('http://example.com/file') }

    before do
      stub_request(:get, 'http://example.com/file').to_return(status: 200, body: 'file contents')
    end

    it 'writes the streamed body to the IO' do
      io = StringIO.new
      instance.stream_to_io(method: :get, uri: uri, body: nil, headers: {}, connection_options: {}, io: io)

      expect(io.string).to eq('file contents')
    end

    it 'writes nothing when validate_response rejects the response' do
      io = StringIO.new
      reject = ->(_) { raise ArgumentError, 'rejected' }

      expect do
        instance.stream_to_io(method: :get, uri: uri, body: nil, headers: {}, connection_options: {}, io: io,
                              validate_response: reject)
      end.to raise_error(ArgumentError, 'rejected')
      expect(io.string).to eq('')
    end
  end

  describe '#stream' do
    let(:uri) { URI('http://example.com/file') }

    before do
      stub_request(:get, 'http://example.com/file').to_return(status: 503, body: 'try later')
    end

    it 'passes the response to validate_response before streaming' do
      seen = nil
      chunks = []
      instance.stream(method: :get, uri: uri, body: nil, headers: {}, connection_options: {},
                      validate_response: ->(response) { seen = response.code }) { |_, chunk| chunks << chunk }

      expect(seen).to eq('503')
      expect(chunks).to eq(['try later'])
    end

    it 'reads a rejected body into the response instead of streaming it' do
      chunks = []
      rejected = nil
      reject = lambda do |response|
        rejected = response
        raise ArgumentError, 'rejected'
      end

      expect do
        instance.stream(method: :get, uri: uri, body: nil, headers: {}, connection_options: {},
                        validate_response: reject) { |_, chunk| chunks << chunk }
      end.to raise_error(ArgumentError)
      expect(chunks).to be_empty
      expect(rejected.body).to eq('try later')
    end
  end
end
