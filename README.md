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

## Production demo data / 프로덕션 시연 데이터

| English | 한국어 |
| --- | --- |
| Reuse the committed `db/seeds/open_library_catalog.json` snapshot. Catalog capture remains development-only. | 커밋된 카탈로그 스냅샷을 재사용하며 새 카탈로그 수집은 개발 환경에서만 실행한다. |
| In the production application's environment, set `ALLOW_PRODUCTION_SCENARIO=true`, a strong `DEVELOPMENT_SCENARIO_PASSWORD`, and `READING_SCENARIO_AS_OF` to one recent ISO 8601 timestamp with a UTC offset, for example `2026-11-16T20:00:00Z`. Choose the time once and keep it unchanged on every replay. | 운영 앱 환경에 명시적 허용 설정, 안전한 시연 계정 비밀번호, 시간대가 포함된 최근 기준 시각을 설정한다. 기준 시각은 한 번 정하고 재실행 시 유지한다. |
| Without a configured reference time, the existing development baseline remains October 30, 2026. A different reference time from the saved manifest is rejected; do not delete the manifest to bypass that check. | 기준 시각 미설정 시 기존 개발 기준일인 2026년 10월 30일을 사용한다. 저장된 manifest와 시각이 다르면 거부하므로 검사를 우회하려고 manifest를 삭제하지 않는다. |
| Keep `/rails/storage` on persistent storage in Docker/Coolify. Preserve `storage/development_scenarios/reading_scenario.json` and its lock file across restarts and deployments. Execute scenario commands on one application instance using that same storage. | Docker/Coolify의 `/rails/storage`를 영속 저장소로 유지한다. manifest와 잠금 파일을 재시작·배포 후에도 보존하고 같은 저장소를 사용하는 앱 인스턴스 한 곳에서 명령을 실행한다. |

With those settings present, run inside the production application container:
위 설정을 적용한 프로덕션 앱 컨테이너 안에서 실행한다:

```bash
RAILS_ENV=production bin/rails console
```

In the Rails console / Rails 콘솔에서:

```ruby
demo = DevelopmentReadingScenario.new.seed_scenario
pp demo.fetch("baseline").slice("status", "actual_counts")
pp demo.dig("catalog", "skipped_edition_conflicts")
```

The edition report includes conflicts found on replay, such as a missing
recorded edition or an edition linked to a different book.
판본 보고서에는 재실행 중 확인한 충돌도 표시된다. 예를 들어 기록된
판본이 사라졌거나 다른 책에 연결된 경우가 포함된다.

To add another batch, use the application container shell / 추가 활동은 앱 컨테이너 셸에서 실행한다:

```bash
RAILS_ENV=production bin/rails 'development_scenario:simulate_reading[demo1]'
```

| English | 한국어 |
| --- | --- |
| The demo uses 100 catalog books and adds 30 readers and a demo admin, reading/community/reaction data, six challenges with 40 enrollments, and subject-based genre links. Conflicting editions skipped during the initial import appear in the console summary. Some other identity conflicts still stop the import for review. | 시연에는 카탈로그 책 100권을 사용하고, 독자 30명과 시연 관리자, 독서·커뮤니티·반응 데이터, 챌린지 6개와 참여 40개, 주제 기반 장르 연결을 추가한다. 최초 가져오기에서 충돌로 건너뛴 판본은 콘솔 결과에 표시된다. 일부 다른 식별 충돌은 여전히 검토를 위해 가져오기를 중단한다. |
| `demo1` adds three sessions dated today and two posts. Use `demo2` for another batch. Repeating the same name resumes or reuses that batch without duplicates. The argument-free command retains the original `tick1` behavior and reference date. | `demo1`은 오늘 날짜 세션 3개와 게시글 2개를 추가한다. 추가 활동에는 `demo2`처럼 새 이름을 사용한다. 같은 이름은 중복 없이 복구·재사용하며 인수 없는 명령은 기존 `tick1` 동작과 기준일을 유지한다. |
| Keep the normal worker running for progress jobs, notifications and broadcasts. Synthetic accounts use reserved `@example.test` addresses, but normal job callbacks still run. | 진행률 작업·알림·브로드캐스트를 처리하는 워커를 실행한다. 합성 계정은 예약된 이메일 주소를 사용하지만 일반 작업 콜백은 실행된다. |
| Verify the printed counts, all genre filters, the three challenge enrollment groups, and current Trending results where enabled. Ranking is cached for 30 minutes. Recent reactions age out of its seven-day window; new reading batches do not refresh reactions. | 출력 수, 장르 필터, 챌린지 참여 그룹 3가지, 활성화된 Trending 결과를 확인한다. 순위는 30분 캐시되며 반응은 7일 집계 범위를 벗어날 수 있다. 독서 활동 추가는 반응 시각을 갱신하지 않는다. |
| For recovery, retain the manifest and rerun the same command with the same settings. There is no automatic cleanup command; inspect recorded IDs before any targeted cleanup and preserve real-user data. Unset `ALLOW_PRODUCTION_SCENARIO` after demo operations. | 복구 시 manifest를 보존하고 같은 설정·명령으로 재실행한다. 자동 정리 명령은 없으며 정리가 필요하면 기록된 ID를 확인하고 실제 사용자 데이터를 보존한다. 작업 후 운영 허용 설정을 해제한다. |

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
