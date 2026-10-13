# frozen_string_literal: true

require "erb"
require "securerandom"

module Hanami
  module Auth
    # Writes the authentication code into an app or slice.
    #
    # Files under `templates/base/` are written relative to the app's `app/` dir or the slice's root;
    # `templates/migrate/` holds the migrations. Changes to existing files (Gemfile, settings, routes
    # and so on) are made by small, idempotent text injections, which skip any change already present.
    #
    # @api private
    class Generator
      TEMPLATES = File.join(__dir__, "templates")

      DEFAULT_MODEL = "user"

      # Gems the generated code needs, added to the Gemfile when missing.
      GEMS = {
        "argon2" => %(gem "argon2", "~> 2.3"),
        "dry-operation" => %(gem "dry-operation", ">= 1.0.1")
      }.freeze

      TEST_FRAMEWORKS = {"rspec" => "spec", "minitest" => "test"}.freeze

      ROUTES = <<~RUBY
        resource :session, only: %i[new create destroy]
        resources :passwords, only: %i[new create edit update]
      RUBY

      attr_reader :fs, :inflector, :out, :app_namespace, :slice

      # @param model [String] the singular name of the authenticated model, e.g. "user" or "admin"
      # @param test_framework [String, nil] "rspec", "minitest", or nil to skip tests
      def initialize(fs:, inflector:, out:, app_namespace:, model: DEFAULT_MODEL, slice: nil, force: false,
                     test_framework: nil, turbo: false)
        @fs = fs
        @inflector = inflector
        @out = out
        @app_namespace = app_namespace
        @model = inflector.underscore(inflector.singularize(model))
        @slice = slice
        @force = force
        @test_framework = test_framework
        @turbo = turbo
        @gemfile_changed = false
      end

      def call
        generate_files
        generate_migrations
        generate_tests if test_framework

        inject_gems
        ensure_operation_base
        ensure_result_monads
        inject_settings
        inject_session_secrets
        inject_sessions_config
        inject_action_include
        inject_view_context
        inject_routes
        inject_layout_head if turbo?
      end

      def gemfile_changed? = @gemfile_changed

      def print_next_steps
        out.puts <<~TEXT

          Authentication generated. Next:

            1. Run the migrations:   bundle exec hanami db migrate
            #{"2. Create #{model.match?(/\A[aeiou]/) ? "an" : "a"} #{model}:".ljust(25)}bundle exec hanami console
                                     > #{container}["repos.#{model}_repo"].create(email_address: "you@example.com", password: "a long password")
            3. Sign in at #{sign_in_path}

          Every #{namespace} action now requires a signed-in #{model}. Opt an action out with:

            class Home < #{namespace}::Action
              allow_unauthenticated_access
            end

          In production, set SESSION_SECRET (at least 64 characters; generate one with
          `ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'`) and configure SMTP for password reset emails.
        TEXT
      end

      # Template context

      def namespace = slice? ? inflector.camelize(slice) : app_namespace
      def slice? = !slice.nil?
      def turbo? = @turbo
      def force? = @force
      attr_reader :test_framework

      # Model naming. The default "user" model keeps plain names (`users`, `sessions`); any other
      # model prefixes its sessions table (`admins`, `admin_sessions`), so it can sit alongside users.
      attr_reader :model
      def models = inflector.pluralize(model)
      def model_class = inflector.camelize(model)
      def models_class = inflector.camelize(models)
      def foreign_key = "#{model}_id"
      def sessions_table = model == DEFAULT_MODEL ? "sessions" : "#{model}_sessions"
      def sessions_class = inflector.camelize(sessions_table)
      def session_repo = "#{inflector.singularize(sessions_table)}_repo"
      def session_repo_class = inflector.camelize(session_repo)

      # Prefixes minitest class names so tests for several models or slices don't collide.
      def test_class_prefix = [(namespace if slice?), (model_class unless model == DEFAULT_MODEL)].compact.uniq.join

      # Where the generated components are resolved from, in tests and the console.
      def container = slice? ? "#{namespace}::Slice" : "Hanami.app"

      # URL paths, for tests and messages.
      def path_prefix
        return "" unless slice?

        routes = fs.exist?("config/routes.rb") ? fs.read("config/routes.rb") : ""
        routes[/^\s*slice :#{slice}\b.*?at: ["']([^"']*)["']/, 1]&.chomp("/") || "/#{slice}"
      end

      def sign_in_path = "#{path_prefix}/session/new"
      def session_path = "#{path_prefix}/session"
      def new_password_path = "#{path_prefix}/passwords/new"
      def passwords_path = "#{path_prefix}/passwords"

      # Extra arguments for the test helper's `sign_in_as`, which defaults to the app's sign-in path.
      def sign_in_args = slice? ? %(, path: "#{session_path}") : ""

      # Returns the route name for use in templates. Routes inside a `slice` block take the slice name
      # after any `new_`/`edit_` prefix: `new_session` becomes `new_admin_session`.
      def route(name)
        return name.to_sym unless slice?

        action, base = name.to_s.match(/\A(?:(new|edit)_)?(.+)\z/).captures
        [action, slice, base].compact.join("_").to_sym
      end

      def env_key = "#{inflector.underscore(namespace)}.authentication.session"

      def cookie_key = "#{inflector.underscore(app_namespace)}.session"

      private

      def base_path = slice? ? fs.join("slices", slice) : "app"

      # The app's own files (settings, app config) always live at the root.
      def app_file(*path) = fs.join(*path)

      def generate_files
        each_template("base") do |relative_path, source|
          create(fs.join(base_path, expand_path(relative_path)), render(source))
        end
      end

      def generate_migrations
        dir = migrations_dir
        timestamp = Time.now # local time, as `hanami generate migration` uses

        {"create_models" => "create_#{models}", "create_sessions" => "create_#{sessions_table}"}
          .each_with_index do |(template, name), index|
            existing = Dir.glob(File.join(dir, "*_#{name}.rb")).first
            if existing && !force?
              skipped(existing)
              next
            end

            version = (timestamp + index).strftime("%Y%m%d%H%M%S")
            path = existing || fs.join(dir, "#{version}_#{name}.rb")
            write(path, render(read_template("migrate/#{template}.rb.erb")))
          end
      end

      # Slices with their own DB config keep their own migrations; otherwise migrations are shared
      # with the app.
      def migrations_dir
        slice_db = fs.join(base_path, "config", "db")
        slice? && fs.directory?(slice_db) ? fs.join(slice_db, "migrate") : fs.join("config", "db", "migrate")
      end

      def generate_tests
        root = TEST_FRAMEWORKS.fetch(test_framework)

        each_template(test_framework) do |relative_path, source|
          relative_path = relative_path.sub("authentication_", "#{model}_authentication_") unless model == DEFAULT_MODEL
          shared = relative_path.start_with?("support/")
          path = slice? && !shared ? fs.join(root, "slices", slice, relative_path) : fs.join(root, relative_path)
          create(path, render(source))
        end
      end

      def inject_gems
        update("Gemfile") do |content|
          missing = GEMS.reject { |name, _| content.match?(/^\s*gem ["']#{name}["']/) }.values
          next if missing.empty?

          @gemfile_changed = true
          lines = missing.join("\n")
          insert_before_first(content, /^group /, "#{lines}\n\n") || "#{content.chomp}\n\n#{lines}\n"
        end
      end

      # The generated operations subclass the app's (or slice's) Operation, which `hanami new` and
      # `hanami generate slice` only create when dry-operation was already bundled.
      def ensure_operation_base
        path = fs.join(base_path, "operation.rb")
        return if fs.exist?(path)

        parent = slice? && fs.exist?(app_file("app", "operation.rb")) ? "#{app_namespace}::Operation" : "Dry::Operation"
        write(path, render(read_template("operation.rb.erb")).sub("PARENT", parent))
      end

      # Actions pattern match on operation results with `Success` and `Failure`. `hanami new` includes
      # them in the app's base action when dry-operation is bundled; add them if not.
      def ensure_result_monads
        path = app_file("app", "action.rb")

        update(path) do |content|
          next if content.include?("Dry::Monads[:result]")

          class_line = content.match(/^(\s*)class Action < Hanami::Action.*$/) or next missing("#{app_namespace}::Action class")
          indent = "#{class_line[1]}  "
          content = content.dup.insert(class_line.end(0), "\n#{indent}# Provide `Success` and `Failure` for pattern matching on operation results\n#{indent}include Dry::Monads[:result]\n")
          content.sub(/^require "hanami\/action"\n/) { "#{_1}require \"dry/monads\"\n" }
        end
      end

      def inject_settings
        update(app_file("config", "settings.rb")) do |content|
          next if content.include?("setting :session_secret")

          setting = <<~RUBY.gsub(/^/, "    ")
            # Signs and encrypts the session cookie, and signs password reset tokens.
            setting :session_secret, constructor: Types::String.constrained(min_size: 64)
          RUBY

          insert_into_class(content, /class Settings < Hanami::Settings/, setting)
        end
      end

      def inject_session_secrets
        %w[development test].each do |env|
          path = app_file(".env.#{env}")
          content = fs.exist?(path) ? fs.read(path) : ""
          next if content.match?(/^SESSION_SECRET=/)

          line = "SESSION_SECRET=#{SecureRandom.hex(64)}\n"
          header = content.empty? ? "# Local #{env} secret only. Set your own SESSION_SECRET in production.\n" : ""
          fs.write(path, "#{content}#{"\n" unless content.empty? || content.end_with?("\n")}#{header}#{line}")
        end
      end

      def inject_sessions_config
        update(app_file("config", "app.rb")) do |content|
          if content.match?(/config\.actions\.sessions\s*=/)
            next if content.include?("settings.session_secret")

            notice "config/app.rb already configures sessions; make sure they're enabled with a secret."
            next
          end

          sessions = <<~RUBY.gsub(/^/, "    ")
            config.actions.sessions = :cookie, {
              key: "#{cookie_key}",
              secret: settings.session_secret,
              expire_after: 60 * 60 * 24 * 30, # 30 days
              same_site: "Lax",
              httponly: true,
              secure: Hanami.env?(:production)
            }
          RUBY

          insert_into_class(content, /class App < Hanami::App/, sessions)
        end
      end

      def inject_action_include
        update(fs.join(base_path, "action.rb")) do |content|
          next if content.match?(/^\s*include Authentication\b/)

          class_line = content.match(/^(\s*)class Action < .*$/) or next missing("#{namespace}::Action class")
          indent = "#{class_line[1]}  "

          # Place it after the class's existing includes, if it has any.
          rest = content[class_line.end(0)..]
          last_include = rest.to_enum(:scan, /^#{indent}include .*$/).map { Regexp.last_match }.last
          offset = class_line.end(0) + (last_include ? last_include.end(0) : 0)

          content.dup.insert(offset, "\n#{indent}include Authentication")
        end
      end

      def inject_view_context
        update(fs.join(base_path, "views", "context.rb")) do |content|
          next if content.include?("def current_user")

          methods = render(read_template("context_methods.rb.erb")).gsub(/^(?=.)/, "      ")
          insert_into_class(content, /class Context < /, methods, at: :bottom)
        end
      end

      def inject_routes
        slice_routes = fs.join(base_path, "config", "routes.rb")

        if slice? && !fs.exist?(slice_routes)
          inject_slice_routes_block
        else
          path = slice? ? slice_routes : app_file("config", "routes.rb")
          update(path) do |content|
            next if content.match?(/resource :session\b/)

            insert_into_class(content, /class Routes < Hanami::Routes/, ROUTES.gsub(/^/, "    "), at: :bottom)
          end
        end
      end

      def inject_slice_routes_block
        update(app_file("config", "routes.rb")) do |content|
          block = content.match(/^(\s*)slice :#{slice}\b.*do\s*$/)

          if block
            body = content[block.end(0)..]
            next if body[/\A.*?^#{block[1]}end\b/m].to_s.match?(/resource :session\b/)

            close = body.index(/^#{block[1]}end\b/)
            content.dup.insert(block.end(0) + close, ROUTES.gsub(/^/, "#{block[1]}  "))
          else
            next if content.match?(/slice :#{slice}\b/)

            routes = "slice :#{slice}, at: \"/#{slice}\" do\n#{ROUTES.gsub(/^/, "  ")}end\n"
            insert_into_class(content, /class Routes < Hanami::Routes/, routes.gsub(/^(?=.)/, "    "), at: :bottom)
          end
        end
      end

      def inject_layout_head
        layout = fs.join(base_path, "templates", "layouts", "app.html.erb")
        layout = app_file("app", "templates", "layouts", "app.html.erb") unless fs.exist?(layout)

        update(layout) do |content|
          next if content.include?("content_for :head") || content.include?("content_for(:head)")

          insert_before_first(content, %r{^(\s*)</head>}) { |m| "#{m[1]}  <%= content_for :head %>\n" } ||
            missing("</head> in #{layout}")
        end
      end

      # Helpers

      def each_template(dir)
        root = File.join(TEMPLATES, dir)
        Dir.glob("**/*.erb", base: root).sort.each do |relative|
          yield relative.delete_suffix(".erb"), File.read(File.join(root, relative))
        end
      end

      def read_template(path) = File.read(File.join(TEMPLATES, path))

      # Expands `%name%` placeholders in template paths, e.g. `repos/%model%_repo.rb`.
      def expand_path(path) = path.gsub(/%(\w+)%/) { public_send(Regexp.last_match(1)) }

      def render(source)
        ERB.new(source, trim_mode: "-").result(binding)
      end

      def create(path, content)
        if fs.exist?(path) && !force?
          skipped(path)
        else
          write(path, content)
        end
      end

      def write(path, content) = fs.write(path, content)

      # Yields a file's content; writes the returned string, if any.
      def update(path)
        unless fs.exist?(path)
          missing(path)
          return
        end

        original = fs.read(path)
        updated = yield(original)
        fs.write(path, updated) if updated.is_a?(String) && updated != original
      end

      # Inserts lines just inside a class body: at the top (after the class line) or bottom (before
      # its matching `end`).
      def insert_into_class(content, class_pattern, lines, at: :top)
        match = content.match(/^(\s*)#{class_pattern}.*$/) or return missing(class_pattern.source)
        indent = match[1]

        if at == :top
          # Keep a blank line before any existing body, but none before the class's closing `end`.
          empty_class = content[match.end(0)..].match?(/\A\n#{indent}end\b/)
          content.dup.insert(match.end(0), "\n#{lines.chomp}#{"\n" unless empty_class}")
        else
          close = content.index(/^#{indent}end\b/, match.end(0)) or return missing("end of #{class_pattern.source}")
          before = content[0...close]
          separator = before.end_with?("\n\n") || before.match?(/^\s*#{class_pattern}.*\n\z/) ? "" : "\n"
          content.dup.insert(close, "#{separator}#{lines.chomp}\n")
        end
      end

      def insert_before_first(content, pattern, text = nil)
        match = content.match(pattern) or return
        text = yield(match) if block_given?
        content.dup.insert(match.begin(0), text)
      end

      def skipped(path) = out.puts("Skipped #{path} (already exists)")

      def notice(message) = out.puts("Notice: #{message}")

      def missing(what)
        out.puts "Warning: couldn't find #{what}; skipping that change. See the hanami-auth README to make it by hand."
        nil
      end
    end
  end
end
