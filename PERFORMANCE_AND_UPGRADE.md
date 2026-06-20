# Performance Investigation & Upstream Upgrade Log

> Work done June 2026. Two related efforts: (1) diagnosing the "Chatwoot is slow"
> complaints, and (2) upgrading the fork from v4.11.1 → v4.15.1 (which carries the
> most relevant performance fixes). Read this before re-investigating slowness or
> doing the next upstream merge.

---

## Part 1 — Performance Investigation (agents report "system is slow")

### Trigger
Agent survey (`Omnichannel Platform Feedback`) — 40 agents, **100% reported slowness**
("slow to load", "Disconnected", "messages don't appear until I refresh", "messages
fail to send"). Most agents have only 1–2 inboxes (~1–2k conversations each).

### Root cause: geographic latency, NOT the server
The production origin (VPS `72.61.193.158`, hostname `srv983901`) is hosted in
**France**; agents are in the **UAE** (Etisalat IPs `86.98.x` / `87.201.x`) and the
**Philippines**. France↔UAE ≈ **120–150 ms round-trip**. Chatwoot's SPA makes many
sequential API calls + a persistent WebSocket, so the latency compounds.

**The server itself is healthy** (measured at peak):
- Rails request times: **14–90 ms** (rare 294/685 ms outliers).
- Load average **~1.3 on 8 cores** even at peak; Sidekiq queues **empty**.
- Open-count query: **24 ms**, fully cached.
- DB size: **95,826 conversations / 1.4M messages** — queries fast, NOT the bottleneck.

### What was ruled OUT
- **~100k conversations** — queries run in tens of ms; not the cause.
- **Over-shared box** — real but not the *active* bottleneck. The single 8-core / 31 GB
  VPS also runs: Chatwoot dev stack, **Odoo prod + Odoo dev** (native, at
  `/opt/odoo-source/odoo19`, invisible to `docker stats`), **Plane** (~12 containers),
  **Postiz**, **Temporal + Elasticsearch**, Evolution, n8n, Flowise.
- **Sidekiq backlog** — queues empty at peak.

### Amplifiers found (via Chrome DevTools on a real agent session)
1. **Responses were uncompressed** — transferred size ≈ resource size. WhatsApp
   conversation-list responses were **80–124 kB each**, ~13+ loaded at once.
2. **Server was HTTP/1.1** — browser caps ~6 connections/host; the app fires 30–40
   requests + a WebSocket → they queue. Over a high-latency link this produced
   intermittent **10–28 second stalls** (1.5 kB requests taking 28 s; DOMContentLoaded 18 s).
3. **`status=all` filter + many inboxes + multiple tabs** — agents hid "Resolve",
   use the "All" filter, so every inbox loads its full list; each open tab re-fetches
   everything and opens its own WebSocket.
4. **99.8% of conversations are open** (95,625 / 95,826) — nothing is ever resolved,
   so lists never shrink.

### Fixes APPLIED (live on production VPS, nginx)
Edited `/etc/nginx/sites-enabled/chatwoot` (inside the `listen 443 ssl` server block):

1. **gzip compression** — added:
   ```nginx
   gzip on;
   gzip_vary on;
   gzip_proxied any;          # required: nginx won't compress proxied responses without this
   gzip_comp_level 5;
   gzip_min_length 1024;
   gzip_types application/json application/javascript text/javascript text/css text/plain application/xml image/svg+xml;
   ```
   Result: conversation-list response **96.7 kB → 11.6 kB (~8×)**. The key type is
   `application/json` (the API payloads).

2. **HTTP/2** — changed `listen 443 ssl;` → `listen 443 ssl http2;` (nginx 1.24 syntax;
   1.25.1+ uses the separate `http2 on;` directive). Verified with
   `curl -sI https://chat.tabeertours.com/ | head -1` → `HTTP/2`.

Apply changes with `nginx -t && systemctl reload nginx`.

### Fixes PENDING / recommended (in priority order)
1. **Cloudflare in front of `chat.tabeertours.com`** (stopgap) — edge TLS in Dubai,
   warm/reused origin connection, edge compression, + Argo Smart Routing. Mitigates
   but doesn't cure the France↔UAE distance.
2. **Relocate the origin to a UAE datacenter (~5–20 ms) or Mumbai `ap-south-1`
   (~40–50 ms)** — the real fix. Going 130 ms → 20 ms is transformative. PH office
   can't be close to both; optimize for UAE (36/40 agents).
3. **"One tab per agent"** — behavioral, free; each tab multiplies requests + sockets.
4. **Archive feature** (parked — see below) — to stop loading 99.8%-open lists.
5. **Fix `Notification::PushNotificationJob`** — failing ~1,800/day with
   `MultiJson::ParseError` (dead set pegged at 9,999). Agent web-push is broken;
   likely a corrupt push-subscription record. Separate bug, not a slowness cause.

### Archive feature (parked, agreed direction)
Team **never resolves** conversations, **hid the Resolve action**, and **all agents use
the "All" filter** — which is *why* lists are heavy. They want an **Archive** feature.
For it to both fit the workflow and help performance it must be a state that is
**excluded from the default/All view** (unlike Chatwoot "Resolved", which still shows
in All), is **restorable**, and **auto-reopens on a new customer message**. This is a
code change (no native Chatwoot equivalent). The survey's most-requested missing
feature was also "Can't archive old chats." Design decision deferred.

### How to re-verify (read-only diagnostics)
```bash
# On VPS (during peak ideally):
uptime; nproc; free -h
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
ps -eo pcpu,pmem,rss,args --sort=-pcpu | grep -iE "odoo|postgres|python" | head   # native Odoo
cd /opt/chatwoot
docker compose -f docker-compose.custom.yaml exec -T rails bundle exec rails runner '
  require "sidekiq/api"; Sidekiq::Queue.all.each{|q| puts "#{q.name}: size=#{q.size} latency=#{q.latency.round(1)}s"}'
curl -sI https://chat.tabeertours.com/ | head -1                                  # expect HTTP/2
# Client-side: agent runs `ping 72.61.193.158` (expect ~120-150ms from UAE),
# and DevTools Network → check content-encoding: gzip + response sizes.
```

---

## Part 2 — Upstream Upgrade v4.11.1 → v4.15.1

### Why
4.13–4.15 contain the most on-point performance fixes for the above:
- `perf: merge 3 conversation COUNT queries in /meta into single query` (#13536)
- `chore: relax conversation meta polling for high-volume accounts` (#14518)
- `perf: eliminate N+1 queries on inboxes#index` (#14451)
- `perf: skip conversation loading in /meta endpoint` (#13564, in 4.12)
- `perf: reduce presence update frequency + background tab throttling` (#13726, in 4.12)
- message query/index optimizations.

### Path & branches
- Done on the **`omni-dev`** branch, **locally** (not yet pushed/deployed at time of writing).
- Upgrade chain: **4.11.1 → 4.12.1 → 4.15.1** (two sequential merges).
- **Backup branches** (for rollback): `backup-omni-dev-pre-4.12.1`,
  `backup-omni-dev-pre-4.15.1`.
- Commits: `Merge upstream v4.12.1`, `fix(inbox): restore Switch/SettingsSection
  imports for idle reassignment`, `Merge upstream v4.15.1`.

### Conflict resolution principles
Keep our customizations (JIVO, Odoo, Evolution WhatsApp, idle reassignment, hidden
resolve), adopt upstream refactors where they're equivalent or better, converge with
upstream when it removes future conflict (e.g. Facebook messaging).

#### v4.12.1 — 9 conflicts
| File | Resolution |
|---|---|
| `account.rb` | keep `jivo_v2_agent`; add upstream `reporting_timezone`/`captain_auto_resolve_mode` + `AccountCaptainAutoResolve` |
| `send_on_facebook_service.rb` | keep `RESPONSE` (intentional fork fix), drop upstream `MESSAGE_TAG` |
| `Message.vue` | keep JIVO/Captain bot types + upstream `senderType` check |
| `ReplyBox.vue` | keep `jivoAssistants/get` + upstream `onReplyToMessage` handler |
| `inbox/Index.vue` | upstream new layout+search + re-integrate Evolution status badge & Reconnect |
| `InboxChannels.vue` | keep `wrapperRef` scroll fix + upstream layout |
| `IntegrationHooks.vue` | keep `integrations/get` mount fix (upstream did same) |
| `Gemfile.lock` | `ai-agents 0.9.1`; `bundle install` |
| `db/schema.rb` | version max; migrations run + re-dump |

**Post-merge regression fixed:** upstream's Assignment-V2 refactor rewrote the imports
of `CollaboratorsPage.vue` and dropped `Switch` + `SettingsSection` imports — the
auto-merge kept our idle-reassignment template, so its toggle silently failed to
render. Fix: re-added both imports. (This class of bug — template kept, import dropped
by auto-merge — only shows as a **"Failed to resolve component"** warning in the
browser console, not in eslint/server logs. Watch for it.)

#### v4.15.1 — 19 conflicts
| File | Resolution |
|---|---|
| `account.rb` | keep custom methods; adopt `AccountSettingsSchema` concern (inline schema → concern, **identical**, ~45 lines moved not lost) |
| `send_on_facebook_service.rb` + spec | converge on upstream `merge_human_agent_tag` (defaults to RESPONSE when `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT` unset = our behavior) |
| `hook_job.rb` | adopt upstream `INTEGRATION_PROCESSORS` hash dispatch, **ADD `'odoo' => :process_odoo_integration_with_lock`** (upstream hash was missing odoo — would have silently broken Odoo sync) |
| `hook_listener.rb` | union odoo + linear events |
| `integrations/hook.rb` | keep `validate_odoo_connection` + upstream `validate_openai_api_key` |
| `integrations_notification_mailer.rb` | keep odoo mailers + upstream `openai_disconnect` |
| `_account.json.jbuilder` | keep jivo/hide_resolve fields; use upstream `resource.onboarding_step` |
| `SingleIntegrationHooks.vue` | keep needed imports (`computed/ref/watch/onMounted/useI18n`), drop `defineProps/defineEmits` macro imports |
| `actionCable.js` | keep `onEvolutionConnected` + upstream voice_call/enrichment handlers |
| `inbox.rb` | keep `auto_reassignment_enabled_since` + upstream `dispatch_reauthorization_event` |
| `ChannelItem.vue` | keep `evolution_whatsapp` + upstream `whatsapp_call` checks |
| `ReplyTopPanel.vue` | keep `executeJivoCopilotAction`, adopt upstream `toggleEditorSize` (drop obsolete `togglePopout`) |
| `Editor.vue` | upstream `hasSelection` (skips NodeSelection) + keep `publishEditorSelection` (JIVO) |
| `features.yml` | keep `channel_evolution_whatsapp` + `companies` `chatwoot_internal` |
| `en.yml` | place upstream `limit_exceeded` under `custom_tool`; keep `jivo:` section |
| `lib/events/types.rb` | union `CONVERSATION_TAKEN` + `CONVERSATION_UNREAD_COUNT_CHANGED` |
| `Gemfile.lock` | `ai-agents 0.10.0`, `hashie 5.1.0`; `bundle install` |
| `db/schema.rb` | version `2026_06_11_184600`; 25 migrations run + re-dump (zero diff) |

### Verification performed (both merges)
- All conflict markers gone; `git diff --diff-filter=U` empty.
- `ruby -c` OK on every edited `.rb`; changed Vue/JS files lint clean.
- Referenced upstream symbols exist: `AccountSettingsSchema.SETTINGS_PARAMS_SCHEMA`,
  `validate_openai_api_key`, `account.onboarding_step`.
- `bundle install` clean; all pending migrations applied; `schema.rb` re-dumped with
  **zero diff** vs manual resolution (Rails agreed).
- App boots **HTTP 200** locally (`overmind start -f Procfile.dev`).
- Cross-check: 22 customization markers all present in final tree.

### Known non-blocking issues
- **`annotaterb`** throws `RubyParser::V34 undefined` after `db:migrate` — pre-existing
  tooling issue (runs *after* schema dump). Migrations & dump succeed.
- **`rack-mini-profiler`** logs `NameError: uninitialized constant Rack::File` in dev —
  Rack version incompatibility from the upgrade; dev-only profiler asset, harmless,
  not present in production.

### Behavior changes to watch when testing
- **Assignment V2** fully rolled out in 4.15 — verify auto-assignment.
- Facebook now routes through `merge_human_agent_tag` (same RESPONSE result; can enable
  HUMAN_AGENT / 24h-follow-up later via `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT`).

### Remaining steps
1. Local browser test (areas: inbox settings list + search + Evolution status/reconnect,
   Collaborators idle-reassignment toggle, reply box + JIVO, Odoo single-hook page,
   message bubbles, Facebook send). Keep DevTools console open for "Failed to resolve
   component" warnings.
2. Push `omni-dev` → auto-deploys to **dev-chat.orbitechsol.com** → test with real
   WhatsApp / Odoo / Facebook data.
3. Merge to prod branch + deploy per `INFRA.md`.
