# frozen_string_literal: true

require 'active_support'

# Purpose is to change the instrument_request to use ActiveSupport::Notifications.instrument
module ClientApiBuilder
  module ActiveSupportNotifications
    def instrument_request
      start_time = Time.now
      error = nil
      result = nil
      ActiveSupport::Notifications.instrument('client_api_builder.request', client: self) do
        result = yield
      rescue StandardError => e
        # Use StandardError instead of Exception to allow SystemExit, Interrupt, etc. to propagate
        error = e
      end

      # Re-raise with original backtrace preserved
      raise(error, error.message, error.backtrace) if error

      result
    ensure
      @total_request_time = Time.now - start_time
    end
  end
end
