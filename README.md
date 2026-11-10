# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Stylesheets

Dart Sass compiles `app/assets/stylesheets/application.scss` into
`app/assets/builds/application.css`. Both layouts load Pico before this output.
Run `bin/rails dartsass:build` to build CSS, or `bin/rails dartsass:watch` while
editing. Asset precompilation invokes the Sass build automatically. Propshaft
excludes the SCSS input directory and serves the compiled build directory.

- `foundation/` owns Sass tokens, the Pico theme, and global base/content rules.
- `layout/` owns the shared site navigation.
- `components/` owns reusable controls, book cards, reviews, pagination, and reactions.
- `features/` owns page-specific styles; Admin, Book Clubs, Books, and My Log
  have subdirectories for their distinct screens.

Use Sass `@use`, with explicit namespaces when filenames overlap. A partial
that references `tokens.$ink`, for example, must load `foundation/tokens` itself
using the appropriate relative path. Tokens emit no CSS. Add new rules to the
module responsible for the component or screen; avoid duplicating tokens or
loading the same stylesheet through additional build entry points.

The entry point preserves the original CSS emission order. In particular,
Admin Catalog follows the workspace, Book Club layout overrides follow detail
and leaderboard, and global content rules and My Log library rules retain their
later positions. Do not move scattered overrides together without comparing
compiled CSS and checking affected screens. Keep responsive rules with their
owning module unless preserving the existing cascade requires a later module.
Store temporary comparison CSS and screenshots outside the repository.
