# frozen_string_literal: true

require 'active_support'

# Purpose is to change the instrument_request to use ActiveSupport::Notifications.instrument
module ClientApiBuilder
  module ActiveSupportNotifications
    # When the request raises, ActiveSupport adds :exception and :exception_object to the
    # event payload, notifies subscribers, and re-raises the original exception.
    def instrument_request(&)
      start_time = Time.now
      ActiveSupport::Notifications.instrument('client_api_builder.request', client: self, &)
    ensure
      @total_request_time = Time.now - start_time
    end
  end
end
