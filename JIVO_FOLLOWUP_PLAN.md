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
      .where(jivo_idle_reminder_count < idle_reminder_limit OR null)
      .limit(BULK_ACTIONS_LIMIT = 100)                     # per inbox per run

  For each eligible conversation:
    if attempts >= idle_reminder_limit:
      apply on_limit_action (handoff | resolve | none); stop
    elsif idle_use_ai:
      result = AI call (idle_prompt + conversation context)   # COUNT: sent/skipped
      if result.should_follow_up: post result.message; increment count
      else: skip (no message); (count as skipped)
    else:
      post idle_message; increment count                       # no AI call
```

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

### Phase 0 — Cutoff foundation  ·  Status: ☐
- **Goal:** never act on pre-enable conversations.
- Add `idle_action_enabled_at` to `store_accessor` + controller permits.
- Set it automatically when `feature_idle_action` transitions false→true (model callback).
- Add `created_at >= idle_action_enabled_at` to the job's `idle_conversations` scope (skip filter if blank, to preserve current behavior until set).
- **Done when:** flipping the toggle on stamps the timestamp; the job ignores older conversations.

### Phase 1 — Eligibility pipeline refactor  ·  Status: ☐
- **Goal:** one clean Layer-1 scope shared by all modes.
- Extract eligibility into a single query incl. timeout, cutoff, attempt-limit, `BULK_ACTIONS_LIMIT`.
- Centralize attempt count read/increment helpers.
- **Done when:** job selects exactly the conversations defined in §5 Layer 1.

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
