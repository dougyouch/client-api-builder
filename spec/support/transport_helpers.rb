# frozen_string_literal: true

require 'support/keep_alive_server'

# Sends a GET through a transport the way NetHTTP::Request does, returning the body
module TransportHelpers
  def get_through(transport, url, connection_options = {})
    uri = URI("#{url}/ping")
    transport.with_connection(uri, connection_options) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri)).body
    end
  end

  # Runs the example against a KeepAliveServer, as server
  def self.included(base)
    base.let(:server) { KeepAliveServer.new }
    base.around do |example|
      WebMock.disable_net_connect!(allow_localhost: true)
      example.run
    ensure
      server.stop
      WebMock.disable_net_connect!
    end
  end
end
