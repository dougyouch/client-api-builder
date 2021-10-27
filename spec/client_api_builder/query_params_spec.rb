require 'spec_helper'

describe ClientApiBuilder::QueryParams do
  let(:data) do
    {
      'test' => 7,
      object: {
        id: 4,
        name: '=Foo Bar&',
        empty: nil,
        chance: 5.1,
        counts: [1, 2],
        things: [
          {
            id: 2,
            available: true
          },
          {
            id: 6,
            available: false
          }
        ]
      }
    }
  end
  let(:namespace) { nil }
  let(:name_value_separator) { '=' }
  let(:param_separator) { '&' }

  let(:expected_query) do
    [
      'test=7',
      'object[id]=4',
      'object[name]=%3DFoo+Bar%26',
      'object[empty]=',
      'object[chance]=5.1',
      'object[counts][]=1',
      'object[counts][]=2',
      'object[things][][id]=2',
      'object[things][][available]=true',
      'object[things][][id]=6',
      'object[things][][available]=false'
    ].join(param_separator)
  end

  context 'to_query' do
    subject { ClientApiBuilder::QueryParams.new(name_value_separator: name_value_separator, param_separator: param_separator).to_query(data, namespace) }

    it { is_expected.to eq(expected_query) }

    describe 'array' do
      let(:namespace) { 'bar' }
      let(:data) do
        [
          'Foo',
          {
            foo: :bar
          },
          [
            1
          ]
        ]
      end

      let(:expected_query) do
        [
          'bar[]=Foo',
          'bar[][foo]=bar',
          'bar[][]=1'
        ].join(param_separator)
      end
        
      it { is_expected.to eq(expected_query) }

      describe 'without namespace' do
        let(:namespace) { nil }
        let(:expected_query) do
          [
            '[]=Foo',
            '[][foo]=bar',
            '[][]=1'
          ].join(param_separator)
        end

        it { is_expected.to eq(expected_query) }
      end
    end

    describe 'primitive value' do
      let(:data) { 'foo' }
      let(:namespace) { 'bar' }
      let(:expected_query) { 'bar=foo' }

      it { is_expected.to eq(expected_query) }

      describe 'without namespace' do
        let(:data) { 'foo' }
        let(:namespace) { nil }
        let(:expected_query) { 'foo' }

        it { is_expected.to eq(expected_query) }
      end
    end
  end
end
