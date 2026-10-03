# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'
require 'logger'
require 'stringio'

describe ClientApiBuilder::ActiveSupportLogSubscriber do
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }
  let(:subscriber) { described_class.new(logger) }
  let(:client_class) { Class.new { include ClientApiBuilder::Router } }

  describe '#initialize' do
    it 'sets the logger' do
      expect(subscriber.logger).to eq(logger)
    end
  end

  describe '#subscribe!' do
    after do
      # Clean up subscriptions
      ActiveSupport::Notifications.unsubscribe('client_api_builder.request')
    end

    it 'subscribes to client_api_builder.request events' do
      subscriber.subscribe!

      # Create a mock client
      mock_client = instance_double(
        client_class,
        request_options: {
          method: :get,
          uri: URI('http://example.com/users')
        },
        response: instance_double(Net::HTTPResponse, code: '200')
      )

      ActiveSupport::Notifications.instrument('client_api_builder.request', client: mock_client) do
        # Simulate request
      end

      log_output.rewind
      log_content = log_output.read

      expect(log_content).to include('GET')
      expect(log_content).to include('example.com')
      expect(log_content).to include('/users')
      expect(log_content).to include('[200]')
    end
  end

  describe '#generate_log_message' do
    let(:uri) { URI('https://api.example.com/v1/users') }
    let(:mock_response) { instance_double(Net::HTTPResponse, code: '201') }
    let(:mock_client) do
      instance_double(
        client_class,
        request_options: { method: :post, uri: uri },
        response: mock_response
      )
    end
    let(:event) do
      instance_double(
        ActiveSupport::Notifications::Event,
        payload: { client: mock_client },
        duration: 150.5
      )
    end

    it 'generates a properly formatted log message' do
      message = subscriber.generate_log_message(event)

      expect(message).to include('POST')
      expect(message).to include('https://api.example.com/v1/users')
      expect(message).to include('[201]')
      expect(message).to include('150ms')
    end

    context 'when response is nil' do
      let(:mock_client) do
        instance_double(
          client_class,
          request_options: { method: :get, uri: uri },
          response: nil
        )
      end

      it 'shows UNKNOWN for response code' do
        message = subscriber.generate_log_message(event)
        expect(message).to include('[UNKNOWN]')
      end
    end

    context 'when the request raised' do
      let(:mock_client) { instance_double(client_class, request_options: { method: :get, uri: uri }, response: nil) }
      let(:event) do
        instance_double(
          ActiveSupport::Notifications::Event,
          payload: { client: mock_client, exception: ['Net::ReadTimeout', 'Net::ReadTimeout'] },
          duration: 150.5
        )
      end

      it 'appends the exception' do
        expect(subscriber.generate_log_message(event))
          .to eq('GET https://api.example.com/v1/users[UNKNOWN] took 150ms (Net::ReadTimeout: Net::ReadTimeout)')
      end
    end

    context 'when the request was not built' do
      let(:mock_client) { instance_double(client_class, request_options: nil, response: nil) }

      it 'says so instead of failing' do
        expect(subscriber.generate_log_message(event)).to eq('[request not built][UNKNOWN] took 150ms')
      end
    end

    context 'when the request has no URI' do
      let(:mock_client) { instance_double(client_class, request_options: { method: :get }, response: nil) }

      it 'says so instead of failing' do
        expect(subscriber.generate_log_message(event)).to eq('GET [no URI][UNKNOWN] took 150ms')
      end
    end

    context 'with different HTTP methods' do
      %i[get post put patch delete].each do |http_method|
        it "handles #{http_method.upcase} method" do
          client = instance_double(
            client_class,
            request_options: { method: http_method, uri: uri },
            response: mock_response
          )
          event = instance_double(ActiveSupport::Notifications::Event, payload: { client: client }, duration: 100)

          message = subscriber.generate_log_message(event)
          expect(message).to include(http_method.to_s.upcase)
        end
      end
    end
  end

  describe 'logging a failed request' do
    let(:router_class) do
      Class.new do
        include ClientApiBuilder::Router

        base_url 'http://example.com'

        route :get_ok, '/ok'
        route :get_slow, '/slow'
      end
    end

    after { ActiveSupport::Notifications.unsubscribe('client_api_builder.request') }

    it 'does not report the previous response for a timed-out request' do
      stub_request(:get, 'http://example.com/ok')
      stub_request(:get, 'http://example.com/slow').to_timeout
      router = router_class.new
      router.get_ok
      subscriber.subscribe!

      expect { router.get_slow }.to raise_error(Net::OpenTimeout)
      expect(log_output.string).to match(%r{GET http://example.com/slow\[UNKNOWN\] took \d+ms \(Net::OpenTimeout: execution expired\)})
    end
  end
end
