# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'client-api-builder'
  s.version     = '0.6.1'
  s.licenses    = ['MIT']
  s.summary     = 'Build robust, secure API clients through declarative configuration'
  s.description = <<~DESC
    A Ruby gem for building API clients through declarative configuration. Features include
    automatic HTTP method detection, nested routing, streaming support, configurable retries,
    and security features like SSL verification, SSRF protection, and path traversal prevention.
    Define your API endpoints with a clean DSL and get comprehensive error handling, debugging
    capabilities, and optional ActiveSupport integration for logging and instrumentation.
  DESC
  s.authors     = ['Doug Youch']
  s.email       = 'dougyouch@gmail.com'
  s.homepage    = 'https://github.com/dougyouch/client-api-builder'
  s.files       = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

  s.required_ruby_version = '>= 3.0'

  s.add_dependency 'inheritance-helper', '>= 0.2.5'

  s.metadata = {
    'rubygems_mfa_required' => 'true',
    'homepage_uri' => s.homepage,
    'source_code_uri' => 'https://github.com/dougyouch/client-api-builder',
    'changelog_uri' => 'https://github.com/dougyouch/client-api-builder/blob/master/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/dougyouch/client-api-builder/issues'
  }
end
