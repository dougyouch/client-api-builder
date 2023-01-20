# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'client-api-builder'
  s.version     = '0.5.5'
  s.licenses    = ['MIT']
  s.summary     = 'Utility for creating API clients through configuration'
  s.description = 'Create API clients through configuration with complete transparency'
  s.authors     = ['Doug Youch']
  s.email       = 'dougyouch@gmail.com'
  s.homepage    = 'https://github.com/dougyouch/client-api-builder'
  s.files       = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

  s.add_runtime_dependency 'inheritance-helper', '>= 0.2.5'
end
