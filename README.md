# hanami-auth

`hanami generate auth` adds session-based sign in, sign out, and password reset by email to your
Hanami app.

The generated code lives in your app:

- operations for sign in and password reset
- thin actions that pattern match on their results
- views, templates, relations, repos, and a mailer
- a small `Authentication` mixin

Read it, change it, and own it. Your app doesn't need this gem at runtime.

## Installation

Add the gem to the `:cli` group, which the `hanami` command loads:

```ruby
# Gemfile
group :cli, :development do
  gem "hanami-auth"
end
```

Then:

```
bundle install
bundle exec hanami generate auth
bundle exec hanami db migrate
```

Create your first user from `bundle exec hanami console`:

```ruby
app["repos.user_repo"].create(email_address: "you@example.com", password: "a long password")
```

## What you get

- **Sign in and sign out**, at `/session/new` and `DELETE /session`. Sessions live in a `sessions`
  table, so you can list and revoke them. The cookie holds a random token, and the table stores only
  its SHA-256 digest.
- **Password reset** at `/passwords/new`. A mailer sends a signed link that expires after 15 minutes
  and works once, because changing the password invalidates it. A reset also signs that user out
  everywhere. In development, the link is logged too.
- **Operations**: `operations.sign_in`, `operations.request_password_reset` and
  `operations.reset_password` hold the logic, so you can reuse them outside HTTP, for example in an
  API slice or a console task. The generator adds `dry-operation` if your app doesn't bundle it.
- **Argon2id** password hashing (adds the `argon2` gem). Sign in doesn't reveal whether an account
  exists, either in its responses or its timing.
- **Every action requires sign in** by default, through `include Authentication` in your base
  `Action`. Opt out per action:

  ```ruby
  class Show < Bookshelf::Action
    allow_unauthenticated_access
  end
  ```

- **Helpers.** Actions get `current_user(request)`, `authenticated?(request)`,
  `start_new_session_for(request, user)` and `terminate_session(request)`. Views get `current_user`
  and `authenticated?`.
- **Cookie sessions**, configured in `config/app.rb` with a `session_secret` setting.
  `.env.development` and `.env.test` get generated secrets; set `SESSION_SECRET` (64+ characters)
  in production.
- **Request and operation tests** for rspec or minitest, whichever your app bundles, plus a
  `sign_in_as(user, password:)` helper.
- **Turbo-friendly** responses: 303 redirects and 422 re-renders. With
  [hanami-turbo](https://github.com/afomera/hanami-turbo) bundled, a Turbo Frame that hits an expired
  session becomes a full-page visit to sign in.

There's no sign-up form, and no sign-out button (layouts vary). Add the button where it fits:

```erb
<%= form_for routes.path(:session), method: :delete do |f| %><%= f.submit "Sign out" %><% end %>
```

## Options

```
hanami generate auth [NAME] [--slice=NAME] [--skip-install] [--skip-tests] [--force]
```

| Command                                   | Generates                                                        |
|-------------------------------------------|------------------------------------------------------------------|
| `hanami generate auth`                    | `users` + `sessions`, into `app/`                                |
| `hanami generate auth admin`              | `admins` + `admin_sessions`, `current_admin`, into `app/`        |
| `hanami generate auth admin --slice=admin`| The same, into `slices/admin/`, with routes under the slice      |

| Option           | Effect                                                    |
|------------------|-----------------------------------------------------------|
| `--skip-install` | Adds `argon2` to the Gemfile without running `bundle install`. |
| `--skip-tests`   | Skips the generated tests.                                |
| `--force`        | Overwrites generated files.                               |

Re-running is safe: existing files are skipped, and each change to an existing file is made once.

## Example

[hanami-auth-example](https://github.com/afomera/hanami-auth-example) is a small notes app on Hanami
main that runs this generator. Its git history shows exactly what the generator wrote.

## License

MIT
