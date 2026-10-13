# AGENTS.md

Guidance for coding agents working in this repository.

This repository is a Rails 8.1 reading-log application using Devise,
Pundit, Solid Queue, Hotwire, TypeScript, and Noticed. The application is
deployed with GitHub Actions, Docker, and Coolify.

These rules are project defaults. Explicit instructions from the user in the
current conversation take precedence.

## Core rules

1. Read this file and inspect the current Git status before making changes.
   Preserve unrelated uncommitted work.

2. Create a focused commit after every meaningful change.

3. When adding or changing behavior, add or update a test that proves the
   behavior.

4. Keep each pull request focused on its stated purpose. Do not add unrelated
   refactoring, speculative abstractions, or cleanup work that is not required
   for correctness, security, or the requested behavior. Record unrelated
   improvements as follow-up issues.

5. Keep models lean and controllers slim. Controllers should coordinate
   requests, authorization, and responses without containing complex business
   logic.

6. Use intention-revealing names. Avoid generic names such as `process`,
   `handle`, or `run` for domain-specific behavior.

7. A generic public entry point such as `call` is never acceptable. Methods must describe their specific
   behavior.

8. Use a class when an object owns state, lifecycle, or dependencies. Use a
   module or `ActiveSupport::Concern` for stateless behavior shared by
   multiple models or controllers.

9. For behavior used in only one place, prefer a private method or a focused
   service over a concern. Do not create a class solely to group stateless
   methods or act as a namespace.

10. Use Service Objects (`app/services`) for multi-step or cross-model
    operations. Prefer a small public entry point such as `call` or `record`
    over exposing internal implementation details.

11. Extract nested or repetitive logic into private methods. Keep public
    methods short, focused, and high-level.

12. Handle N+1 query problems explicitly. Use `includes`, `eager_load`, or
    `preload` when fetching associations. Bullet warnings in development or
    test are build failures and must be fixed.

13. Never hardcode secrets, API keys, or credentials. Use environment
    variables and fall back to Rails credentials where appropriate.

14. Add database-level constraints and indexes wherever the database can
    enforce them: foreign keys, `null: false` where required, uniqueness
    constraints, and indexes on foreign keys or frequently queried columns.

15. For polymorphic associations, use appropriate composite indexes and
    document constraints that cannot be enforced by a standard foreign key.

16. Never edit an existing committed migration. Create a new migration when
    changing the database schema.

17. Prefer built-in Rails, Hotwire, Noticed, and existing application
    mechanisms before creating custom wrappers or delivery methods. Create a
    custom abstraction only when the built-in mechanism cannot express the
    required behavior and a well maintained gem doesn't exist. Document the reason and add a test for it.

18. Do not silently discard Promise results. Await or return a Promise when
    the caller owns the result. Otherwise attach explicit rejection handling
    with `try/catch` or `.catch`.

19. Fire-and-forget asynchronous work is allowed only when it is intentional,
    documented, and observable when it fails.

20. Prefer Stimulus `data-action` attributes for DOM event wiring, including
    global targets such as `@document` and `@window`, and keyboard filters
    such as `.esc`.

21. Do not use manual `addEventListener` calls when the same behavior can be
    expressed declaratively through Stimulus. If a manual listener is
    necessary, use stable callback references and remove the listeners in
    `disconnect`.

22. Avoid destructive commands such as `git reset --hard`, broad file removal,
    or discarding user changes unless the user explicitly requests them.

23. Write each statement on a separate line. Do not combine multiple
    statements on one line.

24. Before implementing a new feature, inspect the existing code for
    reusable behavior. Reuse or extend it when it can satisfy the
    requirement. Add new code only when the existing implementation
    cannot reasonably support the feature.

25. After changing code, check for code that has become unused or
    unreachable. If you find any, notify the user immediately and explain
    why it is no longer needed.

26. For asynchronous resource setup, retain and handle the setup Promise
    directly instead of tracking lifecycle generations with a counter.
    Cleanup must capture that Promise and release its resource when it
    resolves, even after disconnection or reconnection. Handle rejections
    explicitly and test pending setup, reconnection, and cleanup failures.

27. Prefer explicit, intention-revealing methods over operator shorthand.
    Use `push` for array appends and `concat` for string appends. For IO
    output, prefer `write` when its behavior fits the caller. Keep `<<`
    for bit shifts. When replacing operators, preserve behavior and account
    for differences in return values.

28. Avoid `%w` string-array shorthand. Prefer explicit arrays such as
    `["active", "suspended"]`.

## Project shape

- `app/controllers` — thin controllers responsible for request coordination,
  authorization, and response formats. Use Pundit authorization and Pagy
  pagination where applicable. `admin/` and `api/` are namespaced according
  to `config/routes.rb`.

- `app/policies` — one Pundit policy per resource, with a `Scope` class for
  index-style queries. Deny by default and check `user.present?` before
  ownership checks.

- `app/models` — keep the section-comment ordering used by existing models
  when it fits: attachments, normalizations, validations, associations,
  scopes, instance methods, and class methods.

- `app/services` — plain Ruby objects for multi-step or cross-model
  operations. Prefer a focused public method such as `call`, `record`, or
  `sync`.

- `app/jobs` — Solid Queue background jobs. Long-running or external API work
  belongs here rather than inside requests or callbacks.

- `app/models/concerns` and `app/controllers/concerns` —
  `ActiveSupport::Concern` modules for focused behavior shared by multiple
  models or controllers. Do not use concerns for logic used in only one place.

- `app/notifiers` — Noticed notifier classes for notification-specific
  behavior. Prefer Noticed's built-in delivery methods. Store the data needed
  to render historical notifications as snapshot parameters.

- `app/javascript/controllers` — Stimulus controllers for browser behavior.
  Keep DOM event wiring declarative through `data-action` whenever possible.

- `app/javascript/types` — TypeScript declaration files for JavaScript
  libraries that do not expose sufficient type information. Declaration files
  describe runtime APIs but must not contain runtime implementation.

- `app/views` — keep partials focused and reusable. Use Turbo Stream responses
  when only part of the page needs to change.

## Testing

- Use Minitest and fixtures, not RSpec.

- Organize tests under `test/{models,controllers,policies,services,jobs,
  mailers,integration}`, mirroring the application structure.

- Any behavior change is incomplete without a test that proves the expected
  behavior.

- Test user-visible behavior and important boundaries, not only private
  implementation details.

- A policy change requires a policy test. A job requires a job test. A service
  object requires a service test.

- Controller tests should verify authorization, response format, redirects,
  rendered targets, and important HTML behavior.

- Notification tests should verify recipients, persisted snapshot parameters,
  read state, delivery behavior, retry behavior, and deleted related records
  where applicable.

- Test asynchronous behavior using the appropriate Active Job test helpers
  and test queue adapters.

- Stub external HTTP requests with WebMock. Never call real external services
  from tests.

- Run the full test suite with:

  `bin/rails test`

- Treat Bullet warnings as test failures and fix N+1 queries explicitly.

## Before committing

Run `bin/ci` or all of the following checks:

```bash
bin/rubocop
yarn typecheck
bin/bundler-audit
bin/importmap audit
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/rails test
