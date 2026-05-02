# JIVO AI — Captain AI Feature Replication Inventory

Complete feature inventory of Chatwoot's Captain AI, mapped for building **JIVO AI** equivalent. Each feature is broken down into discrete units we'll implement step by step.

---

## Table of Contents

0. [Development Conventions & Patterns](#0-development-conventions--patterns) ⚠️ **READ FIRST**
1. [Core Models & Schema](#1-core-models--schema)
2. [Assistant Management](#2-assistant-management)
3. [Knowledge Base & RAG](#3-knowledge-base--rag)
4. [Conversation Auto-Pilot (V1)](#4-conversation-auto-pilot-v1)
5. [Conversation Auto-Pilot (V2 — Multi-Agent)](#5-conversation-auto-pilot-v2--multi-agent)
6. [Copilot (Agent-side AI Assistant)](#6-copilot-agent-side-ai-assistant)
7. [Inline Agent Tasks](#7-inline-agent-tasks)
8. [Scenarios (Specialized Sub-Agents)](#8-scenarios-specialized-sub-agents)
9. [Custom Tools (HTTP-based)](#9-custom-tools-http-based)
10. [Built-in Agent Tools](#10-built-in-agent-tools)
11. [Memory & Auto-Learning](#11-memory--auto-learning)
12. [Multimodal — Audio & Vision](#12-multimodal--audio--vision)
13. [Settings & Guardrails](#13-settings--guardrails)
14. [Citations & Source Attribution](#14-citations--source-attribution)
15. [Multi-Language Support](#15-multi-language-support)
16. [Auto-Resolution](#16-auto-resolution)
17. [Usage Limits & Tracking](#17-usage-limits--tracking)
18. [Instrumentation & Observability](#18-instrumentation--observability)
19. [Events & Webhooks](#19-events--webhooks)
20. [Frontend & UI](#20-frontend--ui)

---

## 0. Development Conventions & Patterns

**This section is mandatory reading before implementing any JIVO feature.** All code MUST follow these existing Chatwoot conventions to stay consistent with the codebase.

### 0.1 Core Project Rules (from CLAUDE.md)

- **MVP focus**: Least code change, happy-path only
- **No defensive programming**: Trust internal code, only validate at system boundaries
- **No dead code**: Remove unused code, no backups, no commented-out code
- **No multiple versions**: Pick one approach, implement it
- **Avoid writing specs**: Unless explicitly asked

### 0.2 Ruby/Rails Conventions

#### Code Style
- **RuboCop**: Always run `bundle exec rubocop -a` after changes — 150 char max line length
- **Compact module/class definitions**: `class Module::Class` not nested `module Module; class Class; end`
- **`pattr_initialize`**: Use for service constructors (e.g. `pattr_initialize [:assistant!, :conversation!]`)
- **`store_accessor`**: For jsonb field accessors (e.g. `store_accessor :config, :temperature, :product_name`)
- **Polymorphic sender**: `has_many :messages, as: :sender, dependent: :nullify` for AI bots
- **Custom exceptions**: Place in `lib/custom_exceptions/`
- **No bare strings**: Use I18n for all user-facing text (`I18n.t('...')`)

#### Reference Files to Mirror
| What you're building | Reference file |
|---|---|
| Bot/Assistant model | [app/models/agent_bot.rb](app/models/agent_bot.rb) |
| Inbox join table | [app/models/agent_bot_inbox.rb](app/models/agent_bot_inbox.rb) |
| Service class | [app/services/conversations/event_data_creator_service.rb](app/services/conversations/event_data_creator_service.rb) |
| Background job | [app/jobs/send_reply_job.rb](app/jobs/send_reply_job.rb) |
| API controller | [app/controllers/api/v1/accounts/agent_bots_controller.rb](app/controllers/api/v1/accounts/agent_bots_controller.rb) |
| Concern/Module | [app/models/concerns/featurable.rb](app/models/concerns/featurable.rb) |

#### Database Conventions
- **Indexes**: Always add indexes on foreign keys + commonly queried columns
- **Validations**: Validate presence + uniqueness with proper indexes
- **jsonb**: Default to `{}` for hash fields, `[]` for array fields
- **Enums**: `enum status: { open: 0, resolved: 1, ... }` (integer-backed)
- **Timestamps**: Always include `t.timestamps`
- **Foreign keys**: Use `t.references :resource, foreign_key: true, null: false`

#### Service Class Pattern
```ruby
class Jivo::SomeService
  pattr_initialize [:required_arg!, :optional_arg]

  def perform
    # main logic
  rescue StandardError => e
    handle_error(e)
  end

  private

  def helper_method
    # ...
  end
end
```

#### Job Pattern
```ruby
class Jivo::SomeJob < ApplicationJob
  queue_as :high  # or :default, :low

  retry_on Net::ReadTimeout, attempts: 3, wait: 2.seconds

  def perform(record_id)
    record = Record.find(record_id)
    Jivo::SomeService.new(record: record).perform
  end
end
```

#### Controller Pattern
- Use strong params (`params.require(:resource).permit(:field1, :field2)`)
- Inherit from `Api::V1::Accounts::BaseController` (auto account scoping)
- Use Pundit policies (`authorize @resource`)

### 0.3 Vue/Frontend Conventions

#### Code Style
- **ESLint**: Run `pnpm eslint:fix` after changes
- **Vue 3 Composition API**: Always use `<script setup>` at top of file
- **No Options API**: Don't use `data()`, `methods:`, etc.
- **PascalCase**: Component names (`AssistantCard.vue`)
- **camelCase**: Events (`@click`, `@assistant-updated`)
- **No bare strings**: Use `useI18n()` and reference `en.json`

#### Tailwind Only — Strict Rules
- **No custom CSS files**
- **No scoped CSS** in components
- **No inline styles**
- **Use only Tailwind utility classes**
- **Colors**: Reference `tailwind.config.js` color palette
- **Use `components-next/`** for new components (the rest is being deprecated)

#### File Structure
```
app/javascript/dashboard/
├── api/jivo/             # Axios API clients
├── components-next/jivo/ # Vue components (new)
├── composables/useJivo.js # Shared composable
├── routes/dashboard/jivo/ # Vue Router routes
└── store/jivo/           # Vuex stores
```

#### Vue Component Template
```vue
<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';

const props = defineProps({
  assistant: { type: Object, required: true }
});

const emit = defineEmits(['update', 'delete']);

const { t } = useI18n();
const store = useStore();
</script>

<template>
  <div class="flex items-center p-4 bg-white rounded-lg">
    <h3 class="text-lg font-medium text-slate-900">
      {{ assistant.name }}
    </h3>
  </div>
</template>
```

#### API Client Pattern
```js
// app/javascript/dashboard/api/jivo/assistant.js
import ApiClient from '../ApiClient';

class JivoAssistantAPI extends ApiClient {
  constructor() {
    super('jivo/assistants', { accountScoped: true });
  }
  
  // Add custom methods here
}

export default new JivoAssistantAPI();
```

### 0.4 Naming Conventions

| Layer | Convention | Example |
|---|---|---|
| Database tables | snake_case plural with prefix | `jivo_assistants`, `jivo_inboxes` |
| Ruby classes | PascalCase with namespace | `Jivo::Assistant`, `Jivo::ConversationHandlerService` |
| Ruby methods | snake_case | `process_response`, `should_handoff?` |
| Vue components | PascalCase | `AssistantCard.vue`, `JivoSidebar.vue` |
| JS variables | camelCase | `assistantId`, `responseUsage` |
| API routes | snake_case | `/jivo/assistants/:id/copilot_threads` |
| Vuex actions | camelCase | `fetchAssistants`, `createDocument` |
| Events | camelCase | `assistantCreated`, `documentDeleted` |

### 0.5 I18n Conventions

- **Backend**: All strings in `config/locales/en.yml` only
- **Frontend**: All strings in `app/javascript/dashboard/i18n/locale/en.json` only
- **Other languages**: Don't touch — handled by community
- **Key structure**:
  ```yaml
  # en.yml
  jivo:
    assistant:
      created: 'Assistant created successfully'
      handoff_message: 'Connecting you with a human agent.'
  ```
  ```json
  // en.json
  "JIVO": {
    "ASSISTANT": {
      "CREATED": "Assistant created successfully",
      "DELETE_CONFIRM": "Are you sure?"
    }
  }
  ```

### 0.6 Database Migrations

- **Naming**: `YYYYMMDDHHMMSS_create_jivo_assistants.rb`
- **No data migrations** in schema migrations (use rake tasks)
- **Always reversible**: Use `change` method, not `up`/`down` unless necessary
- **Add indexes immediately** in same migration as table creation

### 0.7 Feature Flag Pattern

When adding new toggleable features, follow `Featurable` concern:
```yaml
# config/features.yml
- name: jivo_integration
  display_name: JIVO AI
  enabled: true
```
Then check via: `account.feature_enabled?('jivo_integration')`

### 0.8 Hook into Message Lifecycle

To trigger logic on new messages, **modify**:
- `app/services/message_templates/hook_execution_service.rb` (add to `trigger_templates`)

Not via:
- ❌ `Message` model callbacks directly
- ❌ Listeners (which fire after-the-fact)

### 0.9 Conversation Status Transitions

- Use existing methods: `bot_handoff!`, `pending!`, `open!`, `resolved!`
- Don't manually `update(status: ...)` — these methods dispatch events
- Set initial pending status via `Conversation#determine_conversation_status` (modify if needed)

### 0.10 Error Handling

- **Use `ChatwootExceptionTracker`** for exceptions:
  ```ruby
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
  ```
- **Don't swallow errors silently** — always log
- **Graceful degradation**: On AI errors, hand off to human

### 0.11 Authentication & Authorization

- **Pundit policies**: Create per resource (e.g. `Jivo::AssistantPolicy`)
- **API endpoints**: Auto-scoped by account via `BaseController`
- **User permissions**: Check role (administrator, agent) where appropriate

### 0.12 Testing (Optional but Encouraged)

- **Specs go in**: `spec/models/`, `spec/services/`, `spec/jobs/`, `spec/controllers/`
- **FactoryBot**: Use existing factories or create new (`spec/factories/jivo_assistants.rb`)
- **Run**: `bundle exec rspec spec/models/jivo/assistant_spec.rb`
- **Per CLAUDE.md**: Skip specs unless explicitly asked

### 0.13 Pre-Implementation Checklist

Before writing any code, confirm:
- [ ] Read this section (0) fully
- [ ] Reviewed reference file(s) for the pattern being used
- [ ] Identified existing similar feature to mirror (e.g. AgentBot for AI bots)
- [ ] Confirmed naming follows table 0.4
- [ ] Confirmed file location follows section 0.3
- [ ] No custom CSS / no Options API / no inline styles in any Vue files

### 0.14 Post-Implementation Checklist

After finishing a feature:
- [ ] `bundle exec rubocop -a` — backend lint passes
- [ ] `pnpm eslint:fix` — frontend lint passes
- [ ] All user-facing strings use i18n
- [ ] Migrations have indexes on FKs
- [ ] Job retries configured if calling external APIs
- [ ] Errors caught and tracked via ChatwootExceptionTracker
- [ ] Manually tested happy path in browser

---

## 1. Core Models & Schema

These are the foundational database tables and models that everything else depends on.

### 1.1 JivoAssistant Model
- **Purpose**: Central AI assistant configuration entity
- **Table**: `jivo_assistants`
- **Fields**:
  - `name` (string, required)
  - `description` (text)
  - `config` (jsonb) — temperature, product_name, welcome_message, handoff_message, resolution_message, instructions, feature flags
  - `response_guidelines` (jsonb array)
  - `guardrails` (jsonb array)
  - `account_id` (bigint)
- **Relations**:
  - belongs_to account
  - has_many documents, responses, scenarios, custom_tools
  - has_many inboxes through jivo_inboxes
  - has_many copilot_threads
  - has_many messages, as: :sender (polymorphic)

### 1.2 JivoInbox Model (Join Table)
- **Purpose**: Links assistant to inbox
- **Table**: `jivo_inboxes`
- **Fields**: `jivo_assistant_id`, `inbox_id`, account_id
- **Constraint**: One assistant per inbox (unique on inbox_id)

### 1.3 JivoDocument Model
- **Purpose**: Knowledge base sources
- **Table**: `jivo_documents`
- **Fields**:
  - `name`, `external_link`, `content` (text)
  - `status` enum (in_progress, available)
  - `metadata` (jsonb) — pagination, file IDs
  - `assistant_id`, `account_id`
  - PDF file via Active Storage attachment
- **Constraint**: Unique on (assistant_id, external_link)

### 1.4 JivoAssistantResponse Model (FAQ/Q&A)
- **Purpose**: Searchable Q&A entries
- **Table**: `jivo_assistant_responses`
- **Fields**:
  - `question`, `answer`
  - `embedding` (vector 1536 dim — pgvector)
  - `status` enum (pending, approved)
  - `documentable_id`, `documentable_type` (polymorphic — Document or User)
  - `assistant_id`, `account_id`
- **Index**: IVFFlat on embedding for fast similarity search

### 1.5 JivoScenario Model
- **Purpose**: Specialized sub-agent workflows
- **Table**: `jivo_scenarios`
- **Fields**:
  - `title`, `description`, `instruction` (markdown)
  - `enabled` (boolean, default true)
  - `tools` (jsonb array of tool IDs)
  - `assistant_id`, `account_id`

### 1.6 JivoCustomTool Model
- **Purpose**: User-defined HTTP-based tools
- **Table**: `jivo_custom_tools`
- **Fields**:
  - `title`, `description`, `endpoint_url`, `slug` (unique per account)
  - `http_method` (GET/POST)
  - `auth_type` (none/bearer/basic/api_key), `auth_config` (jsonb)
  - `param_schema` (jsonb)
  - `request_template`, `response_template`
  - `enabled`

### 1.7 CopilotThread Model
- **Purpose**: Agent-side AI chat sessions
- **Table**: `copilot_threads`
- **Fields**: `title`, `account_id`, `user_id`, `assistant_id`

### 1.8 CopilotMessage Model
- **Purpose**: Messages within a copilot thread
- **Table**: `copilot_messages`
- **Fields**:
  - `message` (jsonb) — content, reasoning, function_name, reply_suggestion
  - `message_type` enum (user, assistant, assistant_thinking)
  - `account_id`, `copilot_thread_id`

---

## 2. Assistant Management

### 2.1 CRUD Operations
- Create, list, view, update, delete assistants
- API: `/accounts/:id/jivo/assistants` (REST)

### 2.2 Configuration
- Temperature (0.0-2.0, default 1.0)
- Product name (used in prompts)
- Welcome message
- Handoff message (sent on bot→human transfer)
- Resolution message (sent on auto-resolve)
- Custom instructions (appended to system prompt)
- Feature toggles: `feature_faq`, `feature_memory`, `feature_citation`

### 2.3 Playground
- Test conversations without affecting real conversations
- Real-time chat interface
- Multi-turn message history
- Uses same chat service as production

### 2.4 Inbox Assignment
- Link assistant to specific inboxes
- Enable/disable per inbox
- One assistant per inbox max

### 2.5 Avatar
- Custom avatar upload
- Default fallback logo

### 2.6 Push Events / Webhooks
- WebSocket events on create/update
- Webhook payload: id, name, description, avatar, type

---

## 3. Knowledge Base & RAG

### 3.1 Document Sources
- **URL upload** — paste a URL, auto-crawl
- **PDF upload** — max 10MB, stored via Active Storage
- **Manual entry** — direct text input

### 3.2 Web Crawling
- **Firecrawl integration** — async crawl with webhook callback (max 10 URLs per crawl)
- **Simple page crawl** — fallback HTTP scraping (extracts body, title, meta, favicon)
- Triggered automatically on document creation

### 3.3 PDF Processing
- Upload to OpenAI Files API
- Stores `file_id` in document.metadata
- Used for paginated FAQ generation on large PDFs

### 3.4 FAQ Auto-Generation
- **Standard mode**: Process whole content at once
- **Paginated mode**: For large PDFs, process page-by-page (uses gpt-4.1-mini)
- Auto-generated Q&A pairs with `pending` status
- Manual approval workflow

### 3.5 Manual FAQ Entry
- Agents/admins can manually add Q&A pairs
- Marked as approved by default

### 3.6 Embeddings & Vector Search
- **Model**: text-embedding-3-small (1536 dimensions)
- **Storage**: pgvector column
- **Auto-update**: Job re-generates embedding when Q&A changes
- **Search**: Cosine similarity, returns top-5 nearest neighbors

### 3.7 Bulk Actions
- Approve/reject multiple FAQs at once
- Bulk delete responses

### 3.8 Document Status Tracking
- `in_progress` while crawling
- `available` after FAQ generation completes

---

## 4. Conversation Auto-Pilot (V1)

The original autonomous bot that handles incoming customer messages.

### 4.1 Trigger Mechanism
- After-create-commit hook on incoming messages
- Conditions: `conversation.pending? && message.incoming? && inbox.has_active_assistant?`
- Auto-routed to background job

### 4.2 Conversation Status Management
- New conversations start in `pending` if inbox has assistant
- AI handles while pending
- `bot_handoff!` transitions to `open` on handoff

### 4.3 Message History Collection
- All non-private incoming/outgoing messages
- Roles: incoming → user, outgoing → assistant
- Multimodal content (text + images + audio transcriptions)
- Includes `agent_name` from additional_attributes

### 4.4 System Prompt Generation
- Identity (name, product)
- Response guidelines (concise, language-aware, no markdown)
- Task instructions (call FAQ tool, return JSON)
- Handoff trigger keyword: `conversation_handoff`

### 4.5 OpenAI API Call
- Chat Completions API
- `response_format: { type: 'json_object' }` for reliable parsing
- Tool: `search_documentation` (FAQ lookup)
- Configurable model via `JIVO_OPEN_AI_MODEL`

### 4.6 Response Processing
- Parse JSON `{ reasoning, response }`
- Create outgoing message with sender = assistant
- Increment usage counter

### 4.7 Handoff Logic
- Detection: `response == 'conversation_handoff'`
- Action: Create handoff message, transition to `open`, send out-of-office if applicable
- Skip OOO for campaign conversations

### 4.8 Error Handling
- Retry on transient errors (3 attempts, 2s backoff)
- Graceful handoff to human on unrecoverable errors
- ChatwootExceptionTracker integration

### 4.9 Suppression of Other Templates
- While AI handles conversation, suppress: greeting, OOO, email-collect templates

### 4.10 Attachment Wait Logic
- Delay job by 1-5 seconds when message has attachments
- Allows file processing to complete before AI reads them

---

## 5. Conversation Auto-Pilot (V2 — Multi-Agent)

Modern agent-based architecture using Ruby Agents SDK.

### 5.1 Multi-Agent Orchestration
- Main assistant = orchestrator
- Scenario agents = specialists
- Bidirectional handoffs via `handoff_to_*` tools
- Max 100 turns per session

### 5.2 Agent State & Context
- Conversation state (id, status, priority, labels, custom attrs)
- Contact state (name, email, phone, type, custom attrs)
- Account ID, assistant ID, session ID

### 5.3 Response Schema
- Structured JSON: `{ response, reasoning }`
- Validated via RubyLLM Schema

### 5.4 Agent-Level Instrumentation
- Per-tool span tracking
- Token usage per agent
- Langfuse trace per session

### 5.5 Custom Tool Support
- Scenarios can use custom HTTP tools
- Tools dynamically loaded based on scenario configuration

---

## 6. Copilot (Agent-side AI Assistant)

AI sidebar for human agents to get help while handling conversations.

### 6.1 Thread Management
- Create thread (auto-titled from first message)
- List threads paginated (5 per page)
- Threads scoped to user + account + assistant

### 6.2 Messaging
- User sends message → async response generation
- Message types: user, assistant, assistant_thinking
- Real-time WebSocket broadcast

### 6.3 Available Tools (8 tools)
1. **SearchDocumentation** — FAQ search
2. **GetConversation** — fetch conversation by ID
3. **SearchConversations** — search conversations
4. **GetContact** — fetch contact by ID
5. **SearchContacts** — search contacts
6. **GetArticle** — fetch help center article
7. **SearchArticles** — search help center
8. **SearchLinearIssues** — Linear integration (optional)

### 6.4 Language Awareness
- Inject account locale into system message
- Reply in agent's language

### 6.5 Usage Tracking
- Each response increments `responses_usage`
- Limit check before response generation

---

## 7. Inline Agent Tasks

On-demand AI features available inline in the conversation UI.

### 7.1 Rewrite Service
- **Operations**:
  - `fix_spelling_grammar` — corrects errors
  - `improve` — enhances with conversation context
  - `casual` / `professional` / `friendly` / `confident` / `straightforward` — tone shifts
- Temperature 0.1 for tone consistency

### 7.2 Summarize Service
- Summarize entire conversation
- 400K character limit (token budget)

### 7.3 Reply Suggestion
- Drafts reply for agent approval
- Context: channel type, agent name, signature, conversation history

### 7.4 Label Suggestion
- Suggests relevant labels from account's label list
- Redis-cached by conversation_id + last_activity_at
- Strips "label/labels:" prefix from response

### 7.5 Follow-Up / Refinement
- Multi-turn refinement of any previous task output
- Maintains context across iterations
- Returns updated `follow_up_context` for client-side state

### 7.6 Base Service
- Shared logic: token limits, instrumentation, error handling
- Configurable model + endpoint
- Returns structured response: `{ message, error, error_code, follow_up_context }`

### 7.7 Liquid Prompt Templates
- Per-task templates (summary, reply, label_suggestion, tone_rewrite, improve, fix_spelling_grammar)
- Variable injection (agent name, conversation, signature)

---

## 8. Scenarios (Specialized Sub-Agents)

Each scenario is a focused agent with its own role and tool access.

### 8.1 Configuration
- Title, description, instruction (markdown), enabled flag
- Tool references in instructions: `[Tool Name](tool://tool_id)`
- Auto-extracted tool IDs into `tools` jsonb on save

### 8.2 Validation
- Tool refs must point to valid registered tools
- Required: title, description, instruction

### 8.3 Agent Framework Integration
- `scenario.agent` returns `Agents::Agent` instance
- Inherits temperature from parent assistant
- Custom tool resolution (built-in + custom)

### 8.4 Bidirectional Handoff
- Main assistant → scenario via `handoff_to_{scenario_key}`
- Scenario → main assistant via `handoff_to_{assistant_name}`
- Customer experience: seamless, no visible transfer

### 8.5 Scenario Prompt Template
- Liquid template with: title, instructions, tools list, response guidelines, guardrails
- Conversation + contact context injection

---

## 9. Custom Tools (HTTP-based)

User-defined tools that call external APIs.

### 9.1 Tool Definition
- Endpoint URL with placeholder support
- HTTP method (GET/POST)
- Authentication: none, bearer, basic, api_key
- Parameter schema (JSON schema)
- Request body template (optional)
- Response template (optional, for formatting)

### 9.2 Security
- **Private IP blocking**: 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, IPv6 loopback/ULA
- DNS resolution validation
- No redirects allowed
- Read timeout: 30s, connect timeout: 10s
- Max response size: 1MB

### 9.3 Slug Generation
- Auto-generated from title
- Collision-resistant (appends counter)
- Unique per account

### 9.4 Tool Registration
- Available in `assistant.available_agent_tools`
- Filtered to `enabled: true` only
- Mixed with built-in tools

### 9.5 Execution Flow
- Build URL with parameter substitution
- Build request body from template
- Send HTTP request with auth
- Apply response template
- Return formatted result to LLM

---

## 10. Built-in Agent Tools

Pre-built tools available to assistants and scenarios.

### 10.1 FAQ Lookup Tool
- Semantic search on approved FAQ responses
- Returns top-5 Q&A pairs with optional source URLs
- Handles language translation if needed

### 10.2 Handoff Tool
- Transfers conversation to human agent
- Optional reason (logged as private note)
- Triggers `bot_handoff!`, sets status to open
- Sends out-of-office template if applicable

### 10.3 Add Contact Note Tool
- Appends note to contact profile
- Visible to human agents in CRM

### 10.4 Add Private Note Tool
- Adds internal-only note to conversation
- Not visible to customer
- Sender = assistant

### 10.5 Update Priority Tool
- Sets conversation priority: low, medium, high, urgent

### 10.6 Add Label to Conversation Tool
- Tags conversation with label
- For categorization & reporting

### 10.7 Tool Infrastructure
- Base class: `BasePublicTool`
- Instrumentation mixin for Langfuse
- `execute(**args)` interface
- `active?` method for conditional availability
- `log_tool_usage(action, metadata)` helper

---

## 11. Memory & Auto-Learning

### 11.1 Contact Notes (Memory)
- **Trigger**: On conversation resolution (if `feature_memory` enabled)
- **Service**: Generate notes from full conversation
- **Action**: Save to contact profile for future context
- **Language-aware**: Uses account locale
- **Dedup**: Skips notes already on contact

### 11.2 Conversation FAQ Auto-Generation
- **Trigger**: On conversation resolution (if `feature_faq` enabled)
- **Service**: Extract Q&A pairs from conversation
- **Filter**: Only customer + agent messages (skip bot)
- **Action**: Add to assistant's knowledge base, auto-approved
- **Dedup**: Vector similarity check against existing FAQs

### 11.3 Contact Attribute Extraction
- **Service**: Extract custom attributes from conversation
- **Action**: Update contact custom_attributes
- **Dedup**: Only adds new attributes

---

## 12. Multimodal — Audio & Vision

### 12.1 Audio Transcription
- **Model**: Whisper (whisper-1)
- **Trigger**: Auto on audio attachment
- **Storage**: Transcript saved to attachment metadata
- **Integration**: Transcript becomes text content in message history
- **Usage**: Counts toward response usage

### 12.2 Image Understanding (Vision)
- **Model**: gpt-4-vision (whatever assistant model is, if vision-capable)
- **Trigger**: Auto on image attachment
- **Format**: Image URLs as `image_url` content blocks in OpenAI format
- **Multiple images**: Each becomes separate content block

### 12.3 Multimodal Message Builder
- Service: `OpenAiMessageBuilder`
- Handles: text + images + audio transcriptions
- Generic indicator: "User has shared an attachment" for unsupported types
- Reverse extraction: split content back into text + attachment URLs

### 12.4 Attachment URL Resolution
- Priority: `download_url` → `external_url` → Active Storage `file_url`

---

## 13. Settings & Guardrails

### 13.1 Response Guidelines
- Array of behavioral rules
- Injected into all agent system prompts
- Examples: "Be concise", "Always greet by name"

### 13.2 Guardrails
- Array of constraint rules
- Injected as "Always respect these boundaries"
- Examples: "Don't discuss politics", "Never share API keys"

### 13.3 Temperature
- Float 0.0-2.0
- Default 1.0
- Per-assistant configuration

### 13.4 Per-Feature Model Selection
- Main model: `JIVO_OPEN_AI_MODEL`
- Embedding model: `JIVO_EMBEDDING_MODEL`
- Audio model: hardcoded `whisper-1`
- Task-specific models can override

### 13.5 API Configuration
- API key: `JIVO_OPEN_AI_API_KEY`
- Endpoint: `JIVO_OPEN_AI_ENDPOINT` (allows custom OpenAI-compatible APIs)

---

## 14. Citations & Source Attribution

- **Toggle**: `feature_citation` flag in assistant config
- **Format**: `[[n](URL)]` numbered citations
- **Rules**:
  - Sequential numbering
  - Reuse same number for same source
  - Only cite documents (not conversation-derived info)
  - Place at end of paragraph/sentence
- **Implementation**: Pure prompt-based, no separate data storage

---

## 15. Multi-Language Support

### 15.1 Language Detection
- CLD3 library for query language detection
- Optional/fallback gracefully

### 15.2 Translation Service
- Translate FAQ queries to target language
- Lightweight model (gpt-4.1-nano)
- Skip if already in target language

### 15.3 Locale Awareness
- All system prompts include account locale
- Auto-reply in customer's detected language
- I18n wrapping for handoff/resolution messages

### 15.4 Per-Service Language Hints
- FAQ generator: "Generate in #{language}"
- Notes generator: "Generate in #{language}"
- Conversation FAQ: "Generate in #{language}"
- Copilot: "Account is using #{locale_english_name}"

---

## 16. Auto-Resolution

### 16.1 Pending Conversation Cleanup Job
- **Class**: `Jivo::InboxPendingConversationsResolutionJob`
- **Trigger**: Scheduled job (cron-based)
- **Logic**: Find conversations pending > 1 hour with no activity
- **Action**:
  1. Send resolution message (custom or default)
  2. Mark as resolved
- **Limits**: Bulk action limit per run
- **Locale**: Wraps in `I18n.with_locale(account.locale)`
- **Sender**: Set as assistant via `Current.executed_by`

### 16.2 Customizable Resolution Message
- Per-assistant via `config['resolution_message']`
- Falls back to default I18n string

---

## 17. Usage Limits & Tracking

### 17.1 Response Usage
- Counter: `account.custom_attributes['jivo_responses_usage']`
- Incremented on:
  - Auto-pilot response (V1 + V2, except handoffs)
  - Copilot message response
  - Inline tasks (rewrite, summarize, etc.)
- Method: `account.increment_response_usage`

### 17.2 Document Usage
- Counter: `account.custom_attributes['jivo_documents_usage']`
- Incremented on document create
- Decremented on document delete
- Method: `account.update_document_usage`

### 17.3 Plan Limits Configuration
- Stored in installation config: `JIVO_CLOUD_PLAN_LIMITS` (JSON)
- Per-account via `account.usage_limits[:jivo]`
- Structure: `{ responses: { current_available, total_count, consumed }, documents: { ... } }`

### 17.4 Limit Enforcement
- Pre-check before document creation (raises `LimitExceededError`)
- Pre-check before copilot response (returns error message if exceeded)
- Auto-pilot disabled when limit hits zero

---

## 18. Instrumentation & Observability

### 18.1 Langfuse Integration
- **Span types**: `llm.jivo.assistant`, `llm.jivo.copilot`, `llm.jivo.faq_generator`, etc.
- **Tags**: `[jivo]`, `[jivo_v2]`, `[pdf_upload]`
- **Metadata**: model, temperature, account_id, conversation_id, feature_name
- **Token tracking**: input_tokens, output_tokens per call
- **Cost calculation**: derived from model + tokens

### 18.2 OpenTelemetry
- Tracer access for manual spans
- Optional based on config
- Wrapped in `JivoApp.otel_enabled?` checks

### 18.3 Tool Instrumentation
- Per-tool execution traced
- Tool call & tool result events
- Logging helper: `log_tool_usage(action, metadata)`

### 18.4 Chat Generation Recorder
- Records full LLM interaction with token metadata
- Stores conversation context

### 18.5 Error Tracking
- ChatwootExceptionTracker / ExceptionTracker for all exceptions
- Per-account error scoping
- Rails logger throughout

---

## 19. Events & Webhooks

### 19.1 WebSocket Broadcasting
- `JIVO_MESSAGE_CREATED` — on copilot message creation
- `COPILOT_MESSAGE_CREATED` — broadcast after_create_commit
- Real-time update to dashboard UI

### 19.2 Webhook Payloads
- Assistant: id, name, description, avatar_url, type, created_at
- Thread: id, title, created_at, user, account_id
- Message: id, content, message_type, created_at, thread data

### 19.3 Outbound Webhook Integration
- Push event data fired through webhook system
- For external integrations (Slack, Zapier, etc.)

---

## 20. Frontend & UI

### 20.1 Routes
- `/jivo` — assistant index (with redirect)
- `/jivo/:assistantId/faqs` — Q&A list + management
- `/jivo/:assistantId/faqs/pending` — pending approvals
- `/jivo/:assistantId/documents` — document upload + list
- `/jivo/:assistantId/tools` — custom HTTP tools
- `/jivo/:assistantId/scenarios` — sub-agent workflows
- `/jivo/:assistantId/playground` — test playground
- `/jivo/:assistantId/inboxes` — inbox assignments
- `/jivo/:assistantId/settings` — basic settings
- `/jivo/:assistantId/settings/guardrails` — guardrails editor
- `/jivo/:assistantId/settings/guidelines` — guidelines editor
- `/settings/jivo` — global JIVO settings (API key, model)

### 20.2 Vue Components
- **Assistants**: Card, Playground, MessageList, Switcher
- **Documents**: Card, Form, FormDialog, LimitBanner, RelatedResponses
- **Responses**: Card, Form, CreateDialog, EmptyState
- **Tools**: Card, Form, CreateDialog, AuthConfig, ParamRow
- **Scenarios**: Card, Form, SuggestedRules
- **Settings**: BasicSettingsForm, SystemSettingsForm, ControlItems
- **Inboxes**: ConnectInboxDialog, ConnectInboxForm, InboxCard
- **Copilot**: Sidebar, MessageBubble, ThreadList
- **Shared**: Paywall, BulkSelectBar, BulkDeleteDialog

### 20.3 Vuex Stores
- assistant, document, response, copilotThreads, copilotMessages
- customTools, scenarios, tools, inboxes
- bulkActions, preferences

### 20.4 API Clients
- Per-resource Axios wrappers
- Located in `app/javascript/dashboard/api/jivo/`

### 20.5 Composable
- `useJivo()` — central composable for feature flags, limits, task methods
- Methods: `rewriteContent`, `summarizeConversation`, `getReplySuggestion`, `followUp`, `processEvent`

---

## Implementation Roadmap (Suggested Order)

Build in this order to minimize dependencies:

### Phase 1 — Foundation (MVP Auto-Pilot)
1. **Section 1**: Core models + migrations (JivoAssistant, JivoInbox)
2. **Section 13**: Basic settings (API key config)
3. **Section 4**: Conversation Auto-Pilot V1 (simple bot)
4. **Section 2**: Assistant CRUD + UI

### Phase 2 — Knowledge Base
5. **Section 3**: Documents, FAQs, embeddings, vector search
6. **Section 10**: FAQ Lookup tool + Handoff tool
7. **Section 17**: Usage tracking

### Phase 3 — Inline Tools for Agents
8. **Section 7**: Inline tasks (rewrite, summarize, etc.)
9. **Section 6**: Copilot threads + chat
10. **Section 14**: Citations

### Phase 4 — Advanced
11. **Section 12**: Multimodal (audio + vision)
12. **Section 11**: Memory & auto-learning
13. **Section 16**: Auto-resolution
14. **Section 15**: Multi-language

### Phase 5 — Power Features (V2)
15. **Section 5**: Multi-agent V2 architecture
16. **Section 8**: Scenarios
17. **Section 9**: Custom HTTP tools
18. **Section 10**: Remaining built-in tools (notes, priority, labels)

### Phase 6 — Production-Grade
19. **Section 18**: Instrumentation (Langfuse, OTel)
20. **Section 19**: Events & webhooks
21. **Section 20**: Full frontend polish

---

## Tech Stack Summary

| Component | Technology |
|---|---|
| Backend | Rails 7, Ruby |
| Database | PostgreSQL + pgvector |
| Job Queue | Sidekiq |
| LLM | OpenAI (configurable endpoint) |
| Embeddings | text-embedding-3-small (1536 dim) |
| Audio | Whisper-1 |
| Multi-Agent | Ruby Agents SDK (optional, for V2) |
| Crawling | Firecrawl + simple HTTP fallback |
| Templates | Liquid |
| Observability | Langfuse + OpenTelemetry |
| Frontend | Vue 3 (Composition API) + Vuex |
| HTTP | Net::HTTP / RubyLLM |

---

## Notes for Implementation

- **Naming**: Replace `Captain` with `Jivo` everywhere — namespaces, table prefixes, env vars, routes
- **Database table prefix**: `jivo_*` instead of `captain_*`
- **Env vars**: `JIVO_OPEN_AI_API_KEY`, `JIVO_OPEN_AI_MODEL`, etc.
- **Feature flags**: `jivo_integration`, `jivo_integration_v2`, `jivo_tasks`
- **Routes**: `/accounts/:id/jivo/*`
- **No license enforcement**: Build as fully unlocked feature
- **No Hub ping**: Skip the Chatwoot Hub integration
- **MVP first**: Phase 1 alone gives a working autonomous bot. Phases 2-6 add depth.

---

# Phase Implementation Log

This section is the **source of truth** for what was actually built per phase and what was intentionally deferred. Anything deferred MUST be revisited later — it is not a "nice to have", it's a deliberate cut for MVP velocity. Update this log every time a phase is completed.

## Phase 1 — Foundation + MVP Auto-Pilot ✅ COMPLETED

### Implemented
- ✅ JivoAssistant + JivoInbox models with associations
- ✅ Migrations + schema with proper indexes
- ✅ Conversation status detection (`active_jivo_assistant?`)
- ✅ HookExecutionService trigger + greeting/OOO/email-collect suppression
- ✅ Jivo::ConversationHandlerService with Captain-equivalent system prompt
- ✅ Jivo::ProcessConversationJob (async)
- ✅ Handoff mechanism (`bot_handoff!` → conversation goes from pending to open)
- ✅ Error handling with ChatwootExceptionTracker
- ✅ DocumentsController + InboxesController + AssistantsController + Pundit policies
- ✅ Settings UI (list, create/edit form, inbox connect/disconnect)
- ✅ Message model — JIVO recognized as bot (excluded from first-reply tracking)
- ✅ Frontend: Vuex store + API client + i18n
- ✅ Sidebar entry with sparkles icon

### Deferred — TO BE ADDED LATER
| Item | Why deferred | Phase to revisit |
|---|---|---|
| **Avatar on JivoAssistant** | Captain has `Avatarable` concern with image upload | Phase 6 (UI polish) |
| **Welcome message** config field | Captain has `welcome_message`; we only have `handoff_message` | Phase 6 |
| **Resolution message** config field | Captain has `resolution_message` for auto-resolve | Phase 4 (auto-resolution) |
| **Response guidelines** (jsonb array) | Captain has per-assistant behavioral rules | Phase 6 |
| **Guardrails** (jsonb array) | Captain has per-assistant constraints | Phase 6 |
| **Custom instructions** as separate field | Currently uses `system_prompt`; Captain has both | Phase 6 |
| **Playground UI** | Test conversations without affecting production | Phase 6 |
| **Push events on assistant create/update** | Captain dispatches WebSocket events | Phase 6 |
| **Webhook data** for outbound integrations | Captain has `webhook_data` payload | Phase 6 |
| **Feature flag** (`jivo_integration`) | Skipped because `feature_flags` bigint column is full (65 features) | Add `feature_flags_2` column when needed |
| **Send OOO message after handoff** | Captain triggers OOO template on handoff (skip for campaign convos) | Phase 4 |
| **Attachment wait logic** | Captain delays job 1-5s when attachments present | Phase 4 (multimodal) |
| **`agent_name` tracking** in `additional_attributes` | V2 feature for multi-agent identification | Phase 5 (V2) |
| **Captain V2 agent runner** | Multi-agent orchestration with handoffs | Phase 5 |
| **Per-feature model selection** | Captain has separate models for editor/copilot/assistant/etc. | Phase 3+ |
| **Captain Tasks** flag (always-on inline tools) | Inline rewrite/summarize/etc. | Phase 3 |

---

## Phase 2 — Knowledge Base & RAG ✅ COMPLETED

### Implemented
- ✅ JivoDocument model (URL-based knowledge sources)
- ✅ JivoAssistantResponse model with `has_neighbors :embedding`
- ✅ pgvector embedding column (1536 dim) + IVFFlat index
- ✅ Polymorphic `documentable` (Document or User-created)
- ✅ Status enum (`pending`/`approved`)
- ✅ Jivo::Llm::EmbeddingService (OpenAI text-embedding-3-small)
- ✅ Jivo::Llm::FaqGeneratorService (LLM-generated Q&As)
- ✅ Jivo::Llm::UpdateEmbeddingJob (async embedding refresh)
- ✅ Jivo::Tools::SimplePageCrawlService (HTTP + Nokogiri)
- ✅ Jivo::Documents::CrawlJob + ResponseBuilderJob
- ✅ ConversationHandlerService — RAG via pre-search + inject (top-5 cosine similarity)
- ✅ Knowledge context section in system prompt
- ✅ DocumentsController + AssistantResponsesController + JBuilder views
- ✅ Documents UI (list, add URL, delete, status badge)
- ✅ FAQs UI (list, create/edit, delete, auto-generated badge)
- ✅ Frontend: jivoDocuments + jivoResponses Vuex stores + API clients
- ✅ Navigation buttons from assistant index → Documents/FAQs sub-pages
- ✅ Full i18n coverage

### Deferred — TO BE ADDED LATER
| Item | Why deferred | Phase to revisit |
|---|---|---|
| **PDF upload support** | Captain uses OpenAI Files API + Active Storage attachment | Phase 6 |
| **Firecrawl integration** | Multi-page async crawling with webhook callbacks | Phase 6 |
| **Approval workflow UI** | Captain has separate "Pending" tab for review before going live; we auto-approve | Phase 6 |
| **Bulk actions** (approve/delete multiple) | Captain has bulk action endpoint + bulk select bar | Phase 6 |
| **Paginated FAQ generation** | For very large PDFs, page-by-page processing | Phase 6 (with PDF) |
| **OpenAI function calling** for search | Captain uses `search_documentation` tool — LLM decides when to search; we always pre-search and inject | Phase 5 (V2 architecture) |
| **Query translation** before search | Captain translates query to account locale via TranslateQueryService | Phase 4 (multi-language) |
| **Citations** `[[n](URL)]` in responses | Captain has `feature_citation` flag; sources cited at sentence end | Phase 3 |
| **Source URLs returned with FAQs** | Captain returns external_link with each FAQ result | Phase 3 |
| **Usage limits enforcement** | Captain has document/response quotas with `LimitExceededError` | Skip — self-hosted, no limits needed |
| **Document description/favicon** in metadata | Captain stores richer page metadata | Phase 6 |
| **Crawl progress tracking** | Captain has multi-page progress states | Phase 6 (with Firecrawl) |
| **Conversation FAQ auto-generation** | Captain auto-extracts FAQs from resolved conversations (`feature_faq`) | Phase 4 (memory) |
| **Contact attribute extraction** | Captain extracts custom attributes from conversations | Phase 4 (memory) |
| **Auto-translate FAQ for cross-language** | Captain searches in target language even if FAQ is in original language | Phase 4 |

---

## Phase 3 — Inline Agent Tasks ✅ COMPLETED

### Implemented
- ✅ `Jivo::Tasks::BaseTaskService` — shared OpenAI call + error handling
- ✅ `Jivo::Tasks::RewriteService` — operations: `fix_spelling_grammar`, `improve`, `casual`, `professional`, `friendly`, `confident`, `straightforward`
- ✅ `Jivo::Tasks::SummarizeService` — full conversation summary
- ✅ `Jivo::Tasks::ReplySuggestionService` — AI-drafted reply for agents
- ✅ `Jivo::Tasks::LabelSuggestionService` — label suggestions from account label list
- ✅ `Jivo::Tasks::FollowUpService` — multi-turn refinement of any task output
- ✅ `Api::V1::Accounts::Jivo::TasksController` with 5 POST endpoints
- ✅ Routes: `/jivo/tasks/rewrite|summarize|reply_suggestion|label_suggestion|follow_up`
- ✅ Pundit policy expanded to allow agent + administrator
- ✅ Frontend API client (`jivoTasks.js`)
- ✅ `JivoAssistantPanel.vue` — modal-based UI with 4 task entry points + follow-up refinement
- ✅ Integrated into `ConversationHeader.vue` via sparkles icon button
- ✅ Apply-to-reply via `draftMessages/set` dispatch
- ✅ Copy-to-clipboard for results
- ✅ Full i18n coverage under `JIVO.TASKS.*`

### Deferred — TO BE ADDED LATER
| Item | Why deferred | Phase to revisit |
|---|---|---|
| **Liquid prompt templates** | Captain uses `summary.liquid`, `reply.liquid`, etc. We use inline string prompts | Phase 6 |
| **Per-task model selection** | Captain allows each task to use a different model (e.g. `gpt-4o-mini` for label_suggestion) | Phase 6 |
| **Redis caching for label suggestions** | Captain caches by `conversation_id + last_activity_at` | Phase 6 |
| **Auto-trigger label suggestion** | Captain runs label_suggestion automatically on conversation events | Phase 6 |
| **Token budget enforcement (400K char)** | We limit single-message input only; Captain has full conversation budget tracking | Phase 6 |
| **Multi-language detection in tasks** | Captain detects language and prompts model accordingly | Phase 4 (multi-language) |
| **Streaming responses** | Captain streams chunks; we wait for full response | Phase 6 |
| **Direct editor integration** | Captain integrates rewrite into the WootWriter Editor toolbar; we use a separate modal panel | Phase 6 (deep editor integration) |
| **Reply-suggestion in reply box dropdown** | Captain adds it as inline option; we apply via "Use as reply" button | Phase 6 |
| **Reply suggestion FAQ/RAG search tool** | Captain Enterprise can search documentation while drafting replies; JIVO reply suggestion currently uses conversation history only | Phase 6 |
| **Per-feature model config (CAPTAIN_OPEN_AI_MODEL etc.)** | Captain has installation-level per-feature model config | Phase 6 |
| **Instrumentation (Langfuse)** | Captain traces every task call | Phase 6 |
| **Account-level OpenAI config (vs per-assistant)** | Captain has installation config for tasks; we use the assistant's API key | Skip — keeps multi-assistant model consistent |
| **Usage tracking per task** | Captain increments `responses_usage` per task call | Skip — self-hosted, no limits |
| **Auto-detect agent signature** | Captain reads `user.message_signature` and includes in reply prompt | Phase 6 |
| **Channel-specific reply tone** | Captain adapts based on channel (e.g. Twitter has char limits) | Phase 6 |

---

## Phase 4 — Multimodal + Memory + Multi-Language (NOT STARTED)

Planned per Sections 11, 12, 15, 16. Will track here when started.

---

## Phase 5 — Multi-Agent V2 (NOT STARTED)

Planned per Sections 5, 8, 9, 10. Will track here when started.

---

## Phase 6 — Production Polish (NOT STARTED)

Catches everything deferred from Phases 1-5 plus:
- Section 18 (Instrumentation)
- Section 19 (Webhooks)
- Section 20 (Frontend polish — avatars, branding, advanced forms, playground UI)
- Approval workflows + bulk actions across all features

---

## Conventions for Updating This Log

When completing a phase:
1. Move the phase from "NOT STARTED" to "✅ COMPLETED" with date
2. Fill in the **Implemented** section with what actually shipped
3. Fill in the **Deferred** section with EVERY skipped item — don't quietly drop features
4. For each deferred item, specify which future phase it will land in
5. Skipped items that won't ever be added must be marked `Skip — <reason>` with explicit reasoning

This log replaces commit messages or PR descriptions as the canonical record of what's in JIVO vs Captain.
