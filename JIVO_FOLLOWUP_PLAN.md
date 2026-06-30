# JIVO Idle Follow-Up — Design & Implementation Plan

Status: **Planned / agreed** (not yet implemented)
Branch: `omni-dev` (dev) → merged to `omni-main2` (prod)

A scalable plan to finalize and upgrade the JIVO **idle follow-up** feature: when a
bot-handled conversation goes quiet, JIVO follows up (static message *or* AI-generated),
repeats up to a limit, then escalates (handoff). Includes a Super Admin per-account
monthly AI-call usage counter as the **final phase**.

> **Reuse note (for fresh chats):** this file is the single source of truth for the
> feature. Read it before starting any phase. Each phase is independently shippable and
> has a "Done when" check. Update the Status line of a phase as it lands.

---

## 1. Background & current state

The feature already exists in the codebase but is **dark-launched**: backend is built and
scheduled, only the Settings UI is commented out, and there is no per-conversation cutoff.

| Piece | State | Location |
|---|---|---|
| Model config + helpers | ✅ built | `app/models/jivo_assistant.rb` (store_accessor L43-45; `idle_*` helpers L86-112; defaults `DEFAULT_IDLE_TIMEOUT_MINUTES=60`, `DEFAULT_IDLE_REMINDER_LIMIT=3`) |
| Background job | ✅ built | `app/jobs/jivo/idle_conversation_action_job.rb` (scans JIVO inboxes → `pending` + idle conversations → applies action: resolve / handoff / reminder; reminder count in `custom_attributes['jivo_idle_reminder_count']`) |
| Schedule | ✅ live, hourly | `config/schedule.yml` → `jivo_idle_conversation_action_job` cron `0 * * * *` |
| Controller permits | ✅ built | `app/controllers/api/v1/accounts/jivo/assistants_controller.rb` (permitted `config` keys L70-72) |
| Settings UI | ❌ **commented out** | `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` L266-342 (form fields already initialized L51-55) |
| i18n strings | ✅ exist | `app/javascript/dashboard/i18n/locale/en/jivo.json` (`GROUPS.IDLE`, `FEATURE_IDLE_ACTION`, `IDLE_TIMEOUT`, `IDLE_ACTION.*`, `IDLE_MESSAGE`, `IDLE_REMINDER_LIMIT`) |
| Per-conversation cutoff | ❌ missing | needs `idle_action_enabled_at` (mirror inbox `auto_reassignment_enabled_since`) |
| AI-generated follow-up | ❌ missing | new |
| Usage counter (Super Admin) | ❌ missing | new (final phase) |

**Why it was hidden** (comment in the form): idle reassignment is currently handled at the
inbox level (Settings → Inbox → Collaborators, `AutoAssignment::IdleReassignmentService`).
That service acts **after handoff** (`.open.assigned.where(taken_at: nil)` + `ai_handoff=true`).
This JIVO feature acts **before handoff** (`status = pending`). They operate on different
conversation phases → clean baton-pass, not a conflict (see §6).

---

## 2. Production sizing (measured 2026-06, the "$11/month" period)

- Pending+idle (>60m) on JIVO inboxes right now: **588** — but **~98% is stale backlog**
  (599 pending total). → The **enabled-since cutoff is mandatory** or enabling the feature
  blasts ~588 dead chats.
- New conversations/day on JIVO inboxes: **~90–165 (avg ~120)**; ~12 in a peak hour.
- June AI usage: **~12,471 incoming processed / 13,506 replies sent for $11** → **~$0.00085 per AI call**.
- **Follow-up cost projection** (each chat capped at `idle_reminder_limit` calls for life):
  - Worst case ~360 calls/day → ~$9/mo (×1.5–2 for larger context ≈ **$15–18/mo**).
  - Realistic (skips + not-all-abandoned) ≈ **$5–8/mo**.
- Verdict: trivial absolute cost; tune via `idle_timeout_minutes` and `idle_reminder_limit`.

---

## 3. Locked design decisions

1. **One feature, optional AI switch** (not two separate modes):
   - **Shared eligibility** (Layer 1, deterministic, free) runs for every mode.
   - **AI ON** → `idle_prompt`; the AI decides *whether* to follow up (scenario) and *what* to say (Layer 2 AI call).
   - **AI OFF** → `idle_message`; send fixed text every attempt. **Zero AI calls.**
2. **Counting stays in code** (`jivo_idle_reminder_count`); the AI only decides skip/message — never counts attempts.
3. **On limit reached** → `on_limit_action`: `handoff` (default) / `resolve` / `none`.
4. **Enabled-since cutoff**: only act on conversations **created after** the feature was enabled (`idle_action_enabled_at`). Mirrors `auto_reassignment_enabled_since`.
5. **Runs before handoff** (`pending`); inbox idle reassignment runs after handoff. Escalation = handoff = the baton-pass.
6. **Usage counter** (Super Admin, per account, per month) tracks **AI calls** split `sent` vs `skipped` (a skip still costs a call). Static mode = no AI call = nothing counted. **Final phase.**

---

## 4. Target config schema (`jivo_assistant.config`)

Keep existing keys for back-compat; add new ones.

| Key | Type | Status | Meaning |
|---|---|---|---|
| `feature_idle_action` | bool | existing | Master on/off for the follow-up feature |
| `idle_timeout_minutes` | int | existing | Idle threshold (default 60) |
| `idle_reminder_limit` | int | existing | Max follow-up attempts per conversation (default 3) |
| `idle_message` | string | existing | Static follow-up text (AI OFF) |
| `idle_use_ai` | bool | **new** | Use AI to generate/decide the follow-up |
| `idle_prompt` | string | **new** | AI instruction (AI ON) |
| `on_limit_action` | enum | **new** | After limit: `handoff` (default) / `resolve` / `none` |
| `idle_action_enabled_at` | iso8601 | **new** | Cutoff timestamp; auto-set when `feature_idle_action` flips false→true |

Back-compat mapping for the legacy `idle_action` (`handoff`/`resolve`/`reminder`): treat
`reminder` as the follow-up loop; fold `handoff`/`resolve` into `on_limit_action`. Provide
sane defaults so existing assistants don't break.

---

## 5. Execution flow (per hourly job run)

```
For each JIVO inbox whose assistant has feature_idle_action = true:
  Layer 1 — eligibility (SQL, free):
    conversations
      .pending
      .where(last_activity_at < idle_timeout_minutes.ago)
      .where(created_at >= idle_action_enabled_at)        # cutoff
      .limit(BULK_ACTIONS_LIMIT = 100)                     # per inbox per run
    # NOTE: attempt count is NOT a scope filter — at-limit conversations must still be
    # selected so escalation can fire. It's a per-conversation branch (below).

  For each selected conversation:
    if attempts >= idle_reminder_limit:
      apply on_limit_action (handoff | resolve | none); stop
      # handoff/resolve leave the pending scope; 'none' stays but is a cheap no-op each run
    elsif idle_use_ai:
      if no NEW customer message since last AI check: skip (no call)   # skip-loop guard
      result = AI call (idle_prompt + conversation context)   # COUNT: sent/skipped
      if result.should_follow_up: post result.message; increment count
      else: record last-checked marker (no message, no count bump)
    else:
      post idle_message; increment count                       # no AI call
```

**Attempt spacing is automatic:** every message bump `last_activity_at` (`Message#set_conversation_activity`), so a sent follow-up resets the idle timer → the next attempt can't fire until another full `idle_timeout_minutes` passes. No extra spacing logic needed.

**Escalation timing matches the ask** ("check 2 times, handoff on the 3rd"): with limit=2, cycles 1–2 send follow-ups (count→2), cycle 3 sees `attempts >= limit` → handoff. This is why attempt count is a per-conversation branch, not a scope filter.

**Skip-loop guard (AI mode):** a skip sends no message, so `last_activity_at` is *not* bumped → the chat would re-qualify and re-call the AI every run for no reason. Guard with a "last checked" marker (mirror `Jivo::ContactEnrichmentService`'s `jivo_contact_enriched_message_id`): only call the AI when a **new incoming customer message** exists since the last check. Skips then cost ≤1 call until the customer says something new.

AI call JSON contract (reuse V1 handler pattern, `response_format: json_object`):
```json
{ "should_follow_up": true, "message": "<customer-facing follow-up, in customer's language>" }
```
System prompt = `idle_prompt` + reuse the existing language rule ("reply in the customer's
language") + brevity guidelines from `Jivo::Prompts::V1ConversationPrompt`.

---

## 6. Overlap with inbox idle reassignment (no conflict)

- **JIVO follow-up**: `status = pending` (bot phase, pre-handoff).
- **Inbox idle reassignment** (`AutoAssignment::IdleReassignmentService`): `.open.assigned.where(taken_at: nil)` + `ai_handoff=true` (post-handoff). Already has its own `auto_reassignment_enabled_since` cutoff — we mirror that pattern.
- Sequence: bot handles → (idle) JIVO follows up N times → escalates to handoff → becomes open/assigned → inbox reassignment takes over → agent "takes" (`taken_at`) → both stop.

---

## 7. Phases

> Each phase: small, testable, shippable. Resolve RuboCop/ESLint, no specs unless asked.
> Commit on `omni-dev`; merge to `omni-main2` for prod. Ruby-only phases need no migration
> unless stated; Phase 6 adds a migration.

### Phase 0 — Cutoff foundation  ·  Status: ✅ (omni-dev)
- **Goal:** never act on pre-enable conversations.
- Added `idle_action_enabled_at` to `store_accessor` (`app/models/jivo_assistant.rb`).
- `before_save :stamp_idle_action_enabled_at` — stamps only on a **false→true** transition of `feature_idle_action` (re-enabling restarts the window; other edits don't touch it). Helper `idle_action_enabled_at_value` parses it.
- Job `idle_conversations` now filters `conversations.created_at >= cutoff`; `backfill_cutoff` stamps "now" for any enabled assistant missing a cutoff (safety net so a console/pre-existing enable can't blast the backlog).
- **Deviations from sketch:** controller permit intentionally **not** added — the cutoff is system-managed, not user-settable. Added the backfill safety net (sketch said "skip filter if blank"; we instead self-heal to "now" to stay safe).
- **Done when:** flipping the toggle on stamps the timestamp; the job ignores older conversations. ✓

### Phase 1 — Eligibility pipeline refactor  ·  Status: ✅ (omni-dev)
- **Goal:** one clean Layer-1 scope shared by all modes.
- Eligibility scope (pending + idle + cutoff + `BULK_ACTIONS_LIMIT`) already centralized in `idle_conversations` (Phase 0). Attempt count is intentionally NOT in the scope (see §5 note).
- Centralized attempt count via `ATTEMPT_COUNT_KEY` constant + `attempt_count` / `increment_attempt` helpers (renamed from `increment_reminder_count`); `reminder_limit_reached?` now uses `attempt_count`. Behavior unchanged.
- **Done when:** job selects exactly the conversations in §5 Layer 1 and attempt count has one source of truth. ✓

### Phase 2 — Static follow-up loop + escalation  ·  Status: ☐
- **Goal:** ship the free path end-to-end (no AI), proves scheduling + cutoff + limit.
- Behavior: post `idle_message` each cycle; increment count; on limit → `on_limit_action`.
- Add `on_limit_action` config (`handoff` default / `resolve` / `none`); map legacy `idle_action`.
- **Done when:** an eligible pending chat gets up to N static nudges, then handoff; nothing fires before cutoff.

### Phase 3 — AI follow-up mode  ·  Status: ☐
- **Goal:** prompt-driven, scenario-aware follow-up.
- Add `idle_use_ai` + `idle_prompt`.
- New service `Jivo::Tasks::IdleFollowUpService` (or reuse `Jivo::ConversationHandlerService`/`OpenaiMessageBuilderService` + JSON contract in §5). Returns `{should_follow_up, message}`.
- AI ON → call per eligible chat; send or skip; static path unchanged when AI OFF.
- Reuse language + brevity rules from `Jivo::Prompts::V1ConversationPrompt`.
- **Done when:** with a prompt like "if no phone number, ask for it", chats missing a number get an AI message; chats that already have one are skipped.

### Phase 4 — Settings UI (un-hide + finalize)  ·  Status: ☐
- **Goal:** expose the feature to admins.
- Un-comment `JivoAssistantForm.vue` L266-342; add controls for `idle_use_ai`, `idle_prompt`, `on_limit_action`.
- AI toggle reveals `idle_prompt` (AI ON) vs `idle_message` (AI OFF).
- Add new i18n strings to `jivo.json` (and `en.yml` for any backend strings). English only.
- **Done when:** admin can configure everything in Settings → JIVO → Behavior; saves persist.

### Phase 5 — Guardrails & polish  ·  Status: ☐
- **Goal:** production hardening.
- Per-conversation failure isolation (already in job `rescue`), logging, sane defaults/validation (timeout ≥ 1, limit ≥ 1).
- Confirm clean handoff baton-pass with inbox reassignment (§6).
- Optional: activity-message wording for follow-ups.
- **Done when:** misconfig/AI errors degrade gracefully; no double-acting with reassignment.

### Phase 6 — Super Admin monthly AI-call usage counter  ·  Status: ☐  ·  **(LAST)**
- **Goal:** at-a-glance per-account monthly usage ("credits").
- Count **AI calls** only (Phase 3 path), split `sent` vs `skipped`. Static mode not counted.
- **Storage (scalable):** monthly aggregate row, e.g. table `jivo_ai_usages`
  `(account_id, period 'YYYY-MM', kind 'follow_up', sent_count, skipped_count, timestamps)`,
  unique on `(account_id, period, kind)`, atomic upsert/increment at call time.
  (Simpler alt: increment `account.custom_attributes`; less scalable, avoid.)
- **Display:** add the current-month count to the Super Admin → Accounts view.
- **Done when:** each AI follow-up call increments the right monthly row; Super Admin shows e.g. "JIVO follow-up AI calls (2026-07): 312 — 190 sent / 122 skipped".

---

## 8. Risks / watch-list

- **Backlog blast** → mitigated by Phase 0 cutoff. Never ship Phase 2+ without it.
- **Cost creep** → bounded by `idle_reminder_limit` (lifetime cap per chat) + AI skip; tune timeout/limit.
- **Language/tone** → reuse existing language rule so follow-ups match the customer's language.
- **Hourly granularity** → first follow-up can land up to ~1h after the timeout; acceptable.
- **Separate hygiene issue (not this feature):** ~98% of pending chats never close. Worth a later look; does not affect follow-up once cutoff is in.

## 9. Future / out of scope

- Deliberate one-time, throttled follow-up sweep over the existing backlog (separate job).
- Per-inbox (vs per-assistant) overrides.
- Richer usage analytics / cost dashboard beyond the monthly counter.
