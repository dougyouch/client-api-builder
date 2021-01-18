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
          1,
          {
            x: :x,
            name: :name
          }
        ]
      }
    end

    subject { router_class.get_arguments(query) }

    let(:expected_hash_arguments) { [:name, :x, :name] }

    it { expect(subject).to eq(expected_hash_arguments) }
  end
end
