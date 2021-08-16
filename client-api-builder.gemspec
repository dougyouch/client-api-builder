# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'client-api-builder'
  s.version     = '0.2.8'
  s.licenses    = ['MIT']
  s.summary     = 'Develop Client API libraries faster'
  s.description = 'Utility for constructing API clients'
  s.authors     = ['Doug Youch']
  s.email       = 'dougyouch@gmail.com'
  s.homepage    = 'https://github.com/dougyouch/client-api-builder'
  s.files       = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

  s.add_runtime_dependency 'inheritance-helper', '>= 0.2.5'
end
