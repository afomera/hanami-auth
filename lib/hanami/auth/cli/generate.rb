# frozen_string_literal: true

require "hanami/cli"
require_relative "../generator"

module Hanami
  module Auth
    module CLI
      # `hanami generate auth`
      #
      # @api private
      class Generate < Hanami::CLI::Commands::App::Command
        desc "Generate session-based authentication (sign in, sign out, password reset)"

        argument :name, required: false, default: Generator::DEFAULT_MODEL,
          desc: "Name of the model that signs in (default: user)"

        option :slice, required: false, desc: "Slice name"
        option :skip_install, type: :flag, default: false, desc: "Don't run `bundle install` after adding gems"
        option :skip_tests, type: :flag, default: false, desc: "Skip test generation"
        option :force, type: :flag, default: false, desc: "Overwrite existing files"

        example [
          "                     # Users sign in, with code in app/",
          "admin                # Admins sign in (admins and admin_sessions tables)",
          "admin --slice=admin  # Admins sign in, with code in slices/admin/"
        ]

        def call(name: Generator::DEFAULT_MODEL, slice: nil, skip_install: false, skip_tests: false, force: false, **)
          slice_name = slice && inflector.underscore(slice)

          if slice_name && !fs.directory?(fs.join("slices", slice_name))
            raise Hanami::CLI::MissingSliceError.new(slice_name)
          end

          generator = Generator.new(
            fs:,
            inflector:,
            out: stdout,
            app_namespace: app.namespace.to_s,
            model: name,
            slice: slice_name,
            force:,
            test_framework: (test_framework unless skip_tests),
            turbo: Hanami.bundled?("hanami-turbo")
          )
          generator.call

          install_gems unless skip_install || !generator.gemfile_changed?

          generator.print_next_steps
        end

        private

        def test_framework
          if Hanami.bundled?("hanami-rspec")
            "rspec"
          elsif Hanami.bundled?("hanami-minitest")
            "minitest"
          end
        end

        def install_gems
          Hanami::CLI::Bundler.new(fs:).install!
        end
      end
    end
  end
end
