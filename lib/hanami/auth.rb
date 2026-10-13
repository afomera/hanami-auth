# frozen_string_literal: true

require "hanami/cli"
require_relative "auth/version"

module Hanami
  # Adds `hanami generate auth`, which writes session-based authentication into a Hanami app.
  #
  # The gem is a generator only: the generated code lives in the app and doesn't depend on this gem
  # at runtime. Add it to the `:cli` group in your Gemfile so the `hanami` CLI loads it.
  #
  # @api public
  module Auth
    # The gems the generated code is built on. The command is only registered when all are bundled.
    REQUIRED_GEMS = %w[hanami-action hanami-view hanami-db hanami-mailer].freeze

    # @api private
    def self.available?
      REQUIRED_GEMS.all? { Hanami.bundled?(_1) }
    end

    if Hanami::CLI.within_hanami_app?
      require_relative "auth/cli/generate"

      Hanami::CLI.register "generate auth", CLI::Generate if available?
    end
  end
end
