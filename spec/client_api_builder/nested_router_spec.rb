# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::NestedRouter do
  let(:router_class) do
    class_name = "TestRouter#{rand(1_000_000)}"
    Module.const_set(class_name, Class.new)
    kls = Module.const_get(class_name)
    kls.class_eval do
      include ClientApiBuilder::Router

      attr_accessor :auth_token

      connection_option :open_timeout, 100
      base_url 'http://api.example.com'
      header 'Content-Type', 'application/json'
      query_param 'cachebuster', 1

      section :login do
        connection_option :open_timeout, 1000
        header 'Content-Type', 'application/json'
        header 'X-AuthType', 'JSON'
        base_url 'http://login.example.com'
        query_param 'cachebuster', 5

        route(:create_session, '/sessions', body: { username: :username, password: :password }, expected_response_code: 201) do |res|
          self.auth_token = res['session']['token']
        end

        route :get_profile, '/profiles/{auth_token}'
      end

      section(:auth, ignore_headers: true, ignore_query: true) do
        connection_option :open_timeout, 1000
        header 'Content-Type', 'application/json'
        header 'X-AuthType', 'JSON'
        base_url 'http://auth.example.com'

        route(:create_session, '/sessions', body: { username: :username, password: :password }, expected_response_code: 201) do |res|
          self.auth_token = res['session']['token']
        end
      end
    end
    kls
  end

  let(:username) { 'myclientuser' }
  let(:password) { SecureRandom.uuid }
  let(:router) { router_class.new }

  context 'section' do
    subject { router.login.create_session(username: username, password: password) }

    let(:expected_auth_token) { SecureRandom.uuid }

    before do
      stub_request(:post, 'http://login.example.com/sessions?cachebuster=5')
        .with(
          body: "{\"username\":\"#{username}\",\"password\":\"#{password}\"}",
          headers: {
            'Accept' => '*/*',
            'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
            'Content-Type' => 'application/json',
            'User-Agent' => 'Ruby',
            'X-Authtype' => 'JSON'
          }
        )
        .to_return(status: 201, body: { session: { token: expected_auth_token } }.to_json, headers: {})
    end

    it { expect(subject).to eq(expected_auth_token) }

    it {
      subject
      expect(router.auth_token).to eq(expected_auth_token)
    }

    describe 'ignore_headers' do
      subject { router.auth.create_session(username: username, password: password) }

      let(:expected_auth_token) { SecureRandom.uuid }

      before do
        stub_request(:post, 'http://auth.example.com/sessions')
          .with(
            body: "{\"username\":\"#{username}\",\"password\":\"#{password}\"}",
            headers: {
              'Accept' => '*/*',
              'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
              'User-Agent' => 'Ruby',
              'X-Authtype' => 'JSON'
            }
          )
          .to_return(status: 201, body: { session: { token: expected_auth_token } }.to_json, headers: {})
      end

      it { expect(subject).to eq(expected_auth_token) }

      it {
        subject
        expect(router.auth_token).to eq(expected_auth_token)
      }
    end

    describe 'code' do
      subject { generated_code }

      let(:method_name) { :create_session }
      let(:path) { '/sessions' }
      let(:query) { nil }
      let(:body) { { username: :username, password: :password } }
      let(:expected_response_codes) { nil }
      let(:expected_response_code) { 201 }
      let(:generated_code) { router_class.login_router.generate_route_code(method_name, path, query: query, body: body, expected_response_codes: expected_response_codes, expected_response_code: expected_response_code) }
      let(:expected_code) do
        <<~STR
          def create_session_raw_response(username:, password:, **__options__, &block)
            __path__ = "/sessions"
            __query__ = nil
            __body__ = {username: username, password: password}
            __uri__ = build_uri(__path__, __query__, __options__)
            __body__ = build_body(__body__, __options__)
            __headers__ = build_headers(__options__)
            __connection_options__ = build_connection_options(__options__)
            @request_options = {method: :post, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__}
            @response = request(**@request_options)
          end

          def create_session(username:, password:, **__options__, &block)
            request_wrapper(__options__) do
              block ||= self.class.get_response_proc(:create_session)
              __expected_response_codes__ = ["201"]
              create_session_raw_response(username: username, password: password, **__options__, &block)
              expected_response_code!(@response, __expected_response_codes__, __options__)
              handle_response(@response, __options__, &block)
            end
          end
        STR
      end

      it { expect(subject).to eq(expected_code) }
    end

    describe 'instance methods in path' do
      subject { router.login.get_profile }

      before do
        router.auth_token = 'tok123'
        stub_request(:get, 'http://login.example.com/profiles/tok123?cachebuster=5')
          .to_return(status: 200, body: { name: 'me' }.to_json)
      end

      it 'resolves them on the root router' do
        expect(subject).to eq('name' => 'me')
      end

      it 'URL-encodes them' do
        router.auth_token = 'a/b c'
        stub_request(:get, 'http://login.example.com/profiles/a%2Fb%20c?cachebuster=5')
        router.login.get_profile
        expect(router.login.request_options[:uri].path).to eq('/profiles/a%2Fb%20c')
      end
    end

    describe 'block override' do
      subject { router.login.create_session(username: username, password: password) { nil } }

      it { expect(subject).to be_nil }

      it {
        subject
        expect(router.auth_token).to be_nil
      }
    end
  end

  describe 'a section without its own base_url' do
    let(:router_class) do
      Class.new do
        include ClientApiBuilder::Router

        base_url 'https://api.example.com'

        section :users do
          route :list_users, '/users'
        end
      end
    end

    it 'uses the root base_url' do
      stub = stub_request(:get, 'https://api.example.com/users')

      router.users.list_users
      expect(stub).to have_been_requested
    end
  end
end
