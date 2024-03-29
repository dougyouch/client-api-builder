# frozen_string_literal: true

require 'rubygems'
require 'bundler'
require 'json'
require 'securerandom'
require 'simplecov'
require 'webmock/rspec'
require 'active_support/core_ext/object/to_query'

SimpleCov.start

begin
  Bundler.require(:default, :development, :spec)
rescue Bundler::BundlerError => e
  warn e.message
  warn 'Run `bundle install` to install missing gems'
  exit e.status_code
end

$LOAD_PATH.unshift(File.join(__FILE__, '../..', 'lib'))
$LOAD_PATH.unshift(File.expand_path('..', __FILE__))
require 'client-api-builder'
