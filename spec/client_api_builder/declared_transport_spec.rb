# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::DeclaredTransport do
  def declared(*modules)
    client_class = Class.new do
      include ClientApiBuilder::Router

      modules.each { |mod| include mod }
    end
    ClientApiBuilder.transports.registered_for(client_class)
  end

  it 'declares the pools for a class including ConnectionPools' do
    expect(declared(ClientApiBuilder::ConnectionPools)).to be_a(ClientApiBuilder::Transports::Pooled)
  end

  it 'declares the per-thread connections for a class including ThreadConnections' do
    expect(declared(ClientApiBuilder::ThreadConnections)).to be_a(ClientApiBuilder::Transports::ThreadLocal)
  end

  it 'declares HTTP/2 falling back to a new connection per request' do
    transport = declared(ClientApiBuilder::HTTP2)

    expect(transport).to be_a(ClientApiBuilder::Transports::HTTP2)
    expect(transport.fallback).to be_a(ClientApiBuilder::Transports::OneShot)
  end

  it 'declares HTTP/2 falling back to the class pools' do
    client_class = Class.new do
      include ClientApiBuilder::Router
      include ClientApiBuilder::ConnectionPools
      include ClientApiBuilder::HTTP2
    end
    transport = ClientApiBuilder.transports.registered_for(client_class)

    expect(transport.fallback.pool_set).to be(client_class.connection_pools)
    expect(transport.connections).to be(client_class.http2_connections)
  end

  it 'keeps the HTTP/2 connections when a subclass configures its own pools' do
    parent = Class.new do
      include ClientApiBuilder::Router
      include ClientApiBuilder::ThreadConnections
      include ClientApiBuilder::HTTP2
    end
    child = Class.new(parent) { connection_per_thread ttl: 5 }
    transport = ClientApiBuilder.transports.registered_for(child)

    expect(transport.connections).to be(parent.http2_connections)
    expect(transport.fallback.connection_set).to be(child.thread_connections)
    expect(child.thread_connections).not_to be(parent.thread_connections)
  end
end
