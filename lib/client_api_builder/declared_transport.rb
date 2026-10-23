# frozen_string_literal: true

module ClientApiBuilder
  # Class methods shared by the ConnectionPools, ThreadConnections and HTTP2 mixins. Each
  # stores its transport on the class with redefine_class_method, so subclasses share it,
  # and declare_transport registers their combination as the class's declared transport
  # (see Transports::Registry): the HTTP/2 transport falling back to the HTTP/1.1 one.
  module DeclaredTransport
    # The transport for http URLs, and https origins without HTTP/2
    def http1_transport
      Transports::OneShot.new
    end

    # The class's HTTP/2 transport, when it includes HTTP2
    def http2_transport
      nil
    end

    def declare_transport
      transport = http2_transport ? http2_transport.with_fallback(http1_transport) : http1_transport
      ClientApiBuilder.transports.declare(transport, self)
    end
  end
end
