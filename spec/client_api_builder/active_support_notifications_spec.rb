# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'

describe ClientApiBuilder::ActiveSupportNotifications do
  let(:test_class) do
    Class.new do
      include ClientApiBuilder::ActiveSupportNotifications

      attr_reader :total_request_time
    end
  end

  let(:instance) { test_class.new }

  describe '#instrument_request' do
    it 'yields the block' do
      result = instance.instrument_request { 'test_result' }
      expect(result).to eq('test_result')
    end

    it 'sets total_request_time' do
      instance.instrument_request { sleep(0.01) }
      expect(instance.total_request_time).to be >= 0.01
    end

    it 'instruments with ActiveSupport::Notifications' do
      events = []
      subscription = ActiveSupport::Notifications.subscribe('client_api_builder.request') do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      instance.instrument_request { 'test' }

      expect(events.length).to eq(1)
      expect(events.first.payload[:client]).to eq(instance)
      expect(events.first.payload).not_to have_key(:exception)

      ActiveSupport::Notifications.unsubscribe(subscription)
    end

    context 'when block raises StandardError' do
      it 're-raises the original exception object with its backtrace' do
        original_error = StandardError.new('test error')
        original_error.set_backtrace(%w[line1 line2])

        expect { instance.instrument_request { raise original_error } }.to raise_error do |raised|
          expect(raised).to be(original_error)
          expect(raised.backtrace).to eq(%w[line1 line2])
        end
      end

      it 'adds the exception to the event payload' do
        payload = nil
        subscription = ActiveSupport::Notifications.subscribe('client_api_builder.request') { |*, data| payload = data }
        error = ArgumentError.new('bad request')

        expect { instance.instrument_request { raise error } }.to raise_error(error)
        expect(payload).to include(exception: ['ArgumentError', 'bad request'], exception_object: error)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscription)
      end

      it 'still sets total_request_time' do
        begin
          instance.instrument_request { raise StandardError, 'test' }
        rescue StandardError
          # Expected
        end

        expect(instance.total_request_time).not_to be_nil
      end
    end

    context 'when block raises non-StandardError' do
      # NOTE: SystemExit and Interrupt should propagate without being caught
      it 'allows SystemExit to propagate' do
        expect do
          instance.instrument_request { raise SystemExit }
        end.to raise_error(SystemExit)
      end
    end
  end
end
