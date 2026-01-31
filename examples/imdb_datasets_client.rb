# frozen_string_literal: true

class IMDBDatesetsClient
  include ClientApiBuilder::Router

  base_url 'https://datasets.imdbws.com'

  route :get_name_basics, '/name.basics.tsv.gz', stream: :file
  route :get_title_akas, '/title.akas.tsv.gz', stream: :io
  route :get_title_basics, '/title.basics.tsv.gz', stream: :block

  def self.stream_to_file
    new.get_name_basics(file: 'name.basics.tsv.gz')
  end

  def self.stream_to_io
    File.open('title.akas.tsv.gz', 'wb') do |io|
      new.get_title_akas(io: io)
    end
  end

  def self.stream_with_block
    File.open('title.basics.tsv.gz', 'wb') do |io|
      total_read = 0.0
      new.get_title_basics do |response, chunk|
        total_read += chunk.bytesize
        percentage_complete = ((total_read / response.content_length) * 100).to_i
        puts "downloading title.basics.tsv.gz completed: #{percentage_complete}%"
        io.write chunk
      end
    end
  end
end
