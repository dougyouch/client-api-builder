require 'spec_helper'

describe ClientApiBuilder::NestedRouter do
  let(:router_class) do
    class_name = 'TestRouter' + rand(1_000_000).to_s
    Module.const_set(class_name, Class.new)
    kls = Module.const_get(class_name)
    kls.class_eval do
      include ClientApiBuilder::Router

      attr_accessor :auth_token

      connection_option :open_timeout, 100
      base_url 'http://api.example.com'
      header 'Content-Type', 'application/json'

      section :login do
        connection_option :open_timeout, 1000
        header 'X-AuthType', 'JSON'
        base_url 'http://login.example.com'

        route(:create_session, '/sessions', body: {username: :username, password: :password}, expected_response_code: 201) do |res|
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
    let(:expected_auth_token) { SecureRandom.uuid }
    before do
      stub_request(:post, "http://login.example.com/sessions").
        with(
          body: "{\"username\":\"#{username}\",\"password\":\"#{password}\"}",
          headers: {
       	    'Accept'=>'*/*',
       	    'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
       	    'Content-Type'=>'application/json',
       	    'User-Agent'=>'Ruby',
       	    'X-Authtype'=>'JSON'
          }).
        to_return(status: 201, body: {session:{token: expected_auth_token}}.to_json, headers: {})
    end      

    subject { router.login.create_session(username: username, password: password) }

    it { expect(subject).to eq(expected_auth_token) }
  end
end
