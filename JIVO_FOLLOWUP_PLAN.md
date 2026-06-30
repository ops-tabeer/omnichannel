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
   - **AI ON** → `idle_prompt`; the AI returns an **action** + message (see decision 7).
   - **AI OFF** → `idle_message`; send fixed text every attempt. **Zero AI calls.**
2. **Counting stays in code** (`jivo_idle_reminder_count`); the AI only decides the action/message — never counts attempts.
3. **On limit reached (deterministic backstop, no AI)** → `on_limit_action`: `handoff` (default) / `none`. `resolve` dropped (no auto-closing). `none` = admin opt-out of escalation.
7. **AI action set = `follow_up` / `handoff` / `wait`** (resolve dropped):
   - `follow_up` → send the message, increment attempt count.
   - `handoff` → escalate to a human now (e.g. the prompt says "if the number is already present, hand off"). Solves the "skip but don't orphan" edge case.
   - `wait` → do nothing this cycle; it's the customer's turn. Legitimately stays `pending` until they reply (guarded so it doesn't re-call the AI without a new customer message). Not an orphan.
   - On AI error/invalid output → safe fallback: take no action this run and retry later (bounded by the attempt-limit backstop), so a broken AI can't act wrongly or loop on cost.
4. **Enabled-since cutoff**: only act on conversations **created after** the feature was enabled (`idle_action_enabled_at`). Mirrors `auto_reassignment_enabled_since`.
5. **Runs before handoff** (`pending`); inbox idle reassignment runs after handoff. Escalation = handoff = the baton-pass.
6. **Usage counter** (Super Admin, per account, per month) tracks **AI calls** (each call = cost), optionally broken down by action (`follow_up` / `handoff` / `wait`). Static mode = no AI call = nothing counted. **Final phase.**

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
| `on_limit_action` | enum | **new (Phase 2)** | Deterministic backstop after limit: `handoff` (default) / `none`. `resolve` dropped. |
| `idle_action_enabled_at` | iso8601 | **new (Phase 0)** | Cutoff timestamp; auto-set when `feature_idle_action` flips false→true (system-managed) |

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
      apply on_limit_action (handoff | none); stop          # deterministic backstop, no AI
      # handoff leaves the pending scope; 'none' stays but is a cheap no-op each run
    elsif idle_use_ai:
      if no NEW customer message since last AI check: do nothing (no call)   # skip-loop guard
      result = AI call (idle_prompt + conversation context)   # COUNT this call
      case result.action:
        when 'follow_up': post result.message; increment count
        when 'handoff':   escalate (handoff); stop
        when 'wait':      record last-checked marker (no message, no count bump)
        else (error/invalid): no action this run; retry later (bounded by backstop)
    else:
      post idle_message; increment count                       # no AI call
```

**Attempt spacing is automatic:** every message bumps `last_activity_at` (`Message#set_conversation_activity`), so a sent follow-up resets the idle timer → the next attempt can't fire until another full `idle_timeout_minutes` passes. No extra spacing logic needed.

**Escalation timing matches the ask** ("check 2 times, handoff on the 3rd"): with limit=2, cycles 1–2 send follow-ups (count→2), cycle 3 sees `attempts >= limit` → handoff. This is why attempt count is a per-conversation branch, not a scope filter.

**Skip-loop guard (AI mode):** a `wait` sends no message, so `last_activity_at` is *not* bumped → the chat would re-qualify and re-call the AI every run for no reason. Guard with a "last checked" marker (mirror `Jivo::ContactEnrichmentService`'s `jivo_contact_enriched_message_id`): only call the AI when a **new incoming customer message** exists since the last check. `wait` then costs ≤1 call until the customer says something new.

**Orphan safety:** the "number already present, no nudge needed" case → the prompt tells the AI to return `handoff`, not `wait`, so the chat doesn't sit forever. And the deterministic attempt-limit → `handoff` backstop catches any AI error / endless `wait`.

AI call JSON contract (reuse V1 handler pattern, `response_format: json_object`):
```json
{ "action": "follow_up | handoff | wait", "message": "<follow-up text, in customer's language; required only for follow_up>" }
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

### Phase 2 — Static follow-up loop + escalation  ·  Status: ✅ (omni-dev)
- **Goal:** ship the free path end-to-end (no AI), proves scheduling + cutoff + limit.
- `apply_idle_action` rewritten: if `attempt_count >= idle_reminder_limit_value` → `escalate`, else `send_follow_up` (post static `idle_message`, `increment_attempt`).
- `escalate` → `on_limit_action_value`: `handoff` (default) / `resolve` / `none` (no-op).
- Added `on_limit_action` config (store_accessor + controller permit + `on_limit_action_value` with legacy `idle_action` fallback + `ON_LIMIT_ACTION_NONE`/`ON_LIMIT_ACTIONS`/`DEFAULT_ON_LIMIT_ACTION`).
- `default_idle_message` simplified to the check-in text (follow-up is always a nudge now).
- Removed dead code: `idle_action_value`, `IDLE_ACTIONS`, `IDLE_ACTION_REMINDER`.
- Spacing is automatic (sent message bumps `last_activity_at`); limit=2 → 2 nudges then handoff on cycle 3.
- **Done when:** an eligible pending chat gets up to N static nudges, then escalates; nothing fires before cutoff. ✓ (still UI-hidden until Phase 4)

### Phase 3 — AI follow-up mode  ·  Status: ✅ (omni-dev)
- ✅ **Shared handoff extracted** — `Jivo::HandoffService` (optional private note → `ai_handoff` → `bot_handoff!` → OOO). V2 `HandoffTool` and the idle job use it; V1 to adopt later.
- ✅ `idle_use_ai` + `idle_prompt` config (+ `idle_use_ai_enabled?`).
- ✅ `Jivo::Tasks::IdleFollowUpService` — returns `{action, message}`, degrades to safe `wait`.
- ✅ Wired into the job loop:
  - count ≥ limit → `escalate` (deterministic backstop, **no AI call**).
  - else AI ON → `ai_follow_up`: `follow_up` (send + count), `handoff` (direct, always), `wait` (count; **same-cycle handoff** if it reaches the limit).
  - else AI OFF → static `idle_message` + count.
- ✅ **No skip-loop guard needed** — `wait` counts toward the limit, so calls are capped at `idle_reminder_limit` per conversation and a handoff always terminates it. (Decision changed from the earlier guard approach.)
- ✅ Dropped `resolve` everywhere (`on_limit_action` = `handoff`/`none`; removed `IDLE_ACTION_RESOLVE` + dead `idle_resolve` string).
- **Done when:** prompt "if no number ask for it, if number present hand off" → missing-number chats get an AI nudge, number-present chats hand off, and a chat is never AI-called more than `limit` times before handoff. ✓ (still UI-hidden until Phase 4)

### Phase 4 — Settings UI (un-hide + finalize)  ·  Status: ✅ (omni-dev)
- ✅ Replaced the commented block in `JivoAssistantForm.vue` with live controls: master toggle (`feature_idle_action`) + help, `idle_timeout_minutes`, `idle_reminder_limit`, `on_limit_action` select (handoff/none), `idle_use_ai` toggle, and AI toggle reveals `idle_prompt` (AI ON) vs `idle_message` (AI OFF). Form `config` initializes the new keys; dropped legacy `idle_action`.
- ✅ New i18n in `jivo.json` (`FEATURE_IDLE_ACTION.HELP`, `IDLE_TIMEOUT`, `IDLE_REMINDER_LIMIT`, `ON_LIMIT_ACTION`, `IDLE_USE_AI`, `IDLE_PROMPT`, `IDLE_MESSAGE`); removed `IDLE_ACTION`.
- ✅ Hardened the cutoff callback to **preserve `idle_action_enabled_at`** across form saves (the controller replaces the whole `config` and the form doesn't carry the system-managed key).
- **Done when:** admin can configure everything in Settings → JIVO → Behavior; saves persist; enabling stamps the cutoff. ✓

### Phase 5 — Guardrails & polish  ·  Status: ☐
- **Goal:** production hardening.
- Per-conversation failure isolation (already in job `rescue`), logging, sane defaults/validation (timeout ≥ 1, limit ≥ 1).
- Confirm clean handoff baton-pass with inbox reassignment (§6).
- Optional: activity-message wording for follow-ups.
- **Done when:** misconfig/AI errors degrade gracefully; no double-acting with reassignment.

### Phase 6 — Super Admin monthly AI-call usage counter  ·  Status: ☐  ·  **(LAST)**
- **Goal:** at-a-glance per-account monthly usage ("credits").
- Count **AI calls** only (Phase 3 path), broken down by action (`follow_up` / `handoff` / `wait`). Static mode not counted.
- **Storage (scalable):** monthly aggregate row, e.g. table `jivo_ai_usages`
  `(account_id, period 'YYYY-MM', kind 'follow_up', follow_up_count, handoff_count, wait_count, timestamps)`,
  unique on `(account_id, period, kind)`, atomic upsert/increment at call time.
  (Simpler alt: increment `account.custom_attributes`; less scalable, avoid.)
- **Display:** add the current-month count to the Super Admin → Accounts view.
- **Done when:** each AI follow-up call increments the right monthly row; Super Admin shows e.g. "JIVO follow-up AI calls (2026-07): 312 — 190 follow-up / 80 handoff / 42 wait".

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
