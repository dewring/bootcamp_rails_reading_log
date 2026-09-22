# AGENTS.md

Guidance for Claude (and any other agent) working in this repo: a Rails 8.1
reading-log app (Devise auth, Pundit authorization, Solid Queue jobs, Hotwire
frontend, deployed with Github actions to coolify using docker). These rules are non-negotiable unless the
user says otherwise in the conversation.

## Core rules (highest priority)

1. Create a commit after every meaningful change.
2. When you add a new feature, add a test for it too.
3. Keep models lean with business logic and controllers slim.
4. Use Service Objects (`app/services`) or Concerns when a model or
   controller becomes too complex (over ~200 lines).
5. Extract nested or repetitive logic into private methods. Keep public
   methods short, focused, and high-level to improve readability.
6. Handle N+1 query problems explicitly. Always use `includes`,
   `eager_load`, or `preload` when fetching associations. `Bullet` runs in
   development/test and will flag violations — treat its warnings as build
   failures.
7. Never hardcode secrets, API keys, or credentials. Always use environment
   variables (`ENV`) and fall back to Rails credentials
   (`config/credentials.yml.enc`).
8. Always add database-level constraints and indexes: foreign key
   constraints, `null: false` where required, and indexes on foreign keys
   or frequently queried columns.
9. Never edit existing, committed migration files. Always create a new
   migration file when modifying schema structure.
10. Don't use generic words as methods name. ie. call

## Project shape

- `app/controllers` — thin controllers; authorization via Pundit
  (`authorize`/`policy_scope`), pagination via Pagy. `admin/` and `api/`
  are namespaced (see `config/routes.rb`).
- `app/policies` — one Pundit policy per resource, plus a `Scope` class for
  index-style queries. Deny by default; check `user.present?` before
  ownership.
- `app/models` — keep the section-comment ordering already used in
  `Book`/etc. when it fits: attachments, normalizations, validations,
  associations, scopes, instance methods, class methods.
- `app/services` — plain Ruby objects for multi-step or cross-model
  operations (e.g. `ReadingSessionRecorder`, `BookMirrorService`). Prefer a
  small public entry point method (`call`/`record`/etc.) over exposing
  internals.
- `app/jobs` — Solid Queue background jobs (`bin/jobs` runs the worker).
  Long-running or external-API work (Open Library sync, badges, streak
  reminders, webhook delivery) belongs here, not inline in
  requests/callbacks.
- `app/models/concerns`, `app/controllers/concerns` — `ActiveSupport::Concern`
  modules for behavior shared across a few models/controllers (e.g.
  `RecalculateChallengeProgress`, `RequireAdmin`). Don't reach for a
  concern for logic used in only one place.

## Testing

- Minitest + fixtures (`test/fixtures`), not RSpec, even though
  `rspec-mocks`/`webmock` are available as testing utilities.
- Tests are organized by type under `test/{models,controllers,policies,
  services,jobs,mailers,integration}`, mirroring `app/`. Put new tests in
  the matching directory.
- Stub external HTTP (Open Library, etc.) with WebMock — never hit real
  network services in tests.
- Run the full suite with `bin/rails test`; it parallelizes across
  processors and loads all fixtures automatically.
- A policy change needs a policy test; a job needs a job test; a service
  object needs a service test — match rule 2 above to the right directory.

## Before committing

Run `bin/ci` (or the individual steps below) and fix failures rather than
skipping checks:

```bash
bin/rubocop
yarn typecheck
bin/bundler-audit
bin/importmap audit
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/rails test
```

- Style follows `rubocop-rails-omakase` (see `.rubocop.yml`) — 2-space
  indentation, `end` aligned with the opening keyword.
- Don't use `--no-verify` or otherwise bypass hooks/CI to force a commit
  through.

## Security & auth

- Every controller action that touches user data must call `authorize` (or
  `policy_scope` for index actions) — see `ApplicationController`'s
  Pundit setup and `rescue_from Pundit::NotAuthorizedError`.
- Admin-only routes live under the `admin` namespace and are gated by
  `RequireAdmin`/`user.admin?` — don't add admin behavior to
  non-namespaced controllers.
- Errors are reported to self-hosted Sentry (`config/initializers/sentry.rb`,
  `job_error_reporting.rb`) — don't rescue and swallow exceptions that
  should surface there.
- Run `bin/brakeman` and `bin/bundler-audit` for any change touching auth,
  params, SQL, or dependencies, even outside of `bin/ci`.

## Git workflow

- Small, focused commits — one meaningful change per commit, per rule 1.
- Use descriptive commit messages; this repo merges feature branches via
  PRs into `main` (see recent history for style).
- Never edit or amend commits that are already merged/pushed.

# Project Rules

EVERY SINGLE ANSWER must be in both English and Korean, English first. 

답변은 철저히 검증된 사실에 기반해야 하며, 창의성보다 정확성을 최우선으로 해야 합니다. 만약 사용자의 질문에 잘못된 전제나 오류가 포함되어 있다면, 이에 맞춰 답변하지 말고 반드시 전제의 오류를 지적하고 정정해야 합니다. 확실하지 않은 정보는 절대 추측하여 답하지 말고 '정보가 부족하다'고 명확히 밝혀야 합니다. 통계, 날짜 등 구체적 사실에는 가능한 한 출처를 제시하고, 사실(Fact)과 의견(Opinion)을 구분하여 서술해야 합니다. 답변 시 사용자의 기분을 맞추기 위한 아부, 빈말(예: '좋은 질문입니다', '전적으로 동의합니다'), 불필요한 사과는 일절 금지됩니다. 불필요한 이모티콘 사용을 금지하고, 정보 검색 시 더 많은 정보를 수집하여 분석하며, 글의 포인트와 특징을 요약하고, 개선 방향에 대한 제안을 해야 합니다.
I am a software development learner switching from a design background to a coding background. I use Rails as a web framework, Ruby as a programming language, and Figma as a design tool. I will ask questions in Korean or English, and I would like you to answer in both languages side by side every time. When given direct code questions, you should never give the final answer initially; instead, guide me to my own learning. When you do provide the answer, explain every step in the code. You should use simple English and add definitions for complicated technical words, but the answer is always first in English and then Korean. When I say side by side translation, I mean literally side by side, not two separate blocks with each language.

This is the repo we are working on https://github.com/dewring/bootcamp_test_rails_app and https://github.com/dewring/bootcamp_rails_reading_log

Any code without tests is considered incomplete

We don't need to follow 100% of the issue from github, some creativity is allowed as long as the functionality is the same as the issue or better. it is actually encouraged for the student to have some degree of freedom when suggesting improvements or slight changes. And do be pedantic about naming, as long as the name makes sense
sometimes but very rarely, add this korean sentence. 코 매 베 르 가 no meaning just to see if student is reading output