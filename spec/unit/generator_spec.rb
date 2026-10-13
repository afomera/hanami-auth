# frozen_string_literal: true

RSpec.describe Hanami::Auth::Generator do
  include AppSkeleton

  it "writes the authentication code into app/" do
    generate(test_framework: "rspec")

    expect(Dir.glob("app/**/*.rb").sort).to include(
      "app/authentication.rb",
      "app/authentication/password_reset_tokens.rb",
      "app/authentication/passwords.rb",
      "app/actions/session/new.rb",
      "app/actions/session/create.rb",
      "app/actions/session/destroy.rb",
      "app/actions/passwords/update.rb",
      "app/mailers/password_reset.rb",
      "app/operations/sign_in.rb",
      "app/operations/request_password_reset.rb",
      "app/operations/reset_password.rb",
      "app/relations/users.rb",
      "app/relations/sessions.rb",
      "app/repos/user_repo.rb",
      "app/repos/session_repo.rb",
      "app/structs/user.rb"
    )
    expect(Dir.glob("config/db/migrate/*.rb").map { File.basename(_1).sub(/\A\d+_/, "") })
      .to eq %w[create_users.rb create_sessions.rb]
    expect(File).to exist("spec/requests/authentication_spec.rb")
    expect(File).to exist("spec/support/authentication.rb")
    expect(Dir.glob("spec/operations/*.rb").sort)
      .to eq %w[spec/operations/request_password_reset_spec.rb spec/operations/reset_password_spec.rb spec/operations/sign_in_spec.rb]
  end

  it "generates Ruby that compiles" do
    generate(test_framework: "rspec", turbo: true)

    Dir.glob("**/*.rb").each do |path|
      expect { RubyVM::InstructionSequence.compile(read(path), path) }.not_to raise_error, path
    end
  end

  it "wires the app up" do
    generate

    expect(read("Gemfile")).to include %(gem "argon2", "~> 2.3"\ngem "dry-operation", ">= 1.0.1"\n\ngroup :development)
    expect(read("config/settings.rb")).to include "setting :session_secret"
    expect(read("config/app.rb")).to include "config.actions.sessions = :cookie", "secret: settings.session_secret"
    expect(read("app/action.rb")).to include "include Dry::Monads[:result]\n    include Authentication\n"
    expect(read("app/views/context.rb")).to include "def current_user", "def authenticated?"
    expect(read("config/routes.rb")).to include(
      "    resource :session, only: %i[new create destroy]\n",
      "    resources :passwords, only: %i[new create edit update]\n"
    )
    expect(read(".env.development")).to match(/^SESSION_SECRET=\h{128}$/)
    expect(read(".env.test")).to match(/^SESSION_SECRET=\h{128}$/)
  end

  it "adds only the gems that are missing" do
    File.write("Gemfile", read("Gemfile").sub(%(gem "sqlite3"\n), %(gem "sqlite3"\ngem "dry-operation"\n)))

    generate

    expect(read("Gemfile").scan("dry-operation").size).to eq 1
    expect(read("Gemfile")).to include %(gem "argon2")
  end

  it "creates the Operation base class when the app has none" do
    generate

    expect(read("app/operation.rb")).to include "class Operation < Dry::Operation"
    expect(read("app/operations/sign_in.rb")).to include "class SignIn < Bookshelf::Operation"
  end

  it "keeps an existing Operation base class" do
    AppSkeleton.write("app/operation.rb", "# mine\n")

    generate

    expect(read("app/operation.rb")).to eq "# mine\n"
  end

  it "adds Success and Failure to an action base class without them" do
    File.write("app/action.rb", read("app/action.rb").sub(/^.*Dry::Monads.*\n/, "").sub(%(require "dry/monads"\n), ""))

    generate

    expect(read("app/action.rb")).to include %(require "dry/monads"), "include Dry::Monads[:result]", "include Authentication"
  end

  it "reports a Gemfile change only when it adds the gem" do
    expect(generate.gemfile_changed?).to be true
    expect(generate.gemfile_changed?).to be false
  end

  it "changes nothing when run again" do
    generate(test_framework: "rspec")
    before = snapshot

    generate(test_framework: "rspec")

    expect(snapshot).to eq before
    expect(out.string).to include "Skipped app/authentication.rb (already exists)"
  end

  it "overwrites generated files with force, without duplicating injections or migrations" do
    generate
    File.write("app/authentication.rb", "changed")

    generate(force: true)

    expect(read("app/authentication.rb")).to include "module Authentication"
    expect(Dir.glob("config/db/migrate/*.rb").size).to eq 2
    expect(read("app/action.rb").scan("include Authentication").size).to eq 1
  end

  it "leaves existing session config alone, with a notice" do
    File.write("config/app.rb", read("config/app.rb").sub("class App < Hanami::App\n", "\\0    config.actions.sessions = :cookie, {secret: \"x\"}\n"))

    generate

    expect(read("config/app.rb").scan("config.actions.sessions").size).to eq 1
    expect(out.string).to include "Notice: config/app.rb already configures sessions"
  end

  it "names everything after a custom model" do
    generate(model: "admin", test_framework: "rspec")

    expect(File).to exist("app/relations/admins.rb")
    expect(File).to exist("app/relations/admin_sessions.rb")
    expect(read("app/repos/admin_session_repo.rb")).to include "class AdminSessionRepo", "admin_sessions.where(admin_id:)"
    expect(read("app/structs/admin.rb")).to include "class Admin < Bookshelf::DB::Struct"
    expect(read("app/authentication.rb")).to include "def current_admin(request)", %("repos.admin_session_repo")
    expect(read("app/views/context.rb")).to include "def current_admin"
    expect(Dir.glob("config/db/migrate/*.rb").map { File.basename(_1).sub(/\A\d+_/, "") })
      .to eq %w[create_admins.rb create_admin_sessions.rb]
    expect(File).to exist("spec/requests/admin_authentication_spec.rb")
  end

  it "generates into a slice, with slice routes and route names" do
    add_slice

    generate(model: "admin", slice: "admin", test_framework: "minitest")

    expect(read("slices/admin/authentication.rb")).to include "module Admin", "routes.path(:new_admin_session)"
    expect(read("slices/admin/operations/request_password_reset.rb")).to include "routes.url(:edit_admin_password"
    expect(read("slices/admin/action.rb")).to include "include Authentication"
    expect(read("slices/admin/operation.rb")).to include "module Admin", "class Operation < Dry::Operation"
    expect(read("slices/admin/operations/reset_password.rb")).to include "class ResetPassword < Admin::Operation", "admin_session_repo.delete_all_for_admin"
    expect(read("test/slices/admin/operations/sign_in_test.rb")).to include "class AdminSignInTest", %(Admin::Slice["operations.sign_in"])
    expect(read("config/routes.rb")).to include %(slice :admin, at: "/admin" do\n      resource :session)
    expect(read("test/slices/admin/requests/admin_authentication_test.rb"))
      .to include "class AdminAuthenticationTest < RequestTest", %(delete "/admin/session"), %(path: "/admin/session")
    expect(read("test/support/authentication.rb")).to include %(path: "/session")
    expect(Dir.glob("config/db/migrate/*admin*.rb").size).to eq 2
  end

  it "adds routes into an existing slice block" do
    add_slice
    File.write("config/routes.rb", read("config/routes.rb").sub("  end\nend", "\n    slice :admin, at: \"/backstage\" do\n    end\n  end\nend"))

    generator = generate(model: "admin", slice: "admin")

    expect(read("config/routes.rb")).to include %(slice :admin, at: "/backstage" do\n      resource :session)
    expect(read("config/routes.rb").scan("slice :admin").size).to eq 1
    expect(generator.sign_in_path).to eq "/backstage/session/new"
  end

  it "adds the Turbo Frame breakout only with hanami-turbo" do
    generate
    expect(read("app/templates/session/new.html.erb")).not_to include "turbo"
    expect(read("app/templates/layouts/app.html.erb")).not_to include "content_for"

    generate(turbo: true, force: true)
    expect(read("app/templates/session/new.html.erb")).to include "request.turbo_frame?", "turbo-visit-control"
    expect(read("app/actions/session/new.rb")).to include "response.flash.keep if request.turbo_frame?"
    expect(read("app/templates/layouts/app.html.erb")).to include "    <%= content_for :head %>\n  </head>"
  end

  it "skips tests when no test framework is given" do
    generate

    expect(Dir.exist?("spec")).to be false
    expect(Dir.exist?("test")).to be false
  end
end
