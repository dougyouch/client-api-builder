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
    subject { ClientApiBuilder::QueryParams.to_query(data, namespace, name_value_separator, param_separator) }

    it { is_expected.to eq(expected_query) }
  end
end
