# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::ConnectionPools::Connection do
  let(:connection) { described_class.open('example.com', 80, { read_timeout: 7 }, 100.0) }

  describe '.open' do
    it 'starts a Net::HTTP session with the connection options' do
      expect(connection.http).to be_started
      expect(connection.http.address).to eq('example.com')
      expect(connection.http.read_timeout).to eq(7)
    end

    it 'records when it was opened' do
      expect(connection.opened_at).to eq(100.0)
      expect(connection.last_used_at).to eq(100.0)
    end
  end

  describe '#used' do
    it 'records when it was last used' do
      connection.used(105.0)

      expect(connection.last_used_at).to eq(105.0)
      expect(connection.opened_at).to eq(100.0)
    end
  end

  describe '#expired?' do
    it 'is false before the ttl has passed since it was opened' do
      expect(connection.expired?(30, 129.9)).to be(false)
    end

    it 'is true once the ttl has passed since it was opened' do
      expect(connection.expired?(30, 130.0)).to be(true)
    end
  end

  describe '#close' do
    it 'finishes the session' do
      connection.close

      expect(connection.http).not_to be_started
    end

    it 'does nothing when already closed' do
      connection.close

      expect { connection.close }.not_to raise_error
    end
  end
end
