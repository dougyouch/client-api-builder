# frozen_string_literal: true

require 'rubygems'
require 'bundler'
require 'json'
require 'securerandom'
require 'simplecov'
require 'webmock/rspec'
require 'active_support/core_ext/object/to_query'

SimpleCov.start do
  enable_coverage :branch

  add_filter '/spec/'
  # loaded by the gemspec before SimpleCov starts, so it would always show as missed
  add_filter 'lib/client_api_builder/version.rb'

  add_group 'Core', 'lib/client_api_builder'

  track_files 'lib/**/*.rb'
end

begin
  Bundler.require(:default, :development, :spec)
rescue Bundler::BundlerError => e
  warn e.message
  warn 'Run `bundle install` to install missing gems'
  exit e.status_code
end

$LOAD_PATH.unshift(File.join(__FILE__, '../..', 'lib'))
$LOAD_PATH.unshift(File.expand_path(__dir__))
require 'client-api-builder'
