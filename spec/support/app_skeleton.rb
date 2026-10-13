# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Writes the parts of a freshly generated Hanami app (`hanami new bookshelf`) that the generator
# changes, into a temp dir, and runs the example inside it.
module AppSkeleton
  FILES = {
    "Gemfile" => <<~RUBY,
      source "https://rubygems.org"

      gem "hanami", "~> 2.3"
      gem "sqlite3"

      group :development do
        gem "hanami-webconsole"
      end
    RUBY
    "config/app.rb" => <<~RUBY,
      # frozen_string_literal: true

      require "hanami"

      module Bookshelf
        class App < Hanami::App
        end
      end
    RUBY
    "config/settings.rb" => <<~RUBY,
      # frozen_string_literal: true

      module Bookshelf
        class Settings < Hanami::Settings
          # Define your app settings here, for example:
          #
          # setting :my_flag, default: false, constructor: Types::Params::Bool
        end
      end
    RUBY
    "config/routes.rb" => <<~RUBY,
      # frozen_string_literal: true

      module Bookshelf
        class Routes < Hanami::Routes
          # Add your routes here. See https://hanakai.org/learn/hanami/routing/ for details.
        end
      end
    RUBY
    "app/action.rb" => <<~RUBY,
      # auto_register: false
      # frozen_string_literal: true

      require "hanami/action"
      require "dry/monads"

      module Bookshelf
        class Action < Hanami::Action
          # Provide `Success` and `Failure` for pattern matching on operation results
          include Dry::Monads[:result]
        end
      end
    RUBY
    "app/views/context.rb" => <<~RUBY,
      # auto_register: false
      # frozen_string_literal: true

      module Bookshelf
        module Views
          class Context < Hanami::View::Context
            # Define your view context here. See https://hanakai.org/learn/hanami/views/context/ for details.
          end
        end
      end
    RUBY
    "app/templates/layouts/app.html.erb" => <<~ERB,
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <title>Bookshelf</title>
        </head>
        <body>
          <%= yield %>
        </body>
      </html>
    ERB
    "config/db/migrate/.keep" => ""
  }.freeze

  SLICE_FILES = {
    "action.rb" => <<~RUBY,
      # auto_register: false
      # frozen_string_literal: true

      module Admin
        class Action < Bookshelf::Action
        end
      end
    RUBY
    "views/context.rb" => <<~RUBY
      # auto_register: false
      # frozen_string_literal: true

      module Admin
        module Views
          class Context < Bookshelf::Views::Context
          end
        end
      end
    RUBY
  }.freeze

  def self.included(base)
    base.around do |example|
      Dir.mktmpdir("hanami-auth") do |dir|
        Dir.chdir(dir) do
          FILES.each { |path, content| AppSkeleton.write(path, content) }
          example.run
        end
      end
    end
  end

  def self.write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def add_slice(name = "admin")
    SLICE_FILES.each { |path, content| AppSkeleton.write(File.join("slices", name, path), content) }
  end

  def out = @out ||= StringIO.new

  def generate(**options)
    Hanami::Auth::Generator.new(
      fs: Hanami::CLI::Files.new(stdout: out),
      inflector: Dry::Inflector.new,
      out:,
      app_namespace: "Bookshelf",
      **options
    ).tap(&:call)
  end

  def read(path) = File.read(path)

  def snapshot = Dir.glob("**/*", File::FNM_DOTMATCH).select { File.file?(_1) }.sort.to_h { [_1, File.read(_1)] }
end
