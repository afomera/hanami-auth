# Changelog

## [Unreleased]

### Added

- `hanami generate auth [NAME] [--slice=NAME]`: session-based sign in, sign out, and password reset by
  email, written into the app. Argon2id passwords, database-backed sessions, signed single-use reset
  tokens, dry-operation operations behind thin actions, request and operation tests for rspec or minitest, and Turbo Frame handling with hanami-turbo.
