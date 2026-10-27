# Issue #131 — Local integrated demonstration

Date: 2026-10-25 America/Vancouver (2026-10-26 UTC)
Initial demo code: 09b789a; authentication fix: 27d6c78
Demo club: 29, Issue 131 demo 2026-10-25
Users: admin (Chrome), hamster (in-app browser)
Transport: actual development Solid Cable database, existing Solid Queue worker.
No production data or services were changed. The dedicated demo club, posts, memberships, and pick notifications remain for inspection.

| Scenario | Observed result |
| --- | --- |
| Ordinary nonmember denial | Before joining, hamster requested club 29 discussion and was redirected home with an authorization alert. |
| Book change | Owner changed Philosopher's Stone to Chamber of Secrets. Hamster's already-open overview updated without manual reload. Save-click to observed book heading: 483 ms, including UI automation overhead. |
| Notification | Hamster received the Chamber of Secrets notification and unread badge 1 through live delivery. |
| Presence | Both browsers displayed two members online. |
| Typing | Filling hamster's composer produced “hamster is typing…” and “Writing a post…” in admin's browser. |
| Baseline post | Hamster published the labeled baseline post. Admin observed it after 919 ms, including UI automation overhead. |
| Transport interruption | A local TCP proxy to the existing server was stopped. Admin displayed Offline while hamster saved 12 uniquely labeled Transport posts. Admin stayed on its old feed during the outage. |
| Automatic reconnect recovery | Restarting only the proxy restored Discussion live without page reload or manual Retry. Visible IDs were 75 through 66, each exactly once, newest first. |
| Draft preservation | The composer still contained “[Issue 131 demo] Transport outage draft” after automatic recovery. |
| Bound/history | Page 1 showed the newest ten posts; total count was 25 and page count 3. Page 2 contained Transport posts 02 and 01, followed by earlier posts. |
| Recovery observation window | Recovery was observed within 11,025 ms of beginning the proxy restart sequence. This includes tool/approval/orchestration delays; it is an observation upper bound, not measured application/network recovery latency. |
| Worker restart | Worker 57861 was paused. Owner changed the book to Prisoner of Azkaban. Read-only DB inspection found two persisted recipient notifications and one pending Noticed job, while hamster still showed unread badge 1. The worker was gracefully terminated/resumed for shutdown; its supervisor spawned worker 97010. Without reloading hamster's page, the new notification arrived and badge became 2. |
| Presence failure | Both browsers used the dedicated 3001 server with dedicated Redis 6399 stopped. Both showed Presence unavailable. Hamster's “Redis down, discussion still works” post still reached admin through Solid Cable. |
| Presence recovery | Redis 6399 was restarted. Both browsers returned to two members online through normal heartbeat recovery, without reload. No precise recovery latency was captured. |
| Cleanup | Both browsers returned to the original 3000 server. Dedicated server 3001, Redis 6399, and proxy 3002 were stopped. Original server, original Redis, and replacement worker remain running. |

## Restart authentication finding — resolved on 2026-10-27

The original cold-start demonstration failed when the first request to the restarted development server was `/cable`. The socket upgraded but Warden did not find the logged-in user, and private discussion content was cleared. This failed run is retained here rather than counted as a pass.

Investigation reproduced an unloaded Devise mapping and Warden's `default` scope in a fresh process. After route loading, the configured scope was `user` and the same valid session resolved correctly. The connection now resolves `Devise::Mapping.find_scope!(User)` before reading `env["warden"].user(scope: scope)`.

On 2026-10-27, the dedicated server was stopped and restarted as a new process. The retained browser page reconnected without reload. Server logs confirmed the first request was `/cable`, followed by successful authentication, discussion/notification subscriptions, and the selected-page JSON request. The UI returned to Discussion live with its unsent draft intact. No warm-up page request preceded that WebSocket request. The temporary server was then stopped.

Regression coverage uses real Warden session deserialization for valid/stale-scope, guest, and outdated-salt sessions. A separate fresh-process test checks that mappings and the per-user session deserializer are prepared before the session is read. That initialization test uses a Warden probe; it is complemented by the real-session tests and actual browser restart demonstration.

Production was not redeployed or tested in this assessment. The original failure and verified correction concern the local development startup path.

| English | 한국어 |
| --- | --- |
| Restart authentication is fixed and re-demonstrated. The first WebSocket request authenticated and the draft survived. | 재시작 인증 문제를 수정하고 재시연했다. 첫 WebSocket 요청이 인증됐고 초안도 유지됐다. |
| The fix does not bypass login checks. Guest and outdated authentication sessions remain rejected. | 로그인 검사를 우회하지 않는다. 비로그인 사용자와 오래된 인증 세션은 계속 거부된다. |

## 한국어 요약

- 책 변경, 알림, 접속자, 입력 중 표시, 실시간 게시를 두 사용자로 확인했다.
- 연결만 끊었다가 복구하자 놓친 12개 글 중 최신 10개가 중복 없이 자동 표시되고 초안이 유지됐다. 나머지 글은 2페이지에서 확인했다.
- 실제 Solid Queue 워커가 교체된 뒤 저장돼 있던 알림이 전달됐다.
- 시연 전용 Redis 장애 중에도 게시가 전달됐고 Redis 복구 후 접속자 표시가 자동으로 돌아왔다.
- 별도 Rails 서버 재시작 직후의 인증 거부를 발견했고, 2026-10-27에 Devise 범위 초기화 수정과 재시작 재시연으로 해결을 확인했다.
- 임시 서비스는 정리했고 시연 모임은 재확인을 위해 남겼다. 인증 수정은 27d6c78에 커밋했다.

## Final required checks — 2026-10-27

| Command | Result / 결과 |
| --- | --- |
| `bin/rubocop --cache false` | 265 files, no offenses / 265개 파일, 위반 없음 |
| `yarn typecheck` | Passed / 통과 |
| `yarn test` | 155 TypeScript + 55 JavaScript tests passed / 총 210개 통과 |
| `bin/bundler-audit` | No vulnerabilities / 취약점 없음 |
| `bin/importmap audit` | No vulnerable packages / 취약 패키지 없음 |
| `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | No warnings / 경고 없음 |
| `bin/rails test` | 731 tests, 4,328 assertions, no failures/errors/skips; 13.45 seconds / 731개 테스트, 4,328개 검증 통과, 13.45초 |
| `git diff --check` | Passed / 통과 |

## Issue rubric — implementation self-assessment

This is an engineering self-assessment against the category weights stated in issue #131, not a teacher's grade. The linked detailed lesson was not retrievable during finalization, so no additional unstated subcriteria are assumed.

이슈 #131에 명시된 항목과 배점에 따른 구현 자체 평가이며 선생님의 최종 성적은 아니다. 최종 정리 중 상세 레슨 링크를 조회할 수 없어 별도의 세부 채점 기준을 추정하지 않았다.

| Category / 항목 | Self-assessed score / 자체 평가 | Evidence / 근거 |
| --- | --- | --- |
| Turbo | 20/20 | Live pick update; explicit current-pick, leaderboard and notification frame fallbacks; controller/frame tests / 책 실시간 갱신과 세 종류 프레임 갱신, 관련 테스트 |
| Noticed | 15/15 | Private persisted notifications, unread badge, mark-as-read tests, actual delivery after worker replacement / 개인별 알림 저장·배지·읽음 테스트와 실제 워커 교체 후 전달 |
| Custom Cable | 20/20 | Real two-user posting and typing over Solid Cable; spoofing, ownership, and nonmember tests / 실제 두 사용자 게시·입력 전달과 위조·소유권·비멤버 테스트 |
| Presence/typing | 15/15 | Two online members, typing, isolated Redis outage with continued posting, automatic presence recovery / 접속자·입력 표시, Redis 장애 중 게시, 접속 상태 자동 복구 |
| Recovery | 20/20 | Snapshot/event merging, selected-page bounds, stale requests, Retry, revocation, draft preservation, transport recovery and corrected cold restart / 병합·페이지 제한·오래된 요청·재시도·권한 철회·초안·연결 복구·서버 재시작 |
| Explanation/tests | 10/10 | Student Q&A provided in chat; complete required checks, regression tests, measurements and explicit limitations / 대화 내 학생 문답, 필수 검사·회귀 테스트·측정과 한계 기록 |
| **Total / 합계** | **100/100** | Core categories demonstrated; no privacy leak or executable-user-text failure observed in tested cases / 핵심 항목 시연 완료, 검증한 경우에서 개인정보 노출·사용자 텍스트 실행 실패 없음 |

User-provided message text is assigned through `textContent` in `app/javascript/club_discussion/message_elements.ts`; recovery tests include executable-looking text. Authorization denial/revocation and notification recipient isolation have automated coverage. This is bounded test evidence, not a claim of exhaustive security certification.

## Delivery limitations / 전달 한계

- Each discussion page contains at most ten visible top-level posts. Earlier posts remain in ordinary offset pagination; insertion/deletion can shift historical pages. / 최상위 글은 페이지당 최대 10개이며 이전 글은 오프셋 페이지네이션으로 조회한다. 추가·삭제에 따라 과거 페이지 구성이 달라질 수 있다.
- A restored transport is not message replay. Application snapshots recover current state; intermediate events are not an unlimited event history. / 연결 복구는 메시지 재생이 아니다. 스냅샷으로 현재 상태를 복구하며 무제한 이벤트 이력을 제공하지 않는다.
- Ambiguous posting acknowledgements are never automatically retried; a missing acknowledgement does not prove that saving failed. / 게시 확인 응답이 불명확하면 자동 재전송하지 않는다. 응답 유실이 저장 실패를 의미하지 않기 때문이다.
- Offline clients cannot immediately discover server-side membership changes. Private content is cleared when denial/revocation becomes observable. / 오프라인 클라이언트는 서버의 멤버십 변경을 즉시 알 수 없으며 권한 거부·철회가 관찰되면 비공개 내용을 제거한다.
- UI timings include automation overhead. The 11.025-second recovery observation window includes restart/tool delays and is not a precise recovery latency measurement. / 화면 측정은 자동화 지연을 포함한다. 11.025초의 복구 관찰 구간은 재시작·도구 지연까지 포함하며 정밀한 복구 지연 측정값이 아니다.
- Verification is local. Push, PR creation, merge, production deployment, and GitHub issue closure have not been performed. / 로컬 검증이다. 푸시·PR 생성·병합·운영 배포·GitHub 이슈 종료는 수행하지 않았다.
