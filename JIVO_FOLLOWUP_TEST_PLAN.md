# JIVO Idle Follow-Up — Test Case Catalog

Test cases for the complete idle follow-up feature (Phases 0–6 + review hardening).
Each case is written to become **one automated test** (RSpec) later: it names the unit
under test, the setup (Given), the action (When), and the assertion (Then).

> Status: catalog only. Automation to follow — one `it` per TC.

## Units under test
- `app/models/jivo_assistant.rb` — config helpers + `idle_action_enabled_at` cutoff callback
- `app/jobs/jivo/idle_conversation_action_job.rb` — the scheduled job (eligibility, static/AI loop, marker, escalation)
- `app/services/jivo/tasks/idle_follow_up_service.rb` — AI decision service (result shape, degradation)
- `app/services/jivo/tasks/base_task_service.rb` — `token_usage` helper
- `app/services/jivo/model_pricing.rb` — pricing map + `cost`
- `app/models/jivo_ai_usage.rb` — `record_action` (atomic upsert, counts, tokens, cost), `estimated_cost`
- `app/services/jivo/handoff_service.rb` — shared handoff
- `app/views/super_admin/accounts/_jivo_ai_usage.html.erb` — Super Admin display

## Shared constants (assert against these)
- defaults: `idle_timeout_minutes = 60`, `idle_reminder_limit = 3`, `on_limit_action = handoff`
- attempt key: `custom_attributes['jivo_idle_reminder_count']`
- checked-at marker: `custom_attributes['jivo_idle_checked_at']`
- per-run cap: `Limits::BULK_ACTIONS_LIMIT = 100` per inbox
- status enum: `pending = 2`, `open = 0`
- AI actions: `follow_up | handoff | wait`; hard error → `{ success: false }` (no `:action`)
- pricing (USD / 1M tokens): gpt-4.1 2.00/8.00 · gpt-4.1-mini 0.40/1.60 · gpt-4.1-nano 0.10/0.40 · gpt-4o 2.50/10.00 · gpt-4o-mini 0.15/0.60 · default = mini

---

## A. Assistant config & cutoff (`JivoAssistant`)

**TC-01 — defaults when unset**
Given a JIVO assistant with no idle keys set · When reading helpers · Then `idle_timeout_minutes_value == 60`, `idle_reminder_limit_value == 3`, `on_limit_action_value == 'handoff'`, `idle_use_ai_enabled? == false`, `idle_action_enabled? == false`.

**TC-02 — non-positive timeout falls back to default**
Given `idle_timeout_minutes = 0` (and `-5`, `''`) · Then `idle_timeout_minutes_value == 60`.

**TC-03 — non-positive limit falls back to default**
Given `idle_reminder_limit = 0` (and blank) · Then `idle_reminder_limit_value == 3`.

**TC-04 — on_limit_action validation**
Given `on_limit_action = 'none'` → value `'none'`; given `'resolve'` or garbage → value falls back to `'handoff'`.

**TC-05 — boolean coercion**
Given `feature_idle_action = 'true'` / `'1'` / `true` · Then `idle_action_enabled? == true`; given `'false'`/`'0'`/nil · Then false. Same for `idle_use_ai`.

**TC-06 — cutoff stamped on false→true toggle**
Given `feature_idle_action` false · When set true and saved · Then `idle_action_enabled_at_value` is ~`Time.current` (within a few seconds).

**TC-07 — cutoff NOT restamped on unrelated save**
Given enabled assistant with cutoff `T` · When another field saved (still enabled) · Then `idle_action_enabled_at_value == T` (unchanged).

**TC-08 — cutoff restarts on re-enable**
Given enabled (cutoff `T1`) · When disabled then re-enabled later · Then new cutoff `T2 > T1`.

**TC-09 — cutoff preserved across whole-config replace (form save)**
Given enabled with cutoff `T` · When `config` is reassigned without the system key (mimicking the Settings form) and saved · Then `idle_action_enabled_at_value == T`.

**TC-10 — idle_message_text fallback**
Given blank `idle_message` · Then `idle_message_text` returns the default check-in text; given a custom message · returns it verbatim.

---

## B. Job eligibility & scoping (`IdleConversationActionJob`)

**TC-11 — only JIVO inboxes are scanned**
Given a non-JIVO inbox with idle pending conversations · When job runs · Then those conversations are untouched (no message, no attempt change).

**TC-12 — disabled assistant skipped**
Given a JIVO inbox whose assistant has `feature_idle_action = false` · When job runs · Then its conversations are untouched.

**TC-13 — pending + idle conversation is eligible**
Given enabled assistant (timeout 60), a `pending` conversation with `last_activity_at = 61.minutes.ago`, `created_at` after cutoff · When job runs (static mode) · Then it receives one follow-up.

**TC-14 — not-yet-idle conversation skipped**
Given `last_activity_at = 59.minutes.ago` · When job runs · Then untouched (no follow-up).

**TC-15 — non-pending statuses skipped**
Given `open`, `resolved`, `snoozed` idle conversations · When job runs · Then untouched (scope is `pending` only).

**TC-16 — pre-cutoff backlog never acted on**
Given a `pending` idle conversation with `created_at < idle_action_enabled_at` · When job runs · Then untouched (the ~588 stale-backlog protection).

**TC-17 — conversation created exactly at cutoff is eligible**
Given `created_at == cutoff` · Then eligible (`>=` boundary).

**TC-18 — backfill stamps cutoff when missing**
Given enabled assistant with blank `idle_action_enabled_at` · When job runs · Then cutoff is stamped ~now and NO pre-existing conversation is acted on this run.

**TC-19 — per-inbox bulk cap**
Given 150 eligible pending conversations on one inbox · When job runs once · Then at most `BULK_ACTIONS_LIMIT (100)` are processed.

**TC-20 — attempt count is NOT a scope filter (at-limit still selected)**
Given a pending idle conversation already at `attempt_count == limit` · When job runs · Then it is selected and escalated (proves at-limit chats aren't filtered out of the scope).

**TC-21 — multi-inbox isolation**
Given two JIVO inboxes (one enabled, one disabled) · When job runs · Then only the enabled inbox's conversations are touched.

**TC-22 — per-conversation failure isolation**
Given two eligible conversations where the first raises mid-action · When job runs · Then the error is logged/captured and the second conversation is still processed.

**TC-23 — Current.executed_by set to assistant**
Given processing an inbox · Then messages created during the run are attributed to the assistant (sender) and `Current.reset` runs in `ensure`.

---

## C. Static mode (AI off)

**TC-24 — static follow-up sends idle_message**
Given AI off, custom `idle_message` · When eligible · Then an outgoing message with that text is posted and `attempt_count` becomes 1.

**TC-25 — static loop up to limit**
Given AI off, limit 2 · When the job fires across 3 idle cycles (re-staling `last_activity_at` each time) · Then cycle 1→attempt 1, cycle 2→attempt 2, cycle 3→handoff (status open). 2 messages then handoff.

**TC-26 — static spacing is automatic**
Given AI off · When a follow-up is sent · Then `last_activity_at` advances (message creation), so an immediate re-run does NOT send a second follow-up.

**TC-27 — static mode records ZERO AI usage (cost leak guard)**
Given AI off · When N follow-ups are sent · Then `JivoAiUsage.current_month_for(account)` is nil/zero (no AI call ⇒ nothing counted, no cost).

**TC-28 — blank idle_message uses default text**
Given AI off, blank `idle_message` · Then the follow-up uses the default check-in copy (non-empty).

---

## D. AI mode actions

**TC-29 — follow_up sends AI message + counts**
Given AI on, service returns `{action:'follow_up', message:'Hi…', input_tokens:1000, output_tokens:50}` · Then the AI message is posted, `attempt_count` +1, and usage `follow_up_count` +1.

**TC-30 — follow_up with blank message falls back**
Given `{action:'follow_up', message:''}` · Then `post_follow_up` posts `idle_message_text` (not an empty message).

**TC-31 — handoff acts immediately**
Given `{action:'handoff'}` · Then the conversation is handed off now (status open, `ai_handoff=true`), no follow-up message, `attempt_count` unchanged, usage `handoff_count` +1.

**TC-32 — wait counts but sends nothing**
Given `{action:'wait'}`, below limit · Then no message, `attempt_count` +1, usage `wait_count` +1.

**TC-33 — wait that reaches the limit escalates same run**
Given `{action:'wait'}`, `attempt_count == limit-1` · Then `attempt_count` becomes limit AND the conversation is handed off in the same run.

**TC-34 — AI message language**
Given the service prompt builds with the customer-language rule · Then the system prompt includes the "same language as the customer" instruction (assert on built messages).

**TC-35 — static path is never AI in AI-off mode**
Given AI off · Then `IdleFollowUpService` is never instantiated (no AI call) for any cycle.

**TC-36 — model passed to usage is the assistant's model**
Given assistant `openai_model = 'gpt-4o'` · When an AI action records usage · Then cost is computed at gpt-4o rates (see TC-58).

---

## E. AI re-check spacing & marker (cost-leak core)

**TC-37 — first AI check stamps the marker**
Given no `jivo_idle_checked_at` · When `ai_follow_up` runs · Then the marker is stamped ~now before/around the AI call.

**TC-38 — recently_checked? blocks within the idle window**
Given marker `= 30.minutes.ago`, timeout 60 · Then `recently_checked? == true` and `ai_follow_up` returns early (no AI call, no attempt change, no usage).

**TC-39 — recently_checked? allows after the idle window**
Given marker `= 61.minutes.ago`, timeout 60 · Then `recently_checked? == false` and the AI runs.

**TC-40 — no marker ⇒ first check proceeds**
Given marker absent · Then `recently_checked? == false`.

**TC-41 — wait does NOT re-call AI every cron tick (regression guard)**
Given AI on, service always returns `wait`, timeout 60, cron simulated every 10 min · When the job fires 6 times within one hour (last_activity_at fixed in the past) · Then the AI is called **once**, not 6 times (marker suppresses re-checks). Usage `wait_count == 1` for that hour.

**TC-42 — wait escalation timing respects the timeout**
Given AI on, always `wait`, timeout 60, limit 3 · When fired across simulated time · Then attempts increment at ~60-min spacing and handoff occurs after ~3 windows — NOT after 3×10 min.

**TC-43 — marker stale after customer reply ⇒ fresh check**
Given a wait at t with marker stamped, then a customer reply bumps `last_activity_at` (newer than the marker), then idle again · Then `recently_checked? == false` and the AI re-checks (last_activity governs; stale marker doesn't block).

---

## F. AI error handling (cost-leak + escalation guard)

**TC-44 — hard error returns no actionable result**
Given `BaseTaskService#perform` rescues an exception and returns `{success:false, error:…}` (no `:action`) · When `ai_follow_up` handles it · Then the `else` branch runs: NO attempt increment, NO escalation, a warning is logged.

**TC-45 — error records no usage (no phantom cost)**
Given the error result (no action) · Then `JivoAiUsage.record_action(account, nil, …)` is a no-op (no row created, no counts).

**TC-46 — sustained outage does not march to handoff**
Given AI on, the service errors on every call, limit 3 · When the job fires repeatedly · Then the conversation is NOT handed off due to errors (attempts stay 0) and stays pending.

**TC-47 — error retries are spaced by the marker**
Given the AI errors · Then the marker is stamped, so the next error-retry is delayed by `idle_timeout` (not every 10-min tick) — bounding wasted calls during an outage.

**TC-48 — JSON parse error degrades to wait (service level)**
Given the AI returns 200 with non-JSON body · When `IdleFollowUpService#build_result` runs · Then it returns `{action:'wait'}` merged with token usage (degrade-to-wait, still counts as wait by design).

**TC-49 — invalid action degrades to wait**
Given the AI returns `{action:'banana'}` · Then the service returns `action:'wait'` (only `follow_up/handoff/wait` accepted).

---

## G. Attempt limit & escalation

**TC-50 — at-limit goes straight to escalate (no AI call)**
Given `attempt_count >= limit`, AI on · When job runs · Then `escalate` runs WITHOUT calling `IdleFollowUpService` (no AI cost at the backstop).

**TC-51 — on_limit_action = handoff hands off**
Given limit reached, `on_limit_action='handoff'` · Then conversation is handed off (status open, note posted).

**TC-52 — on_limit_action = none leaves pending**
Given limit reached, `on_limit_action='none'` · Then NO handoff, conversation stays pending (a cheap no-op each run).

**TC-53 — escalation note text (limit)**
Given a limit-backstop handoff · Then the private note uses `idle_handoff_reason` ("…after the idle follow-up limit was reached.").

**TC-54 — AI handoff note text (distinct)**
Given an AI-decided handoff · Then the private note uses `idle_ai_handoff_reason` ("Auto-handed off by JIVO idle follow-up.") — NOT the limit text.

---

## H. Handoff service (`Jivo::HandoffService`)

**TC-55 — handoff flips pending→open**
Given a pending conversation · When `HandoffService#perform` runs · Then status becomes `open` (via `bot_handoff!`).

**TC-56 — handoff sets ai_handoff flag**
Then `custom_attributes['ai_handoff'] == true` (so inbox reassignment can take over).

**TC-57 — handoff posts the reason as a private note**
Given `reason: 'X'` · Then a private outgoing message with content 'X' is created; given blank reason · Then no note is posted.

**TC-58 — handoff sends OOO when applicable**
Given no campaign · Then `OutOfOffice.perform_if_applicable` is invoked; given a campaign present · Then it is skipped.

**TC-59 — pattr_initialize optional reason defaults to nil**
Given `HandoffService.new(conversation:, assistant:)` (no reason) · Then it constructs without error and `reason` is nil (regression for the attr_extras boot fix).

---

## I. Usage counter (`JivoAiUsage.record_action`)

**TC-60 — known action increments the right column**
Given `record_action(acc, 'follow_up', model:, tokens…)` · Then row `(account, current period)` has `follow_up_count == 1`.

**TC-61 — unknown/nil action is ignored**
Given `record_action(acc, nil)` and `record_action(acc, 'bogus')` · Then no row is created / no counts change.

**TC-62 — tokens accumulate**
Given two calls with 1000/200 input · Then `input_tokens == 1200` on the single row.

**TC-63 — one row per account per period (atomic upsert)**
Given many calls in the same month · Then exactly ONE `jivo_ai_usages` row exists for `(account, period)`.

**TC-64 — concurrent calls don't lose counts / don't raise**
Given N threads calling `record_action` for the same account+period · Then the final counts sum correctly and no `RecordNotUnique` is raised (atomic `upsert_all`).

**TC-65 — period is current YYYY-MM**
Then `period == Time.current.strftime('%Y-%m')`; a call in a different month creates a separate row.

**TC-66 — cost computed at the call's own model**
Given a gpt-4.1 call (1000 in / 100 out) · Then `cost_micros == round((1000*2.00 + 100*8.00)/1e6 * 1e6) == 2800`.

**TC-67 — mixed-model month sums correctly**
Given call A on gpt-4.1 (1000/100) and call B on gpt-4.1-mini (1000/100) · Then `estimated_cost == 0.00336` (each priced at its own model, summed — NOT blended).

**TC-68 — estimated_cost reads stored micros**
Then `estimated_cost == cost_micros / 1_000_000.0` (no live model lookup).

**TC-69 — total helper sums action counts**
Given follow_up 2 / handoff 1 / wait 0 · Then `total == 3`.

**TC-70 — handoff & wait also recorded (full breakdown)**
Given one of each action · Then `follow_up_count/handoff_count/wait_count` are each 1 and `total == 3`.

---

## J. Pricing & token extraction

**TC-71 — price_for known model**
Given `price_for('gpt-4o')` · Then `{input:2.50, output:10.00}`.

**TC-72 — price_for unknown/nil → default**
Given `price_for('made-up')` and `price_for(nil)` · Then `DEFAULT_PRICE` (mini rates).

**TC-73 — cost math**
Given `cost(model:'gpt-4.1-mini', input_tokens:1_000_000, output_tokens:0)` · Then `== 0.40`.

**TC-74 — token_usage extracts prompt/completion tokens**
Given response `{'usage'=>{'prompt_tokens'=>123,'completion_tokens'=>45}}` · Then `token_usage == {input_tokens:123, output_tokens:45}`.

**TC-75 — token_usage missing usage block → zeros**
Given response without `'usage'` · Then `{input_tokens:0, output_tokens:0}` (no crash).

**TC-76 — IdleFollowUpService merges tokens into every branch**
Given valid follow_up / handoff / wait / JSON-error responses · Then each returned hash includes `input_tokens`/`output_tokens` from `token_usage`.

---

## K. Baton-pass with inbox reassignment (no conflict)

**TC-77 — idle job ignores open/assigned conversations**
Given an `open`+assigned conversation (post-handoff) on a JIVO inbox · When the idle job runs · Then it is untouched (scope is `pending`).

**TC-78 — reassignment ignores pending conversations**
Given a `pending` conversation · When `AutoAssignment::IdleReassignmentService` runs · Then it is untouched (scope is `.open.assigned`).

**TC-79 — sequential handoff path**
Given a pending chat that hits handoff · Then it leaves the idle scope (now open + ai_handoff) and becomes eligible for inbox reassignment — proving the clean hand-off boundary.

---

## L. Super Admin display & cross-cutting cost-leak

**TC-80 — usage shown for current month**
Given recorded usage for an account · When the Super Admin account show renders · Then it shows total, per-action breakdown, tokens in/out, and `est. ≈ $cost`.

**TC-81 — no-usage state**
Given no usage rows · Then it renders "No AI follow-up calls this month." (no crash, no cost line).

**TC-82 — display has no per-request model guess**
Then the partial reads `usage.estimated_cost` (no `JivoAssistant.find_by` model lookup) — correct for multi-assistant accounts.

**TC-83 — cost-leak sweep (end-to-end)**
Across a full run with mixed outcomes · Then: static cycles record 0 usage; each AI call records exactly 1 action; a `wait` chat is AI-called at most `limit` times for its life; errors record 0; the at-limit backstop makes 0 AI calls; total AI calls per conversation ≤ `idle_reminder_limit`.

**TC-84 — idempotent re-run within the window**
Given any AI-mode conversation just processed · When the job immediately re-runs (same minute) · Then no second AI call/message/attempt occurs (marker for wait/error; last_activity for follow_up; open status for handoff).

---

### Coverage summary
84 cases across: config/cutoff (10), eligibility/scoping (13), static mode (5), AI actions (8),
re-check spacing/marker (7), error handling (6), limit/escalation (5), handoff service (5),
usage counter (11), pricing/tokens (6), baton-pass (3), Super Admin/cost-leak (5).
