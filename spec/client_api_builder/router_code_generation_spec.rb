# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::Router do
  let(:router_class) do
    Class.new do
      include ClientApiBuilder::Router

      base_url 'http://example.com'
    end
  end

  describe '.included' do
    context 'when ActiveSupport is not loaded' do
      before { hide_const('ActiveSupport') }

      it 'does not include the ActiveSupport instrumentation' do
        kls = Class.new { include ClientApiBuilder::Router }
        expect(kls.ancestors).not_to include(ClientApiBuilder::ActiveSupportNotifications)
      end
    end
  end

  describe '.default_options' do
    context 'when Hash#to_query is unavailable' do
      before do
        allow(Hash).to receive(:method_defined?).and_call_original
        allow(Hash).to receive(:method_defined?).with(:to_query).and_return(false)
      end

      it 'falls back to the query_params builder' do
        kls = Class.new { include ClientApiBuilder::Router }
        expect(kls.default_options[:query_builder]).to eq(:query_params)
      end
    end
  end

  describe '.deep_dup_hash' do
    it 'copies hashes inside arrays and keeps other elements' do
      original = { list: [1, { a: 'b' }] }
      copy = router_class.deep_dup_hash(original)

      expect(copy).to eq(original)
      expect(copy[:list][1]).not_to be(original[:list][1])
    end
  end

  describe '.deep_dup' do
    it 'copies hashes and arrays at any depth' do
      original = { list: [[{ a: 'b' }]] }
      copy = router_class.deep_dup(original)

      expect(copy).to eq(original)
      expect(copy[:list][0][0]).not_to be(original[:list][0][0])
    end
  end

  describe '.route with query and body hashes' do
    let(:query) { { app_id: :app_id, filters: [{ tag: :tag }] } }
    let(:body) { [{ name: :name }] }

    it 'leaves the caller\'s hashes unchanged' do
      router_class.route :create_a, '/a', query: query, body: body

      expect(query).to eq(app_id: :app_id, filters: [{ tag: :tag }])
      expect(body).to eq([{ name: :name }])
    end

    it 'lets routes share one hash' do
      router_class.route :get_a, '/a', query: query
      router_class.route :get_b, '/b', query: query

      expect(router_class.instance_method(:get_b).parameters).to include(%i[keyreq app_id], %i[keyreq tag])
    end

    it 'accepts frozen hashes' do
      frozen = { app_id: :app_id, nested: { tag: :tag }.freeze }.freeze

      expect { router_class.route :create_c, '/c', query: frozen, body: frozen }.not_to raise_error
    end
  end

  describe '.configure_retries' do
    it 'sets max_retries and the sleep time between retries' do
      router_class.configure_retries(3, 0.5)

      expect(router_class.default_options).to include(max_retries: 3, sleep: 0.5)
    end

    it 'defaults the sleep time' do
      router_class.configure_retries(4)

      expect(router_class.default_options).to include(max_retries: 4, sleep: 0.05)
    end
  end

  describe '.requires_body?' do
    it 'honors no_body' do
      expect(router_class.requires_body?(:post, no_body: true)).to be(false)
    end

    it 'honors has_body' do
      expect(router_class.requires_body?(:get, has_body: true)).to be(true)
    end

    it 'requires a body for post, put and patch by default' do
      expect(router_class.requires_body?(:put, {})).to be(true)
      expect(router_class.requires_body?(:get, {})).to be(false)
    end
  end

  describe '.get_arguments' do
    it 'collects symbols from an array and replaces instance method placeholders' do
      list = [:first, '{second}', 'plain', [:third], { fourth: :fourth }]

      expect(router_class.get_arguments(list)).to eq(%i[first third fourth])
      expect(list).to eq(['__||first||__', '__||second||__', 'plain', ['__||third||__'], { fourth: '__||fourth||__' }])
    end

    it 'replaces instance method placeholders in hash values and ignores other values' do
      hsh = { name: '{label}', count: 5 }

      expect(router_class.get_arguments(hsh)).to eq([])
      expect(hsh).to eq(name: '__||label||__', count: 5)
    end

    it 'returns no arguments for other values' do
      expect(router_class.get_arguments('raw body')).to eq([])
    end
  end

  describe '.value_to_code' do
    it 'renders empty hashes' do
      expect(router_class.value_to_code({})).to eq('{}')
    end

    it 'renders symbol, string and other keys' do
      expect(router_class.value_to_code({ a: 1, 'b' => 2, 3 => 4 })).to eq('{a: 1, "b" => 2, 3 => 4}')
    end

    it 'renders arrays, nil and booleans' do
      expect(router_class.value_to_code([nil, true, false, 'x'])).to eq('[nil, true, false, "x"]')
    end
  end

  describe '.generate_route_code' do
    subject(:code) { router_class.generate_route_code(:download, '/files/:id', options) }

    context 'with stream: true' do
      let(:options) { { stream: true } }

      it 'streams to a file' do
        expect(code).to include('def download_raw_response(id:, file:, **__options__, &block)')
        expect(code).to include('@request_options[:file] = file')
        expect(code).to include('@response = stream_to_file(**@request_options)')
        expect(code).to include("    @response\n")
      end
    end

    context 'with stream: :io' do
      let(:options) { { stream: :io } }

      it 'streams to an IO' do
        expect(code).to include('@request_options[:io] = io')
        expect(code).to include('@response = stream_to_io(**@request_options)')
      end
    end

    context 'with stream: :block' do
      let(:options) { { stream: :block } }

      it 'streams to the block' do
        expect(code).to include('def download_raw_response(id:, **__options__, &block)')
        expect(code).to include('@response = stream(**@request_options, &block)')
      end
    end

    context 'with return: :body' do
      let(:options) { { return: :body } }

      it 'returns the response body' do
        expect(code).to include("    @response.body\n")
      end
    end

    context 'with return: :response' do
      let(:options) { { return: :response } }

      it 'returns the response' do
        expect(code).to include("    @response\n")
      end
    end
  end
end
