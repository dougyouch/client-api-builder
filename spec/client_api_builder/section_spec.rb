# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::Section do
  let(:client_class) do
    Class.new do
      include ClientApiBuilder::Router

      base_url 'https://api.example.com'
      attr_accessor :token

      section :users, { on_error: ->(e) { "failed: #{e.message}" } } do
        header 'Authorization', :token

        route :list_users, '/users'
      end
    end
  end

  let(:client) { client_class.new.tap { |c| c.token = 'secret' } }

  before { stub_request(:get, 'https://api.example.com/users').to_return(body: '[]') }

  describe '.section' do
    it 'works on an anonymous client class' do
      expect(client.users.list_users).to eq([])
      expect(client.users.request_options[:headers]).to eq('Authorization' => 'secret')
    end

    it 'returns the section router class from <name>_router' do
      expect(client_class.users_router.superclass).to eq(ClientApiBuilder::NestedRouter)
      expect(client.users).to be_a(client_class.users_router)
    end

    it 'memoizes the section router per client instance' do
      users = client.users

      expect(client.users).to be(users)
      expect(client_class.new.users).not_to be(users)
    end

    it 'passes option values through unchanged, with a copy per client instance' do
      other = client_class.new
      client.users.nested_router_options[:extra] = true

      expect(client.users.nested_router_options[:on_error].call(StandardError.new('boom'))).to eq('failed: boom')
      expect(other.users.nested_router_options).not_to have_key(:extra)
    end

    it 'is inherited by subclasses' do
      subclass = Class.new(client_class)

      expect(subclass.new.users.list_users).to eq([])
    end

    it 'can be redefined by a subclass' do
      subclass = Class.new(client_class) do
        section(:users) { route :list_users, '/v2/users' }
      end
      stub_request(:get, 'https://api.example.com/v2/users').to_return(body: '[1]')

      expect(subclass.new.users.list_users).to eq([1])
    end

    it 'works on a named client class' do
      stub_const('NamedSectionClient', client_class)

      expect(NamedSectionClient.new.users.list_users).to eq([])
    end

    it 'rejects names that are not identifiers' do
      expect { client_class.section(:'my-users') { nil } }
        .to raise_error(ArgumentError, 'Invalid section name: :"my-users"')
    end
  end
end
