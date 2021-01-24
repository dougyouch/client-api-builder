require 'spec_helper'

describe ClientApiBuilder::Router do
  let(:router_class) do
    Class.new do
      include ClientApiBuilder::Router

      connection_option :open_timeout, 100
      base_url 'http://example.com'
      header 'Content-Type', 'application/json'

      route :get_user, '/users/:id', query: {app_id: :app_id}
      route :create_user, '/users', query: {app_id: :app_id}
    end
  end

  let(:router) { router_class.new }
  let(:expected_base_url) { 'http://example.com' }
  let(:expected_connection_options) { {open_timeout: 100} }

  context '.base_url' do
    subject { router_class.base_url }

    it { expect(subject).to eq(expected_base_url) }
  end

  context '.query_builder' do
    let(:builder) { :to_query }
    subject { router_class.query_builder }

    let(:expected_query_builder) { :to_query }

    before do
      router_class.query_builder builder
    end

    it { expect(subject).to eq(builder) }
  end

  context '.headers' do
    subject { router_class.headers }

    let(:expected_headers) do
      {
        'Content-Type' => 'application/json'
      }
    end

    it { expect(subject).to eq(expected_headers) }

    describe 'add header' do
      before do
        router_class.header 'Authorization', 'basic foo:bar'
      end

      let(:expected_headers) do
        {
          'Content-Type' => 'application/json',
          'Authorization' => 'basic foo:bar'
        }
      end

      it { expect(subject).to eq(expected_headers) }
    end
  end

  context '.connection_options' do
    subject { router_class.connection_options }

    it { expect(subject).to eq(expected_connection_options) }
  end

  context '.http_method' do
    it { expect(router_class.http_method('get_user')).to eq(:get) }
    it { expect(router_class.http_method('create_user')).to eq(:post) }
    it { expect(router_class.http_method('update_user')).to eq(:put) }
    it { expect(router_class.http_method('delete_user')).to eq(:delete) }
    it { expect(router_class.http_method('unknown')).to eq(:get) }
  end

  context '.get_arguments' do
    let(:query) do
      {
        foo: 'bar',
        name: :name,
        nested: [
          {
            x: :x,
            name: :name
          }
        ],
        list: [
          1,
          :bar,
          :foo,
          'name2',
          [
            2,
            :email
          ]
        ]
      }
    end

    subject { router_class.get_arguments(query) }

    let(:expected_hash_arguments) { [:name, :x, :name, :bar, :foo, :email] }

    it { expect(subject).to eq(expected_hash_arguments) }
  end

  context '.route' do
    let(:method_name) { :create_user }
    let(:path) { '/apps/:app_id/users' }
    let(:query) { {auth: :auth} }
    let(:body) { {user: {name: :name, email: :email}} }
    let(:expected_response_codes) { nil }
    let(:expected_response_code) { nil }

    let(:generated_code) { router_class.generate_route_code(method_name, path, query: query, body: body, expected_response_codes: expected_response_codes, expected_response_code: expected_response_code) }
    subject { router_class.route(method_name, path, query: query, body: body); router_class.method_defined?(method_name) }

    let(:expected_code) do
      <<-CODE
def create_user(app_id:, auth:, name:, email:, **__options__, &block)
  __path__ = "/apps/\#{app_id}/users"
  __query__ = {:auth=>auth}
  __body__ = {:user=>{:name=>name, :email=>email}}
  __expected_response_codes__ = []
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @response = request(method: :post, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__)
  expected_response!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
    end

    it { expect(generated_code).to eq(expected_code) }
    it { expect(subject).to eq(true) }

    describe 'get request no body' do
      let(:path) { '/apps/:app_id/users/:user_id' }
      let(:method_name) { :get_user }
      let(:body) { nil }

      let(:expected_code) do
        <<-CODE
def get_user(app_id:, user_id:, auth:, **__options__, &block)
  __path__ = "/apps/\#{app_id}/users/\#{user_id}"
  __query__ = {:auth=>auth}
  __body__ = nil
  __expected_response_codes__ = []
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @response = request(method: :get, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__)
  expected_response!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }
    end

    describe 'get request no body, no query' do
      let(:method_name) { :get_users }
      let(:body) { nil }
      let(:query) { nil }
      let(:expected_response_code) { 202 }

      let(:expected_code) do
        <<-CODE
def get_users(app_id:, **__options__, &block)
  __path__ = "/apps/\#{app_id}/users"
  __query__ = nil
  __body__ = nil
  __expected_response_codes__ = ["202"]
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @response = request(method: :get, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__)
  expected_response!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }
    end

    describe 'delete request' do
      let(:path) { '/apps/:app_id/users/:user_id' }
      let(:method_name) { :delete_user }
      let(:body) { nil }
      let(:query) { nil }
      let(:expected_response_codes) { [200, 204] }

      let(:expected_code) do
        <<-CODE
def delete_user(app_id:, user_id:, **__options__, &block)
  __path__ = "/apps/\#{app_id}/users/\#{user_id}"
  __query__ = nil
  __body__ = nil
  __expected_response_codes__ = ["200", "204"]
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @response = request(method: :delete, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__)
  expected_response!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }
    end

    describe 'create request' do
      let(:path) { '/apps' }
      let(:method_name) { :create_app }
      let(:body) { nil }
      let(:query) { nil }
      let(:expected_response_code) { 201 }

      let(:expected_code) do
        <<-CODE
def create_app(body:, **__options__, &block)
  __path__ = "/apps"
  __query__ = nil
  __body__ = body
  __expected_response_codes__ = ["201"]
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @response = request(method: :post, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__)
  expected_response!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }
    end
  end
end
