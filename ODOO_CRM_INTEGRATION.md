# Odoo CRM Integration — Design & Plan

Status: **Planned / agreed** (not yet implemented)
Branch: `omni-dev`

One-directional **Chatwoot → Odoo** lead sync, built inside the existing `Crm::`
integration framework (mirrors the LeadSquared integration: processor + mappers +
setup + API client under `app/services/crm/`, wired through
`Integrations::Hook` → `HookListener` → `HookJob`).

---

## Goals (requirements)

1. When a **handed-off** conversation is **Taken** by an agent, create the lead in
   Odoo CRM with that agent as the assignee (salesperson).
2. When the conversation is **reassigned** (e.g. by Fey/Jasmine), update the
   salesperson on the same Odoo lead.
3. **Block** changing the salesperson directly inside Odoo for Chatwoot-managed
   leads — show an error telling the user to reassign from Chatwoot.
4. Every synced lead must carry a **reference link** back to the originating chat.
5. The assignee is **emailed** when a conversation is taken/assigned.

---

## How Chatwoot connects to Odoo

- Uses Odoo's built-in **External API over JSON-RPC** (`POST {url}/jsonrpc`).
  No endpoint is created on the Odoo side; the API ships with every instance.
- Talks to Odoo with **HTTParty** (no `xmlrpc` gem — removed from Ruby 3.4 stdlib).
- Authenticates as a **dedicated Odoo bot user**:
  1. `service: "common", method: "authenticate"` → `uid`
  2. `service: "object", method: "execute_kw"` for `crm.lead` / `res.partner` /
     `res.users` operations.
- Credentials stored in the hook `settings`; the `api_key` lives in the encrypted
  `access_token` column. Server-side only, authenticated + TLS on every call.
- The bot identity is also what makes requirement 3 enforceable — Odoo can allow
  salesperson changes from the bot `uid` and block them from human users.

### Connection settings (Odoo integration config)

| Setting | Example | Purpose |
|---|---|---|
| `url` | `https://yourco.odoo.com` | Instance base URL |
| `db` | `yourco-prod` | Database name |
| `login` | `chatwoot-bot@yourco.com` | Dedicated bot user |
| `api_key` | (generated in Odoo) | Auth secret (Preferences → Account Security) |
| `enabled_inbox_ids` | `[1, 4]` | Inboxes allowed to sync (see scoping) |

---

## Triggers

| Event | Condition | Action |
|---|---|---|
| **`conversation.taken`** (new event dispatched from the `take` action) | handed-off convo, inbox enabled, no Odoo lead yet | **CREATE** lead; salesperson = `conversation.assignee` |
| `assignee.changed` | Odoo lead already exists, inbox enabled | **UPDATE** salesperson |
| `assignee.changed` | no lead yet (pre-Take idle bounce) | **ignore** |
| `contact.updated` | contact now has real email/phone, has a managed lead | **replace placeholder** email/phone on the lead |

### Why "Take" and not assignment

The custom **"Take" button** (`POST /:id/take`) sets a `taken_at` timestamp on a
conversation that is **already assigned** to the agent. It is *not* a self-assign.
`taken_at` is also the permanent stop for `AutoAssignment::IdleReassignmentService`
— before Take, a handed-off conversation can bounce between agents (firing
`assignee.changed` repeatedly); after Take it never auto-reassigns again. So:

- **Take** is the deliberate "this agent now owns it" moment → create the lead.
- Any `assignee.changed` *after* a lead exists is a real reassignment → update.
- `assignee.changed` *before* Take (idle bouncing) has no lead yet → ignored.

The salesperson is always `conversation.assignee` (matched to an Odoo `res.users`
by **email**), even if an admin clicked Take on someone else's behalf.

---

## Records & dedup

- **Lead = per conversation.** Odoo lead id stored in
  `conversation.additional_attributes['odoo']`.
- **Partner = per contact.** `res.partner` find-or-create:
  1. Reuse `contact.additional_attributes['external']['odoo_partner_id']` if set.
  2. Else search Odoo by **real** email, then real phone (skip placeholders).
  3. Else create a partner, then store its id on the contact.

This guarantees one partner per customer (across conversations) and one lead per
conversation, with no duplicates on re-sync.

---

## `crm.lead` field mapping

Target Odoo modules: `travel_agency_crm` + `lead_integrations` (Odoo 19, custom
Python fields, no Studio).

| Odoo field | Value from Chatwoot | Notes |
|---|---|---|
| `partner_id` ✱ | find-or-create `res.partner` | required |
| `email_from` ✱ | `contact.email`, else placeholder `noreply+conv<id>@chat.tabeertours.com` | required; replaced on `contact.updated` |
| `phone` ✱ | `contact.phone_number`, else `additional_attributes['raw_phone_number']`, else placeholder `N/A` | required; replaced on `contact.updated` |
| `user_id` | assignee → `res.users` by login(email) | the salesperson |
| `company_id` | the matched assignee user's `company_id` | lead lands in the assignee's company; falls back to bot's default company when no user matches |
| `lead_assignment_state` | constant `"accepted"` | prevents Odoo from auto-reassigning the lead |
| `assignment_deadline` | **not sent** (left empty) | leaving it unset stops the auto-reassign timer |
| `external_source_id` | Chatwoot **conversation id** | dedup key + req-3 "managed" marker |
| `communication_channel` | inbox channel → `messenger` / `whatsapp` / `website_chat` / `email` / `other` | derived |
| `source_platform` | `facebook` (Messenger) / `instagram` / else `custom_api` | derived |
| `description` | chat **deep link** (req 4) + contact name | Html, clickable |
| `name` | **not sent** | auto-set by the module's sequence on create |
| `inquiry_type` | **not sent** (left unset) | view-required only; AI could classify later |
| `lead_source` | **not sent** (left unset) | — |

✱ = required on create (DB-level). Messenger leads often lack email/phone, so
**placeholders** are sent and overwritten when real values arrive.

Selection fields must be sent as exact stored values (see the module field
inventory shared by the Odoo team).

---

## Handoff note → lead chatter

When the lead is created (on Take), the **AI handoff note** is posted to the lead's
chatter. The handoff note is a private message created by `Jivo::Tools::HandoffTool`
with `sender` = the assistant (`sender_type = 'JivoAssistant'`), which distinguishes
it from agents' own private notes (`sender_type = 'User'`).

```
execute_kw(db, uid, key, 'crm.lead', 'message_post', [[lead_id]],
  { body: <note content>, message_type: 'comment', subtype_xmlid: 'mail.mt_note' })
```

`mail.mt_note` posts an **internal log note** (not emailed to followers).

---

## Per-inbox scoping

A single account-level Odoo hook holds the connection. The integration settings
include an **inbox multi-select** stored as `enabled_inbox_ids` in the hook
settings. Every processor action is gated:

```ruby
return unless enabled_inbox_ids.include?(conversation.inbox_id)
```

Default is **explicit opt-in** — nothing syncs unless the inbox is enabled.

---

## Requirement 3 — block manual reassignment in Odoo (Odoo side)

Enforced inside Odoo (Chatwoot cannot block edits made in Odoo). An **automated
action / server action** on `crm.lead` write: when `external_source_id` is set
(i.e. the lead came from Chatwoot) and `user_id` is being changed by a **non-bot**
user, raise a `UserError` ("Reassign this lead from Chatwoot, not Odoo"). The bot
user's own writes (Chatwoot syncs) are allowed. No extra custom field is needed —
`external_source_id` presence is the marker. (Python snippet provided separately.)

## Requirement 5 — email the assignee

Use Chatwoot's built-in `conversation_assignment` email notification
(`AgentNotifications::ConversationNotificationsMailer`). Just ensure the setting is
enabled for the relevant agents; no new code.

---

## Related side-fix — phone enrichment

`app/services/jivo/contact_enrichment_service.rb` extracts email/phone from chat
messages into the contact. Email saves, but **phone often does not**, because
`normalized_phone_number` calls `TelephoneNumber.parse(value)` with **no default
country** — local-format numbers (e.g. `03001234567`) fail validation. The
`Contact` model also hard-validates `phone_number` against strict E.164
(`/\+[1-9]\d{1,14}\z/`), so a local-format number **cannot** be stored on
`phone_number` at all. Implemented fix:

- Scan recent incoming messages for email AND phone **separately**, so a phone sent
  in a different message than the trigger is still captured.
- `normalized_phone_number` now returns `parsed.e164_number` (contiguous
  `+923049356118`), **not** `international_number` (space-formatted `+92 304 ...`).
  The space-formatted variant failed the model's `/\+[1-9]\d{1,14}\z/` validator and
  raised on `update!` — so even valid numbers were being dropped before this fix.
- Valid E.164 numbers are stored on `contact.phone_number` as before. When the
  number can't be parsed to E.164, the **raw digits are stored in
  `contact.additional_attributes['raw_phone_number']`** (never dropped) — the model
  rejects them on `phone_number`. Email and phone are written so a rejected phone
  never rolls back the email.
- **Odoo consumption (Phase 2/4):** the lead/partner mapper uses
  `contact.phone_number` when present, else falls back to
  `additional_attributes['raw_phone_number']`, else the `N/A` placeholder.

Better contact data → fewer Odoo placeholders.

---

## Components to build

1. `Crm::Odoo::Api::Client` — JSON-RPC authenticate + `execute_kw`.
2. `Crm::Odoo::ProcessorService` — `handle_taken`, `handle_assignee_changed`,
   `handle_contact_updated` (placeholder replacement).
3. `Crm::Odoo::Mappers::LeadMapper` — lead/partner field mapping.
4. `Crm::Odoo::SetupService` — validate credentials on connect.
5. Wiring — `config/integration/apps.yml` (`odoo` block + inbox multi-select),
   `Integrations::Hook#crm_integration?`, `Crm::SetupJob`, `HookListener`
   (`conversation.taken`, `assignee.changed`, `contact.updated` +
   `supported_events_map`), `HookJob` routing.
6. New `conversation.taken` event dispatched from the `take` controller action.
7. Phone enrichment fix in `Jivo::ContactEnrichmentService`.
8. Odoo automated-action snippet for requirement 3 (delivered to the Odoo team).

---

## Phased rollout

Each phase is independently testable and shippable. Earlier phases deliver value
without depending on later ones.

### Phase 0 — Phone enrichment fix ✅ implemented
- `Jivo::ContactEnrichmentService`: store raw digits when unparseable; scan recent
  messages for email and phone separately.
- Small, self-contained, no Odoo dependency. Reduces placeholders later.
- **Done when:** local-format phone numbers reliably save to the contact.

### Phase 1 — Connection & setup (foundation, no triggers) ✅ implemented
- `Crm::Odoo::Api::Client` (JSON-RPC authenticate + `execute_kw`).
- `odoo` block in `config/integration/apps.yml` (incl. inbox multi-select),
  `Integrations::Hook#crm_integration?`, `Crm::SetupJob`, `Crm::Odoo::SetupService`.
- **Done when:** the integration can be configured in the UI and validates
  credentials against Odoo on connect. No leads created yet.

Implementation notes:
- **Synchronous validation on connect:** `Integrations::Hook#validate_odoo_connection`
  (a `validate ... on: :create`) calls `SetupService#validate_connection!`, which
  authenticates the bot user and reads its display name. Bad credentials block the
  create with a form error ("Could not connect to Odoo: …") instead of a silent
  failure; on success the resolved `uid` + `connected_user` (bot name) are stored.
- The async `Crm::SetupJob` then **moves `api_key` from `settings` into the encrypted
  `access_token` column** and strips it from settings (reusing the uid/connected_user
  from validation, so no second auth round-trip).
- **"Connected as" status:** `SingleIntegrationHooks.vue` shows
  "Connected to Odoo as &lt;bot user&gt;" from `hook.settings.connected_user`.
- Inbox multi-select: `enabled_inbox_ids` rendered as a checkbox group in
  `NewHook.vue` (connect form) **and** editable after connection on the
  `SingleIntegrationHooks.vue` card (Save → `integrations/updateHook` →
  `PATCH /integrations/hooks/:id`, sends full merged settings so other keys are
  preserved). Stored in hook `settings`; consumed by the Phase 2 per-inbox gate.
- `crm_integration` feature flag must be enabled on the account for the integration
  to appear. Logo assets `public/dashboard/images/integrations/odoo{,-dark}.png` are
  the official Odoo CRM app icon (transparent background, same file for both themes).

### Phase 2 — Create lead on Take (req 1 + 4) ✅ implemented
- New `conversation.taken` event dispatched from the `take` controller action.
- `HookListener` + `HookJob` routing; per-inbox `enabled_inbox_ids` gate.
- `Crm::Odoo::ProcessorService#handle_taken`, `LeadMapper`, partner
  find-or-create, placeholders, store lead/partner ids, chat reference link.
- **Done when:** taking a handed-off conversation creates a correctly-mapped lead
  with the right salesperson and chat link.

### Phase 3 — Update salesperson on reassignment (req 2) ✅ implemented
- `assignee.changed` wired through `HookListener` (`assignee_changed`) +
  `HookJob#process_odoo_integration` (shared dispatcher with Take, same per-hook
  `CRM_PROCESS_MUTEX`).
- `Crm::Odoo::ProcessorService#handle_assignee_changed`: per-inbox gate; only acts
  when a lead already exists (the `assignee.changed` that fires alongside the initial
  Take, and any pre-Take idle bounce, are ignored). Reuses `salesperson_fields`
  (assignee Odoo user → `fallback_user_login` → none) and `write`s `user_id`/`company_id`
  when one resolves.
- Posts a chatter note via `message_post` (`subtype_xmlid: mail.mt_note`, internal log
  note) on every genuine reassignment — even when no Odoo user resolves — so the change
  is visible in Odoo: "Conversation reassigned to &lt;agent&gt; via Omni." /
  "Conversation unassigned via Omni." Failures route through `notify_sync_failure`.
- **Done when:** reassigning a taken conversation updates the lead's salesperson and
  logs a chatter note; pre-Take changes are ignored.

### Phase 4 — Handoff note + lead enrichment + placeholder replacement
- ✅ **Handoff note → chatter:** `handle_taken` posts the AI handoff reason (latest
  private `JivoAssistant` message) to the lead chatter via `message_post`
  (`mail.mt_note`), body `"AI handoff reason: <reason>"`. Skipped when no reason.
- ✅ **Lead enrichment (LLM):** `Crm::Odoo::LeadEnrichmentService` (mirrors
  `Jivo::Llm::ContactAttributesService`; uses the handoff assistant's OpenAI key + model,
  JSON mode, temp 0) extracts `inquiry_type` (selection key), `nationality`, `destination`
  (canonical country names) from the **handoff note + full conversation transcript**
  (`conversation.to_llm_text`). `ProcessorService#enrich_lead` resolves the two country
  names → `res.country` ids (`=ilike`) and writes `inquiry_type` / `nationality_id` /
  `destination_location` onto the lead. Best-effort: its own rescue logs + Sentry only, so
  it never triggers a false "sync failed" email or blocks lead creation. (Odoo field facts:
  `inquiry_type` selection w/ 13 keys; `nationality_id`/`destination_location`/`origin_location`
  are many2one → `res.country`.) Deferred optimisation: have the agent emit these fields as
  handoff-tool params (zero extra call) — not done to avoid domain leakage into core Jivo.
- ✅ **Conversation summary:** reuses `Jivo::Tasks::SummarizeService` (same logic as the
  JIVO summary button) and adds it to the lead — **rich HTML in the Notes (`description`)
  field** and a **clean plaintext copy in the chatter**. (This Odoo instance's `message_post`
  runs every body through `plaintext2html`, escaping HTML, so the chatter can only show
  plaintext; the `description` html field keeps the rendered markup.) Markdown rendered via
  `ChatwootMarkdownRenderer` (`render_message` for Notes, `render_markdown_to_plain_text`
  for chatter). Best-effort with its own rescue.
- **Refactor:** the post-create chatter/LLM steps (handoff note + enrichment + summary) live
  in `Crm::Odoo::LeadArtifactsService`; `ProcessorService#handle_taken` just calls
  `.apply(lead_id, conversation)`. Handoff-note failures still propagate (→ sync-failure
  email); enrichment + summary swallow their own errors.
- ✅ **Contact → partner sync (placeholder healing + corrections):** `contact.updated` →
  `ProcessorService#handle_contact_updated`. Gated on the contact being linked
  (`external.odoo_partner_id`). Reads the partner's current email/phone and writes the
  contact's value for a field only when it **changed** and is **not already used by another
  partner** (uniqueness guard → skip taken values; never trips Odoo's email/phone
  constraint). Updates the **partner only** — the lead's email/phone follow the partner in
  this Odoo. Won't clear a value on blank. Works for both placeholder→real and real→corrected.
  Best-effort (log + Sentry). Wired via `HookListener` (`contact.updated` added to the odoo
  map; `contact_updated` handler already existed) + `HookJob#process_odoo_integration`.
- **Done when:** the handoff note + summary appear, the lead is auto-classified, and a
  linked contact's email/phone edits sync to Odoo. ✅ Phase 4 complete.

### Phase 5 — Odoo-side enforcement & email (req 3 + 5)
- ✅ **Req 5 — lead-created email:** `AdministratorNotifications::IntegrationsNotificationMailer
  #odoo_lead_created` (view `odoo_lead_created.liquid`) emails the **assignee** when a lead is
  created on Take, with a deep link to the Odoo lead (`<hook url>/odoo/crm/<lead_id>`) and the
  conversation. Sent from `ProcessorService#notify_lead_created` after a successful create.
- ⬜ **Req 3 — Odoo automated action (Odoo team deploys, not in repo):** block manual
  `user_id` (Salesperson) change on Chatwoot-managed leads. Marker = `chatwoot_conversation_url`
  is set (only Chatwoot-created leads have it). Allow the bot user (`ops@tabeertours.com`);
  raise `UserError` for anyone else. Base.automation on `crm.lead`, watched field `user_id`.
- **Done when:** manual salesperson edits in Odoo are blocked and assignees are emailed
  when their lead is created.

---

## Later (enhancements, not in v1)

- **Transcript on resolve → chatter:** on `conversation.resolved`, post the full
  chat transcript to the lead's chatter (mirrors LeadSquared's transcript activity).
  Use the same `message_post`; gate behind an enable toggle.
- **Activity log:** a structured per-conversation activity entry on the lead.
- **AI-classified `inquiry_type`:** let the assistant classify the inquiry into one
  of the module's selection values instead of leaving it unset.
