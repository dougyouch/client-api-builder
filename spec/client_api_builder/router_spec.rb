require 'spec_helper'

describe ClientApiBuilder::Router do
  let(:router_class) do
    Struct.new(:authorization, :request_count, :app_key) do
      include ClientApiBuilder::Router

      connection_option :open_timeout, 100
      base_url 'http://example.com'
      header 'Content-Type', 'application/json'

      route :get_user, '/users/:id', query: {app_id: :app_id}
      route :create_user, '/users', query: {app_id: :app_id}

      namespace '/v2' do
        namespace '/apps' do
          route :get_app_users, '/{app_key}/users'
        end
      end
    end
  end

  let(:authorization) { SecureRandom.uuid }
  let(:request_count) { rand(10_000) }
  let(:app_key) { SecureRandom.uuid }
  let(:router) { router_class.new(authorization, request_count, app_key) }
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
    let(:path) { '/v2/apps/:app_id/users' }
    let(:query) { {auth: :auth} }
    let(:body) { {user: {name: :name, email: :email}} }
    let(:expected_response_codes) { nil }
    let(:expected_response_code) { nil }

    let(:generated_code) { router_class.generate_route_code(method_name, path, query: query, body: body, expected_response_codes: expected_response_codes, expected_response_code: expected_response_code) }
    subject { router_class.route(method_name, path, query: query, body: body, expected_response_codes: expected_response_codes, expected_response_code: expected_response_code); router_class.method_defined?(method_name) }
    let(:route_params) do
      {
        app_id: 8,
        auth: 'secret',
        name: 'Foo',
        email: 'foo@example.com'
      }
    end
    let(:call_route) { router.public_send(method_name, **route_params) }
    let(:expected_route_return_value) do
      {
        'user' => {
          'id' => 6,
          'name' => 'Foo',
          'email' => 'foo@example.com'
        }
      }
    end
    let(:create_stubbed_response) do
      stub_request(:post, "http://example.com/v2/apps/8/users?auth=secret").
        to_return(status: 201, body: expected_route_return_value.to_json)
    end

    let(:expected_code) do
      <<-CODE
def create_user(app_id:, auth:, name:, email:, **__options__, &block)
  block ||= self.class.response_proc(:create_user)
  __path__ = "/v2/apps/\#{escape_path(app_id)}/users"
  __query__ = {:auth=>auth}
  __body__ = {:user=>{:name=>name, :email=>email}}
  __expected_response_codes__ = []
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @request_options = {method: :post, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__}
  @response = request(**@request_options)
  expected_response_code!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
    end

    it { expect(generated_code).to eq(expected_code) }
    it { expect(subject).to eq(true) }
    it { subject; create_stubbed_response; expect(call_route).to eq(expected_route_return_value) }

    describe 'get request no body' do
      let(:path) { '/v2/apps/:app_id/users/:user_id' }
      let(:method_name) { :get_user }
      let(:body) { nil }

      let(:expected_code) do
        <<-CODE
def get_user(app_id:, user_id:, auth:, **__options__, &block)
  block ||= self.class.response_proc(:get_user)
  __path__ = "/v2/apps/\#{escape_path(app_id)}/users/\#{escape_path(user_id)}"
  __query__ = {:auth=>auth}
  __body__ = nil
  __expected_response_codes__ = []
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @request_options = {method: :get, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__}
  @response = request(**@request_options)
  expected_response_code!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end
      let(:route_params) do
        {
          app_id: 8,
          user_id: 6,
          auth: 'secret'
        }
      end
      let(:create_stubbed_response) do
        stub_request(:get, "http://example.com/v2/apps/8/users/6?auth=secret").
          to_return(status: 200, body: expected_route_return_value.to_json)
      end

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }
      it { subject; create_stubbed_response; expect(call_route).to eq(expected_route_return_value) }
    end

    describe 'get request no body, no query' do
      let(:method_name) { :get_users }
      let(:body) { nil }
      let(:query) { nil }
      let(:expected_response_code) { 202 }

      let(:expected_code) do
        <<-CODE
def get_users(app_id:, **__options__, &block)
  block ||= self.class.response_proc(:get_users)
  __path__ = "/v2/apps/\#{escape_path(app_id)}/users"
  __query__ = nil
  __body__ = nil
  __expected_response_codes__ = ["202"]
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @request_options = {method: :get, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__}
  @response = request(**@request_options)
  expected_response_code!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end
      let(:route_params) do
        {
          app_id: 8
        }
      end
      let(:create_stubbed_response) do
        stub_request(:get, "http://example.com/v2/apps/8/users").
          to_return(status: 202, body: expected_route_return_value.to_json)
      end

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }
      it { subject; create_stubbed_response; expect(call_route).to eq(expected_route_return_value) }
    end

    describe 'delete request' do
      let(:path) { '/v2/apps/:app_id/users/:user_id' }
      let(:method_name) { :delete_user }
      let(:body) { nil }
      let(:query) { nil }
      let(:expected_response_codes) { [200, 204] }

      let(:expected_code) do
        <<-CODE
def delete_user(app_id:, user_id:, **__options__, &block)
  block ||= self.class.response_proc(:delete_user)
  __path__ = "/v2/apps/\#{escape_path(app_id)}/users/\#{escape_path(user_id)}"
  __query__ = nil
  __body__ = nil
  __expected_response_codes__ = ["200", "204"]
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @request_options = {method: :delete, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__}
  @response = request(**@request_options)
  expected_response_code!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end
      let(:route_params) do
        {
          app_id: 8,
          user_id: 6
        }
      end
      let(:create_stubbed_response) do
        stub_request(:delete, "http://example.com/v2/apps/8/users/6").
          to_return(status: 204, body: '')
      end
      let(:expected_route_return_value) { nil }

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }
      it { subject; create_stubbed_response; expect(call_route).to eq(expected_route_return_value) }
    end

    describe 'create request' do
      let(:path) { '/v2/apps' }
      let(:method_name) { :create_app }
      let(:body) { nil }
      let(:query) { nil }
      let(:expected_response_code) { 201 }

      let(:expected_code) do
        <<-CODE
def create_app(body:, **__options__, &block)
  block ||= self.class.response_proc(:create_app)
  __path__ = "/v2/apps"
  __query__ = nil
  __body__ = body
  __expected_response_codes__ = ["201"]
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @request_options = {method: :post, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__}
  @response = request(**@request_options)
  expected_response_code!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }
    end

    describe 'instance methods in path' do
      let(:method_name) { :get_app_users }
      let(:path) { '/v2/apps/{app_key}/users' }
      let(:body) { nil }
      let(:query) { nil }
      let(:expected_response_code) { 200 }

      let(:expected_code) do
        <<-CODE
def get_app_users(**__options__, &block)
  block ||= self.class.response_proc(:get_app_users)
  __path__ = "/v2/apps/\#{escape_path(app_key)}/users"
  __query__ = nil
  __body__ = nil
  __expected_response_codes__ = ["200"]
  __uri__ = build_uri(__path__, __query__, __options__)
  __body__ = build_body(__body__, __options__)
  __headers__ = build_headers(__options__)
  __connection_options__ = build_connection_options(__options__)
  @request_options = {method: :get, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__}
  @response = request(**@request_options)
  expected_response_code!(@response, __expected_response_codes__, __options__)
  handle_response(@response, __options__, &block)
end
CODE
      end

      it { expect(generated_code).to eq(expected_code) }
      it { expect(subject).to eq(true) }

    end
  end

  context '.build_headers' do
    let(:route_options) do
      {
        headers: {
          'X-Frame' => 'top',
          'X-Prev-Request-Count' => :request_count,
          'X-Request-Count' => proc { request_count + 2 }
        }
      }
    end
    subject { router.build_headers(route_options) }
    let(:expected_headers) do
      {
        'Content-Type' => 'application/json',
        'Authorization' => authorization,
        'X-Tracking' => (request_count + 1),
        'X-Frame' => 'top',
        'X-Prev-Request-Count' => request_count,
        'X-Request-Count' => (request_count + 2)
      }
    end

    before do
      router_class.header 'Authorization', :authorization
      router_class.header('X-Tracking') { request_count + 1 }
    end

    it { expect(subject).to eq(expected_headers) }
  end
end
