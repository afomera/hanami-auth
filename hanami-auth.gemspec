# frozen_string_literal: true

require_relative "lib/hanami/auth/version"

Gem::Specification.new do |spec|
  spec.name = "hanami-auth"
  spec.version = Hanami::Auth::VERSION
  spec.authors = ["Andrea Fomera"]
  spec.email = ["afomera@hey.com"]
  spec.summary = "Authentication generator for Hanami apps"
  spec.description = "Adds `hanami generate auth`, which writes session-based sign in and password reset into your Hanami app"
  spec.homepage = "https://github.com/afomera/hanami-auth"
  spec.license = "MIT"

  spec.files = Dir["lib/**/*.rb", "lib/hanami/auth/templates/**/*", "README.md", "LICENSE.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.3"

  spec.add_dependency "hanami-cli", ">= 2.3"
end
