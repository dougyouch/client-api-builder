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

  describe 'inherit:' do
    let(:client_class) do
      Class.new do
        include ClientApiBuilder::Router

        base_url 'https://api.example.com'
        header 'Authorization', :authorization
        header 'X-Shared', 'root'
        query_param :api_key, 'k1'
        connection_option :open_timeout, 5
        attr_accessor :token

        section :all, inherit: %i[headers query_params connection_options] do
          header 'X-Shared', 'section'
          connection_option :read_timeout, 30

          route :list_items, '/items', query: { page: :page }
        end

        section :headers_only, inherit: :headers do
          route :list_items, '/items'
        end

        section :none do
          route :list_items, '/items'
        end

        section :declared_in_block do
          inherit_from_root :query_params
          route :list_items, '/items'
        end

        def authorization
          "Bearer #{token}"
        end
      end
    end

    before { stub_request(:get, %r{https://api.example.com/items}).to_return(body: '[]') }

    it 'uses the root settings beneath the section\'s own, resolved on the root client' do
      client.all.list_items(page: 2)

      expect(client.all.request_options[:headers]).to eq('Authorization' => 'Bearer secret', 'X-Shared' => 'section')
      expect(URI.decode_www_form(client.all.request_options[:uri].query).to_h).to eq('api_key' => 'k1', 'page' => '2')
      expect(client.all.request_options[:connection_options]).to eq(open_timeout: 5, read_timeout: 30)
    end

    it 'inherits only the listed settings' do
      client.headers_only.list_items

      expect(client.headers_only.request_options[:headers]).to eq('Authorization' => 'Bearer secret', 'X-Shared' => 'root')
      expect(client.headers_only.request_options[:uri].query).to be_nil
      expect(client.headers_only.request_options[:connection_options]).to eq({})
    end

    it 'inherits nothing by default' do
      client.none.list_items

      expect(client.none.request_options[:headers]).to eq({})
      expect(client.none.request_options[:uri].query).to be_nil
    end

    it 'can be declared inside the section block' do
      client.declared_in_block.list_items

      expect(client.declared_in_block.request_options[:uri].query).to eq('api_key=k1')
    end

    it 'lets per-request headers override or drop inherited ones' do
      client.headers_only.list_items(headers: { 'X-Shared' => 'request', 'Authorization' => nil })

      expect(client.headers_only.request_options[:headers]).to eq('Authorization' => nil, 'X-Shared' => 'request')
    end

    it 'reads root settings per request, including ones declared after the section' do
      client_class.header 'X-Late', 'added later'
      client.headers_only.list_items

      expect(client.headers_only.request_options[:headers]).to include('X-Late' => 'added later')
    end

    it 'uses the settings of a root client subclass' do
      subclass = Class.new(client_class) { header 'X-Shared', 'subclass' }
      subclient = subclass.new

      subclient.headers_only.list_items
      expect(subclient.headers_only.request_options[:headers]).to include('X-Shared' => 'subclass')
    end

    it 'inherits from the root client in nested sections' do
      client_class.section :outer do
        section :inner, inherit: :headers do
          route :list_items, '/items'
        end
      end

      client.outer.inner.list_items
      expect(client.outer.inner.request_options[:headers]).to include('Authorization' => 'Bearer secret')
    end

    it 'keeps inherit: out of nested_router_options' do
      client_class.section :tagged, inherit: :headers, team: 'billing'

      expect(client.tagged.nested_router_options).to eq(team: 'billing')
    end

    it 'records the inherited settings on the section class' do
      expect(client_class.all_router.inherited_root_settings).to eq(%i[headers query_params connection_options])
      expect(client_class.none_router.inherited_root_settings).to eq([])
    end

    it 'rejects unknown settings' do
      expect { client_class.section :bad, inherit: %i[headers retries] }
        .to raise_error(ArgumentError, 'Unknown inherit setting(s): :retries. Allowed: :headers, :query_params, :connection_options')
    end
  end
end
