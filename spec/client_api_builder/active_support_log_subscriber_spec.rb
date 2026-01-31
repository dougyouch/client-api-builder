# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'
require 'logger'
require 'stringio'

describe ClientApiBuilder::ActiveSupportLogSubscriber do
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }
  let(:subscriber) { described_class.new(logger) }

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
      mock_client = double(
        'client',
        request_options: {
          method: :get,
          uri: URI('http://example.com/users')
        },
        response: double('response', code: '200')
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
    let(:mock_response) { double('response', code: '201') }
    let(:mock_client) do
      double(
        'client',
        request_options: { method: :post, uri: uri },
        response: mock_response
      )
    end
    let(:event) do
      double(
        'event',
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
        double(
          'client',
          request_options: { method: :get, uri: uri },
          response: nil
        )
      end

      it 'shows UNKNOWN for response code' do
        message = subscriber.generate_log_message(event)
        expect(message).to include('[UNKNOWN]')
      end
    end

    context 'with different HTTP methods' do
      %i[get post put patch delete].each do |http_method|
        it "handles #{http_method.upcase} method" do
          client = double(
            'client',
            request_options: { method: http_method, uri: uri },
            response: mock_response
          )
          event = double('event', payload: { client: client }, duration: 100)

          message = subscriber.generate_log_message(event)
          expect(message).to include(http_method.to_s.upcase)
        end
      end
    end
  end
end
