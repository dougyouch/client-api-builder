# frozen_string_literal: true

# Purpose: objects that own connections and send requests, chosen per environment at boot
# rather than baked into a client class:
#
#   ClientApiBuilder.use_transport(ClientApiBuilder::Transports::ThreadLocal.new)              # every client
#   ClientApiBuilder.use_transport(ClientApiBuilder::Transports::Pooled.new, GitHubClient) # one class
#
# A transport answers with_connection(uri, connection_options) { |http| ... }, yielding
# something that responds to request(net_request) { |response| } like a started Net::HTTP,
# and close, which closes its connections.
module ClientApiBuilder
  module Transports
    autoload :HTTP2, 'client_api_builder/transports/http2'
    autoload :OneShot, 'client_api_builder/transports/one_shot'
    autoload :Pooled, 'client_api_builder/transports/pooled'
    autoload :Registry, 'client_api_builder/transports/registry'
    autoload :ThreadLocal, 'client_api_builder/transports/thread_local'
  end
end
