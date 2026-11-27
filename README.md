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

## Reading activity simulator / 독서 활동 시뮬레이터

Run the simulator once for each new round of reading activity. In development, `bin/rails db:seed` runs the same simulator.

시뮬레이터를 실행할 때마다 새로운 독서 활동이 추가된다. 개발 환경에서는 `bin/rails db:seed`도 같은 시뮬레이터를 실행한다.

```sh
bin/rails development_scenario:simulate_reading
```

| English | 한국어 |
| --- | --- |
| Set `DEVELOPMENT_SCENARIO_PASSWORD` to a strong password for new demo accounts. The simulator uses the committed Open Library snapshot and reserved `@example.test` logins. | 새 시연 계정에 사용할 안전한 비밀번호를 `DEVELOPMENT_SCENARIO_PASSWORD`에 설정한다. 커밋된 Open Library 스냅샷과 `@example.test` 전용 로그인 주소를 사용한다. |
| Each run reuses the catalog, demo accounts, clubs, genres, badges and challenges. Each available demo reader logs a session today and can add one review and one reaction on books they have yet to review or react to. Each available club gets a discussion post. Keep the normal worker running for callbacks. | 카탈로그, 계정, 클럽, 장르, 배지, 챌린지는 재사용한다. 실행할 때마다 사용 가능한 독자별로 오늘 날짜의 독서 기록을 추가하고, 아직 리뷰하거나 반응하지 않은 책에 리뷰와 반응을 하나씩 추가한다. 사용 가능한 클럽에는 토론 글을 하나씩 추가한다. 후속 작업을 위해 워커를 실행한다. |
| The report shows static record counts, activity added in this run, and reasons for skipped records. If every book already has a review or reaction from a reader, their sessions and club discussions can still grow. Running again after a partial run adds another round. | 결과에는 정적 데이터 수, 이번 실행에서 추가한 활동 수, 건너뛴 이유가 표시된다. 모든 책에 이미 리뷰나 반응이 있어도 독서 기록과 토론은 계속 추가된다. 일부만 완료된 뒤 다시 실행하면 새로운 활동 회차가 추가된다. |
| In production, set `ALLOW_PRODUCTION_SCENARIO=true` and run the task above inside the application container, or use the console command below. Keep `/rails/storage` persistent between runs. Existing manifests retain ownership information and the original challenge reference date. Unset the flag after use. | 운영 환경에서는 `ALLOW_PRODUCTION_SCENARIO=true`를 설정한 뒤 앱 컨테이너에서 위 태스크 또는 아래 콘솔 명령을 실행한다. `/rails/storage`를 영속 저장소로 유지한다. 기존 manifest의 소유 정보와 챌린지 기준일은 유지된다. 사용 후 허용 설정을 해제한다. |

```ruby
pp DevelopmentReadingScenario.new.seed_scenario
```

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
