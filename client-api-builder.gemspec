# frozen_string_literal: true

require_relative 'lib/client_api_builder/version'

Gem::Specification.new do |s|
  s.name        = 'client-api-builder'
  s.version     = ClientApiBuilder::VERSION
  s.licenses    = ['MIT']
  s.summary     = 'Build Ruby HTTP API clients from declarative route definitions'
  s.description = 'Client API Builder generates HTTP client methods from a declarative route DSL. ' \
                  'It infers HTTP methods from route names, builds query strings and request bodies, ' \
                  'and supports nested routers, configurable retries, and streaming responses to files ' \
                  'or IO. SSL verification, base URL scheme checks, and path traversal protection are ' \
                  'on by default. Optional ActiveSupport integration adds instrumentation and request logging.'
  s.authors     = ['Doug Youch']
  s.email       = 'dougyouch@gmail.com'
  s.homepage    = 'https://github.com/dougyouch/client-api-builder'
  s.files       = Dir.glob('lib/**/*.rb') + %w[README.md LICENSE CHANGELOG.md]

  s.required_ruby_version = '>= 3.2'

  s.add_dependency 'inheritance-helper', '>= 1.0', '< 2'

  s.metadata = {
    'rubygems_mfa_required' => 'true',
    'source_code_uri' => 'https://github.com/dougyouch/client-api-builder',
    'changelog_uri' => 'https://github.com/dougyouch/client-api-builder/blob/master/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/dougyouch/client-api-builder/issues'
  }
end
