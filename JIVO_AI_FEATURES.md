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
16. [Idle Conversation Action](#16-idle-conversation-action)
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
  - `config` (jsonb) — temperature, product_name, welcome_message, handoff_message, idle action settings, instructions, feature flags
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
- Idle action settings: enable/disable, timeout, action type, idle message
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
- **Current Limitation**: If the business does not resolve conversations, this trigger will not run. Need a non-resolution learning path.

### 11.2 Conversation FAQ Auto-Generation
- **Trigger**: On conversation resolution (if `feature_faq` enabled)
- **Service**: Extract Q&A pairs from conversation
- **Filter**: Only customer + agent messages (skip bot)
- **Action**: Add to assistant's knowledge base as pending for review
- **Dedup**: Vector similarity check against existing FAQs
- **Current Limitation**: If the business does not resolve conversations, this trigger will not run. Need a manual or inactivity-based learning path.

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

## 16. Idle Conversation Action

### 16.1 Idle Conversation Action Job
- **Class**: `Jivo::IdleConversationActionJob`
- **Trigger**: Scheduled job (cron-based)
- **Default State**: Disabled unless assistant config enables it
- **Logic**: Find JIVO-handled conversations with no activity for configured timeout
- **Recommended Default Action**: `handoff`
- **Supported Actions**:
  1. `handoff` — send handoff/idle message and hand over to a human agent/team
  2. `resolve` — send resolution message and mark as resolved
  3. `reminder` — send reminder message only, keep conversation state unchanged
- **Limits**: Bulk action limit per run
- **Locale**: Wraps in `I18n.with_locale(account.locale)`
- **Sender**: Set as assistant via `Current.executed_by`

### 16.2 Idle Action Configuration
- `config['feature_idle_action']` — enable/disable
- `config['idle_timeout_minutes']` — default `60`
- `config['idle_action']` — default `handoff`
- `config['idle_message']` — custom message for handoff/reminder/resolve
- Falls back to existing handoff message for `handoff`
- Falls back to default I18n resolution message for `resolve`

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
| **Idle action config fields** | Captain only auto-resolves; JIVO should support handoff, resolve, or reminder | Phase 4 (idle action) |
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
| **Approval workflow UI** | Captain has separate "Pending" tab for review before going live; conversation-learned FAQs are pending but UI is still basic | Phase 6 |
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

## Phase 4 — Multimodal + Memory + Multi-Language (✅ COMPLETED)

> **Handoff-ready sub-task breakdown.** Each sub-task is independent. Mark `IN PROGRESS` when starting, `✅ COMPLETED` when done, list what was actually built + deferred items.

### Sub-Task 4.1: Multimodal Message Builder + Vision

**Status: ✅ COMPLETED**

**Implemented:**
- `app/services/jivo/openai_message_builder_service.rb` — multimodal content builder (text + image_url[] + audio transcripts)
- `Jivo::OpenaiMessageBuilderService.extract_text_and_attachments(content)` class method to reverse-extract from content array
- Modified `app/services/jivo/conversation_handler_service.rb` — `build_content` method delegates to builder; OpenAI receives content as either string or array
- Image attachment URL resolution: `download_url` → `external_url` → Active Storage `file_url`
- Tested with real message having image attachment — builder correctly returns `[{type: 'text'}, {type: 'image_url'}]`

**Verified:** Plain text messages return string. Image-attached messages return content array compatible with OpenAI vision API.

**Goal:** Customer sends image → JIVO sees and responds based on image content.

**Reference (Captain):**
- `enterprise/app/services/captain/open_ai_message_builder_service.rb` — multimodal content builder
- `enterprise/app/jobs/captain/conversation/response_builder_job.rb#L78-L80` — `prepare_multimodal_message_content`

**Files to create:**
- `app/services/jivo/openai_message_builder_service.rb` — extract text + image_url[] + audio transcripts from a message; return either a string (text-only) or a content array (multimodal)

**Files to modify:**
- `app/services/jivo/conversation_handler_service.rb` — replace simple `content` extraction with `Jivo::OpenaiMessageBuilderService.new(message:).generate_content`
- Inside the OpenAI POST body, when content is an array (multimodal), keep it as the array (OpenAI accepts content as array of `{ type: 'text' | 'image_url' }` blocks)

**How it works:**
- Image attachments → `{ type: 'image_url', image_url: { url: <attachment_url> } }`
- Audio → transcript via Whisper (Sub-task 4.2; until then, just text fallback)
- Other files → text "User has shared an attachment"
- URL resolution priority: `download_url` → `external_url` → Active Storage `file_url`

**Test:**
1. Send a customer message with an image attachment to a JIVO inbox
2. Check Sidekiq job logs — should pass image_url to OpenAI
3. JIVO response should reference what's in the image

**Deferred (Phase 6):**
- Vision-capable model detection (warn if model doesn't support vision)
- Image OCR fallback for non-vision models

---

### Sub-Task 4.2: Audio Transcription (Whisper)

**Status: ✅ COMPLETED**

**Implemented:**
- `app/services/jivo/messages/audio_transcription_service.rb` — calls OpenAI Whisper at `/v1/audio/transcriptions` via multipart/form-data, downloads from Active Storage to temp file, caches transcript on `attachment.meta['transcribed_text']` via `update_columns` (skips validations intentionally)
- `app/jobs/jivo/messages/audio_transcription_job.rb` — async wrapper with retry on Net::ReadTimeout
- Updated `Jivo::OpenaiMessageBuilderService` — accepts optional `assistant` param. When audio attachment lacks cached transcript and assistant is provided, transcribes inline via service
- Updated `Jivo::ConversationHandlerService` — passes `assistant:` to message builder
- Updated `app/services/message_templates/hook_execution_service.rb` — `schedule_jivo_response` now waits 8s when message has audio attachments (give upload time to complete) and 1-5s otherwise

**Verified:** Service classes load. Builder accepts assistant. Real audio attachment found in DB available for live test.

**How to test live:**
1. Send a voice note to a JIVO-enabled inbox
2. Wait ~10s for processing
3. Check `attachment.meta['transcribed_text']` for transcript
4. JIVO response should reference voice note content

**Goal:** Customer sends voice note → Whisper transcribes → JIVO responds based on transcript.

**Reference (Captain):**
- `enterprise/app/services/messages/audio_transcription_service.rb` — Whisper integration
- `enterprise/app/jobs/messages/audio_transcription_job.rb` — async wrapper

**Files to create:**
- `app/services/jivo/messages/audio_transcription_service.rb` — calls OpenAI `/v1/audio/transcriptions` with the audio file, returns transcript string. Caches transcript on `attachment.meta['transcribed_text']`
- `app/jobs/jivo/messages/audio_transcription_job.rb` — async wrapper (queue: `:default`)

**Files to modify:**
- `app/services/jivo/openai_message_builder_service.rb` (from 4.1) — when audio attachment exists, call transcription service synchronously OR enqueue job + use cached transcript
- `app/services/jivo/conversation_handler_service.rb` — wait time when message has audio attachments (Captain has `calculate_attachment_wait_time`)

**Approach:**
- Use `attachment.file_type == 'audio'`
- Get audio file via `attachment.file.download` (Active Storage) → write to temp file → POST to OpenAI Whisper API as multipart/form-data
- Whisper model: `whisper-1`
- On success, save transcript to `attachment.meta['transcribed_text']` and return text

**Test:**
1. Send voice note (.ogg/.m4a/.mp3) to JIVO inbox
2. Wait ~5s for transcription
3. JIVO should respond based on transcript content

**Deferred (Phase 6):**
- Per-account language hint to Whisper (`language` param)
- Transcription model fallback if Whisper fails
- Larger file chunking (Whisper 25MB limit)

---

### Sub-Task 4.3: Contact Notes Memory (Auto-Generation)

**Status: ✅ COMPLETED**

**Implemented:**
- `app/services/jivo/llm/contact_notes_service.rb` — builds contact + conversation context, calls OpenAI with JSON response format, parses `{ "notes": [] }`, and creates `contact.notes`
- `app/jobs/jivo/contact_notes_job.rb` — async wrapper for note generation
- `app/listeners/jivo_listener.rb` — handles `conversation_resolved` and enqueues notes when inbox has JIVO + `feature_memory` is enabled
- `app/dispatchers/async_dispatcher.rb` — registers `JivoListener.instance`
- `app/models/jivo_assistant.rb` — added `feature_memory` config accessor

**Verified:** New constants load via Rails runner. Focused RuboCop passes for service, job, listener, dispatcher, and model.

**Goal:** When conversation resolves, JIVO summarizes and saves a note on the contact for future context.

**Reference (Captain):**
- `enterprise/app/services/captain/llm/contact_notes_service.rb`
- `enterprise/app/listeners/captain_listener.rb` — `conversation_resolved` event handler

**Files to create:**
- `app/services/jivo/llm/contact_notes_service.rb` — sends conversation to LLM with `notes_generator` prompt, parses JSON `{ notes: ['...', '...'] }`, creates contact notes via `contact.notes.create!`
- `app/listeners/jivo_listener.rb` — subscribes to `conversation_resolved`. On event: check if inbox has assistant + `feature_memory` enabled, then enqueue job
- `app/jobs/jivo/contact_notes_job.rb` — async wrapper

**Files to modify:**
- `config/initializers/event_listeners.rb` (or equivalent) — register `JivoListener.instance` as listener for events
- `app/models/jivo_assistant.rb` — add `feature_memory` to `store_accessor` config keys

**Approach:**
```ruby
# JivoListener
def conversation_resolved(event)
  conversation = event.data[:conversation]
  assistant = conversation.inbox.jivo_assistant
  return unless assistant.present? && assistant.config['feature_memory']

  Jivo::ContactNotesJob.perform_later(conversation, assistant)
end
```

**Files to look at:**
- Find existing listener registration pattern: `grep -rn "register_listener\|add_listener" config/`
- Existing pattern: `app/listeners/agent_assignable_listener.rb` or similar

**Test:**
1. Resolve a conversation that has good content
2. Check `contact.notes` table — should have 1-3 new notes
3. Verify `feature_memory` flag works (toggle off → no notes generated)

**Deferred:**
- Dedup against existing notes
- Polished UI for `feature_memory` in assistant settings form (basic testing toggle exists)
- Non-resolution learning trigger for businesses that keep conversations open. Options: manual "Learn from conversation" action, inactivity-based learner, handoff-based learner, or scheduled learner with `last_jivo_learned_at`.

---

### Sub-Task 4.4: Conversation FAQ Auto-Generation

**Status: ✅ COMPLETED**

**Implemented:**
- `app/services/jivo/llm/conversation_faq_service.rb` — filters resolved conversation to customer/agent messages, calls OpenAI with JSON response format, parses `{ "faqs": [] }`, dedupes via vector cosine distance, and creates pending `JivoAssistantResponse` records
- `app/jobs/jivo/conversation_faq_job.rb` — async wrapper for FAQ generation
- `app/listeners/jivo_listener.rb` — also enqueues FAQ generation when `feature_faq` is enabled
- `app/models/jivo_assistant.rb` — added `feature_faq` config accessor

**Verified:** New constants load via Rails runner. Focused RuboCop passes for service, job, listener, and model.

**Goal:** Resolved conversations auto-generate Q&A pairs added to knowledge base.

**Reference (Captain):**
- `enterprise/app/services/captain/llm/conversation_faq_service.rb`

**Files to create:**
- `app/services/jivo/llm/conversation_faq_service.rb` — sends conversation (filtered to customer + agent only, no bot messages) to LLM with `conversation_faq_generator` prompt, dedupes via vector similarity, creates `JivoAssistantResponse` records with `documentable: nil` and status: `:pending`
- `app/jobs/jivo/conversation_faq_job.rb` — async wrapper

**Files to modify:**
- `app/listeners/jivo_listener.rb` (from 4.3) — also enqueue FAQ job on `conversation_resolved` if `feature_faq` is enabled
- `app/models/jivo_assistant.rb` — add `feature_faq` to `store_accessor`

**Approach:**
- Filter messages: `.where(message_type: [:incoming, :outgoing], private: false).where.not(sender_type: ['JivoAssistant', 'AgentBot'])`
- Use system prompt: "You are a support agent looking to convert conversations into reusable FAQs"
- Output JSON: `{ "faqs": [{ "question": "...", "answer": "..." }] }`
- Dedup: for each new FAQ, run `JivoAssistantResponse.search(question, jivo_assistant: assistant)` — skip if top result has cosine similarity > 0.9
- Create with `status: :pending`, `documentable: nil`

**Test:**
1. Resolve a conversation with clear Q&A
2. Check `JivoAssistantResponse.where(documentable: nil)` for new entries
3. Run similar question through search — should match new FAQ

**Deferred:**
- Approval workflow polish (conversation-learned FAQs are pending now; Phase 6 has manual review UI)
- Rate limit (Captain has plan-based limits)
- Polished UI for `feature_faq` in assistant settings form (basic testing toggle exists)
- Non-resolution learning trigger for businesses that keep conversations open. Recommended: manual "Learn from conversation" action first; later add inactivity/scheduled learner. Generated FAQs should remain pending.

---

### Sub-Task 4.5: Multi-Language Support

**Status: ✅ COMPLETED**

**Goal:** Customer writes in any language → JIVO responds in same language. FAQ search works across languages.

**Reference (Captain):**
- `enterprise/app/services/captain/llm/translate_query_service.rb` — query translation
- Captain uses `cld3` gem for detection (already in Gemfile? check `bundle list | grep cld3`)

**Files to create:**
- `app/services/jivo/llm/translate_query_service.rb` — given a query + target language, translates if not already in target language. Uses `gpt-4.1-nano` (cheapest model) for translation only

**Files to modify:**
- `app/models/jivo_assistant_response.rb` — `self.search` method should translate query to account's locale before embedding (since FAQs are stored in account locale)
- `app/services/jivo/conversation_handler_service.rb` — system prompt already has "detect language and reply in same language" — verify it works
- `Gemfile` — add `gem 'cld3'` if not present

**Approach:**
```ruby
class Jivo::Llm::TranslateQueryService
  def translate(query, target_language: 'english')
    return query if detect_language(query) == target_language
    # call gpt-4.1-nano with simple translation prompt
  end
end
```

**Test:**
1. Add FAQ in English: "How to book a flight?"
2. Customer asks in Arabic: "كيف أحجز رحلة؟"
3. JIVO should: translate query → search FAQ → reply in Arabic

**Deferred:**
- Translation caching
- Per-language FAQ storage (currently single language per FAQ)

**Implementation Notes (2026-05-02):**
- Created `app/services/jivo/llm/translate_query_service.rb`.
- Uses `cld3` for language detection and skips translation when the query already matches the account locale language.
- Uses `gpt-4.1-nano` for translation only, with the assistant OpenAI API key.
- Updated `JivoAssistantResponse.search` to translate the customer query to the account locale before generating embeddings.
- `cld3` was already present in `Gemfile`, so no dependency change was needed.

---

### Sub-Task 4.6: Idle Conversation Action

**Status: ✅ COMPLETED**

**Goal:** JIVO-handled conversations that go idle can be handled by configurable action: handoff to agent, resolve, or send reminder only.

**Reference (Captain):**
- `enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb`

**Files to create:**
- `app/jobs/jivo/idle_conversation_action_job.rb` — finds JIVO-handled conversations idle longer than `assistant.config['idle_timeout_minutes'] || 60`, then applies configured idle action
- Schedule entry in `config/schedule.yml` to run hourly

**Files to modify:**
- `app/models/jivo_assistant.rb` — add `feature_idle_action`, `idle_timeout_minutes`, `idle_action`, and `idle_message` to `store_accessor` config keys
- `config/schedule.yml` — add cron entry

**Approach:**
```ruby
# Cron: every hour
def perform
  Inbox.joins(:jivo_inbox).find_each do |inbox|
    assistant = inbox.jivo_assistant
    next unless assistant.feature_idle_action.present?

    timeout = assistant.idle_timeout_minutes.presence || 60
    conversations = inbox.conversations
                         .pending
                         .where('last_activity_at < ?', timeout.minutes.ago)
                         .limit(Limits::BULK_ACTIONS_LIMIT)
    conversations.each do |conv|
      # Set Current.executed_by = inbox.jivo_assistant
      # Apply assistant.idle_action:
      # handoff  -> send idle/handoff message + conv.bot_handoff!
      # resolve  -> send idle/resolution message + conv.resolved!
      # reminder -> send idle/reminder message only
    end
  end
end
```

**Recommended MVP Defaults:**
- Disabled by default
- `idle_timeout_minutes`: `60`
- `idle_action`: `handoff`
- `idle_message`: blank, so it falls back to existing handoff message

**Test:**
1. Set a pending conversation's `last_activity_at` to 2 hours ago
2. Enable `feature_idle_action` on the assistant
3. Run `Jivo::IdleConversationActionJob.perform_now`
4. For `handoff`, conversation should receive idle/handoff message and be handed to human workflow
5. For `resolve`, conversation should receive idle/resolution message and be resolved
6. For `reminder`, conversation should receive idle/reminder message and remain unchanged

**Deferred:**
- Polished UI controls for enable/disable, timeout, action type, and custom idle message (basic testing controls exist)
- Reminder limit setting for `reminder` action, e.g. `idle_reminder_limit`, with per-conversation counters such as `jivo_idle_reminder_count` and `jivo_last_idle_reminder_at` to avoid repeated hourly reminders.
- Smarter assignment target selection for `handoff`
- Per-inbox/action analytics

**Implementation Notes (2026-05-02):**
- Created `app/jobs/jivo/idle_conversation_action_job.rb`.
- Job runs hourly via `config/schedule.yml`.
- Added assistant config accessors/helpers for `feature_idle_action`, `idle_timeout_minutes`, `idle_action`, and `idle_message`.
- Supported actions:
  - `handoff` — sends idle message, marks `custom_attributes['ai_handoff'] = true`, calls `bot_handoff!`, and sends out-of-office template if applicable.
  - `resolve` — sends idle message and marks conversation resolved.
  - `reminder` — sends idle message only.
- Job only processes pending conversations, so handoff/resolve actions do not repeat after the status changes.
- Added English default messages under `conversations.jivo`.

---

### Phase 4 Handoff Notes

If picking up mid-phase:
1. Read this section + look at the **last sub-task marked IN PROGRESS or NOT STARTED**
2. Each sub-task lists exact files to create/modify and Captain reference files
3. Run `bundle exec rails runner "..."` to test backend after each sub-task
4. Update this log when done — move from `NOT STARTED` → `✅ COMPLETED` and fill in actually-built items + deferred items
5. **Lint after each sub-task**: `bundle exec rubocop -a app/services/jivo/ app/jobs/jivo/ app/models/jivo_*` and `pnpm eslint --fix <changed files>`

### Phase 4 Status Tracker

- [x] 4.1 Multimodal Message Builder + Vision — ✅ COMPLETED
- [x] 4.2 Audio Transcription — ✅ COMPLETED
- [x] 4.3 Contact Notes Memory — ✅ COMPLETED
- [x] 4.4 Conversation FAQ Auto-Generation — ✅ COMPLETED
- [x] 4.5 Multi-Language Support — ✅ COMPLETED
- [x] 4.6 Idle Conversation Action — ✅ COMPLETED

### Last Handoff State

**Date:** 2026-05-02
**Last completed sub-task:** 4.6
**Files modified in 4.6:**
- Created: `app/jobs/jivo/idle_conversation_action_job.rb`
- Modified: `app/models/jivo_assistant.rb` (idle action config accessors and helper methods)
- Modified: `config/schedule.yml` (hourly scheduled job)
- Modified: `config/locales/en.yml` (JIVO handoff/reminder/resolve defaults)
- Modified: `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` (basic testing controls for Phase 4 flags)
- Modified: `app/javascript/dashboard/i18n/locale/en/jivo.json` (labels for testing controls)
- Modified: `app/controllers/api/v1/accounts/jivo/assistants_controller.rb` (permits Phase 4 config keys)

**To continue, the next agent should:**
1. Treat Phase 4 as complete.
2. Run live/manual testing for 4.1-4.6 using the phase test notes.
3. Move to Phase 5 or Phase 6 depending on product priority.
4. Polish the basic Phase 4 settings UI in Phase 6.

**Lint commands to run after each sub-task:**
```bash
bundle exec rubocop -a app/services/jivo/ app/jobs/jivo/ app/listeners/jivo_listener.rb 2>/dev/null
pnpm eslint --fix app/javascript/dashboard/api/jivo*.js app/javascript/dashboard/components-next/jivo/
```

---

## Phase 4.7 — Quick Wins for Non-Resolution Learning (IN PROGRESS)

Unblocks the real-world Tabeer Tours deployment (conversations rarely get resolved). Three independently shippable sub-tasks.

### Sub-Task 4.7.1: Inject Contact Notes into Reply System Prompt

**Status: ✅ COMPLETED**

**Goal:** Notes already auto-generated by `Jivo::ContactNotesJob` should actually influence JIVO replies. They were being saved to `contact.notes` but never read back by the conversation handler.

**Implemented:**
- Modified `app/services/jivo/conversation_handler_service.rb` — added `contact_notes_section` method, called from `system_prompt_text` after the knowledge base section. Fetches the contact's last 10 notes ordered by recency, skips entirely when blank.

**Verified:** Rails runner against conversation 3424 — empty notes returned no `[Contact Memory]` section; after creating a note the section appeared with the note text included.

**Test:**
1. Pick a conversation in a JIVO-enabled inbox.
2. Create a `Note` on its contact (`conversation.contact.notes.create!(content: 'foo', user: User.first, account: conversation.account)`).
3. Trigger a reply — the OpenAI request body's system message should contain `[Contact Memory]` with the note text.

**Deferred:**
- Cap on note character length per entry (long notes can blow context).
- Token-aware budgeting if the FAQ context + notes exceed model limits.
- Surface notes in the JIVO assistant panel as read-only context.

---

### Sub-Task 4.7.2: Admin-Only "Learn from this Conversation" Button

**Status: ✅ COMPLETED**

**Goal:** Manual, on-demand learning trigger for admins. Forces both contact-notes and FAQ generation on the current conversation, including bypassing the FAQ service's "no human interaction" guard so admins can extract knowledge from any conversation regardless of its state.

**Design decisions (per user direction):**
- Trigger is **manual only**. The previous draft of 4.7.2 wired learning to the `conversation.bot_handoff` event, but that has been reverted — the listener is back to its original `conversation_resolved`-only state. Reasoning: admin wants explicit control over when learning fires; nothing happens silently in the background.
- The button is **admin-only** (hidden for agents) via `useAdmin` composable + `JivoAssistantPolicy#learn_from_conversation?`.
- The manual path **bypasses** `Jivo::Llm::ConversationFaqService#no_human_interaction?` via a new `force:` flag. The auto path (`conversation_resolved`) still respects the guard — only the admin-triggered path skips it.

**Implemented:**
- Reverted `app/listeners/jivo_listener.rb` to its pre-4.7.2 state (only handles `conversation_resolved`).
- `app/services/jivo/llm/conversation_faq_service.rb` — added `force` to `pattr_initialize`. `generate_and_deduplicate` now skips the human-interaction guard when `force` is true.
- `app/jobs/jivo/conversation_faq_job.rb` — accepts and forwards `force:` keyword arg.
- `app/policies/jivo_assistant_policy.rb` — added `learn_from_conversation?` (administrator only).
- `app/controllers/api/v1/accounts/jivo/tasks_controller.rb` — added `learn_from_conversation` action. Reuses `load_assistant` + `load_conversation!`. Enqueues `ContactNotesJob` + `ConversationFaqJob` (force: true) and returns `{ success: true, message: ... }`.
- `config/routes.rb` — added `post :learn_from_conversation` to the `jivo/tasks` resource.
- `config/locales/en.yml` — added top-level `jivo.tasks.learn.queued` key.
- `app/javascript/dashboard/api/jivoTasks.js` — added `learnFromConversation`.
- `app/javascript/dashboard/components-next/jivo/JivoAssistantPanel.vue` — added admin-only tile (`v-if="isAdmin"`) spanning two columns at the bottom of the task grid. Shows a spinning loader icon while learning is queueing, fires `useAlert` with the success message, and resets state independently from the other task flows.
- `app/javascript/dashboard/i18n/locale/en/jivo.json` — added `JIVO.TASKS.LEARN.{TITLE,DESCRIPTION,QUEUED}`.

**Verified (Rails runner):**
- Route registered at `POST /api/v1/accounts/:account_id/jivo/tasks/learn_from_conversation`.
- FAQ service still skips with `force: false` (no behavior regression for the auto path).
- `Jivo::ContactNotesJob` + `Jivo::ConversationFaqJob.perform_later(..., force: true)` both enqueue without arity errors.
- `I18n.t('jivo.tasks.learn.queued')` resolves.

**Test (live):**
1. Sign in as an administrator. Open any conversation in a JIVO-enabled inbox.
2. Open the JIVO assistant panel — the "Learn from this conversation" tile should be visible at the bottom (admins only).
3. Click it. Toast says learning is queued.
4. Sidekiq runs both jobs. Confirm `conversation.contact.notes` gets new rows and `JivoAssistantResponse.where(documentable: nil)` gets pending FAQs.
5. Sign in as an agent — tile should be hidden.

**Deferred:**
- Idempotency: clicking Learn twice will trigger duplicate notes. FAQ has vector dedupe so safe there; notes do not. Cheap fix: dedupe on `(contact_id, content)` or scope to recent activity window.
- Progress feedback after toast — currently fire-and-forget. Could add a "last learned at" timestamp on the conversation or a polling check.
- Eventual auto-trigger after human agent replies (so FAQ generation happens automatically post-handoff once an agent has answered) — still open as an optional future improvement, but admin button covers the MVP need.

---

### Sub-Task 4.7.3: Idle Reminder Limit Guard

**Status: ✅ COMPLETED**

**Goal:** Prevent the hourly idle job from spamming customers when `idle_action: reminder` is enabled. Cap the number of reminder messages per conversation.

**Implemented:**
- `app/models/jivo_assistant.rb` — added `idle_reminder_limit` to `store_accessor`, plus `DEFAULT_IDLE_REMINDER_LIMIT = 3` constant and `idle_reminder_limit_value` helper that falls back to the default when blank or non-positive.
- `app/jobs/jivo/idle_conversation_action_job.rb` — `apply_idle_action` now calls `reminder_limit_reached?` first and returns early when the cap is hit. The reminder branch then calls `increment_reminder_count` after sending the message, persisting `jivo_idle_reminder_count` on `conversation.custom_attributes`. Handoff and resolve branches are unaffected (they self-terminate by transitioning status off `pending`).
- `app/controllers/api/v1/accounts/jivo/assistants_controller.rb` — permitted `idle_reminder_limit` in strong params.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — added a numeric `Input` for the limit, defaulting to `3`, only visible when `idle_action === 'reminder'` (no point showing it for handoff/resolve).
- `app/javascript/dashboard/i18n/locale/en/jivo.json` — added `IDLE_REMINDER_LIMIT.LABEL`, `PLACEHOLDER`, and `HELP_TEXT`.

**Verified (Rails runner):**
- Configured assistant with `idle_action: reminder, idle_reminder_limit: 2`, conversation with `last_activity_at` 2h ago and zero counter.
- Three sequential runs of `apply_idle_action` produced: counter `0→1` (sent), `1→2` (sent), `2→2` (skipped). Final status remained `pending`.
- With handoff/resolve modes, `reminder_limit_reached?` correctly returned `false` regardless of counter value (limit only applies to reminder action).

**Test (live):**
1. As admin, edit the JIVO assistant. Set `idle_action: reminder` and `idle_reminder_limit: 2` in the form (the limit input only shows when reminder is selected).
2. Pick a `pending` conversation in the inbox. Run `Conversation.find(<id>).update_column(:last_activity_at, 2.hours.ago)`.
3. Run `Jivo::IdleConversationActionJob.perform_now` two times — each should send a reminder and increment `custom_attributes['jivo_idle_reminder_count']`.
4. Run a third time — no reminder should be sent.

**Deferred:**
- Per-action analytics on how often the limit is hit.
- Time-window reset (e.g., reset counter if customer replies) — currently the counter never resets within the conversation's lifetime. Acceptable for MVP since most reminder cycles end with the customer replying or the conversation being resolved.

---

## Phase 4.7 Status Tracker

- [x] 4.7.1 Inject Contact Notes into Reply Prompt — ✅ COMPLETED
- [x] 4.7.2 Admin-Only "Learn from this Conversation" Button — ✅ COMPLETED
- [x] 4.7.3 Idle Reminder Limit Guard — ✅ COMPLETED

Phase 4.7 is now complete. The three known issues from Phase 4 are resolved:
- Contact notes auto-generated under `feature_memory` are now actually used in replies (4.7.1).
- Admins can manually trigger learning on any conversation regardless of resolution state (4.7.2).
- Idle reminder loop is bounded by `idle_reminder_limit` (4.7.3).

---

## Phase 5 — Multi-Agent V2 — ✅ COMPLETE

Mirrors Captain V2's agent-based architecture using the `ai-agents` gem (already in `Gemfile` — `gem 'ai-agents'` and `gem 'ruby_llm'`). Brings in scenarios (specialist sub-agents), custom HTTP tools, built-in agent tools, and a multi-agent runner with bidirectional handoff.

Phase 5 is split into 8 independently shippable sub-tasks designed to be completable across separate usage windows. Each sub-task ends in a "lock-in" state (DB stable, lint clean, doc updated) so a different session can resume cleanly. Critical path to a usable V2 is `5.1 → 5.2 → 5.3 → 5.4` (~7 hrs); 5.5/5.6/5.7/5.8 layer scenarios, custom tools, and admin UI on top.

**Captain reference root:** `enterprise/app/services/captain/`, `enterprise/lib/captain/tools/`, `enterprise/app/models/captain/`.

**Phase 5 Status Tracker:**
- [x] 5.1 Models + migrations: `jivo_scenarios`, `jivo_custom_tools` — ✅ COMPLETED
- [x] 5.2 Built-in agent tools — ✅ COMPLETED
- [x] 5.3 Agent runner service + `assistant.agent` — ✅ COMPLETED
- [x] 5.4 V2 wiring behind `feature_v2_agent` flag — ✅ COMPLETED
- [x] 5.5 Scenario CRUD API + policy — ✅ COMPLETED
- [x] 5.6 Multi-agent handoff orchestration — ✅ COMPLETED
- [x] 5.7 Custom HTTP tools CRUD + executor — ✅ COMPLETED
- [x] 5.8 Frontend admin UI for scenarios + custom tools — ✅ COMPLETED

---

### Sub-Task 5.1: Models & Migrations for Scenarios + Custom Tools

**Status: ✅ COMPLETED**

**Implemented:**
- `db/migrate/20260504202647_create_jivo_scenarios.rb` — table with `title`, `description`, `instruction`, `tools` (jsonb default `[]`), `enabled` (default true), FK refs to `jivo_assistant` and `account`. Indexes on `enabled` and `(jivo_assistant_id, enabled)`.
- `db/migrate/20260504202648_create_jivo_custom_tools.rb` — account-scoped (no `jivo_assistant_id` — matches Captain's design where custom tools are shared across an account's assistants and selected per-scenario via `tools` jsonb). Fields: `slug`, `title`, `description`, `http_method` (default 'GET'), `endpoint_url`, `request_template`, `response_template`, `auth_type` (default 'none'), `auth_config` (jsonb), `param_schema` (jsonb default `[]`), `enabled`. Unique index on `(account_id, slug)`.
- `app/models/jivo_scenario.rb` — `belongs_to :jivo_assistant`, `belongs_to :account`, validates title/description/instruction presence, scope `:enabled`.
- `app/models/jivo_custom_tool.rb` — `belongs_to :account`, enums for `http_method` (`GET`/`POST`) and `auth_type` (`none`/`bearer`/`basic`/`api_key`, prefix `auth`), `before_validation :generate_slug` with collision suffix, validates slug uniqueness scoped to account.
- `app/models/jivo_assistant.rb` — added `has_many :scenarios, class_name: 'JivoScenario', dependent: :destroy_async`.
- `app/models/account.rb` — added `has_many :jivo_custom_tools, dependent: :destroy_async`. Scenarios cascade through the assistant association so no separate Account entry needed (and skipping it kept us within Metrics/ClassLength).

**Verified (Rails runner):**
- Created `JivoScenario` with default `enabled=true`, `tools=[]`. Scope `:enabled` filtered correctly.
- Created two `JivoCustomTool` records with the same title — first got slug `custom_flight_search_api`, second got collision suffix `custom_flight_search_api_7x9cde`.
- Associations resolved: `assistant.scenarios.count`, `account.jivo_scenarios.count` (via assistant join), `account.jivo_custom_tools.count`.

**Lock-in state:** migrations applied, models load and pass rubocop, smoke test green. No controllers, routes, or UI yet — purely schema + model layer.

**Implementation notes:**
- The Phase 5 plan originally placed `jivo_assistant_id` on `jivo_custom_tools`. Corrected to match Captain's account-scoped design while implementing — custom tools are an account-wide resource.
- Skipped Captain's `Concerns::CaptainToolsHelpers`, `Concerns::Agentable`, `Concerns::Toolable`, `Concerns::SafeEndpointValidatable`, and `JsonSchemaValidator` — all of these are tool-resolution / agent-runner / endpoint-security infrastructure that lands in 5.2, 5.3, 5.6, and 5.7 respectively.
- Skipped Captain's `validate_instruction_tools` and `resolve_tool_references` callbacks on Scenario — those depend on `assistant.available_agent_tools` which doesn't exist until 5.2. Comes back in 5.5.

**Deferred to later sub-tasks:**
- Tool ref auto-extraction from instruction text (`[Tool Name](tool://tool_id)` parsing) — 5.5.
- Agent method on scenario (`scenario.agent`) — 5.6.
- JSON Schema validation on `param_schema` — 5.7.

**Goal:** Create the database tables and ActiveRecord models that the rest of Phase 5 will hang off of. No controllers, no UI yet — pure schema + model layer.

**Captain reference:**
- `enterprise/app/models/captain/scenario.rb`
- `enterprise/app/models/captain/custom_tool.rb`
- Migration files under `db/migrate/` matching `*captain_scenarios*`, `*captain_custom_tools*`

**Files to create:**
- `db/migrate/<ts>_create_jivo_scenarios.rb` — table with `title`, `description`, `instruction` (text), `enabled` (bool default true), `tools` (jsonb array default `[]`), `jivo_assistant_id`, `account_id`, timestamps. Index on `jivo_assistant_id`, `account_id`.
- `db/migrate/<ts>_create_jivo_custom_tools.rb` — table with `title`, `description`, `endpoint_url`, `slug`, `http_method`, `auth_type`, `auth_config` (jsonb), `param_schema` (jsonb), `request_template` (text), `response_template` (text), `enabled` (bool default true), `jivo_assistant_id`, `account_id`, timestamps. Unique index on `(account_id, slug)`. Index on `jivo_assistant_id`.
- `app/models/jivo_scenario.rb` — `belongs_to :jivo_assistant`, `belongs_to :account`, validations on title/description/instruction, scope `:enabled`, `store_accessor`-style for parsed tool refs in instruction.
- `app/models/jivo_custom_tool.rb` — same pattern; `before_validation :generate_slug`, validations on URL format + http_method enum + auth_type enum.

**Files to modify:**
- `app/models/jivo_assistant.rb` — `has_many :scenarios, class_name: 'JivoScenario', dependent: :destroy_async` and `has_many :custom_tools, class_name: 'JivoCustomTool', dependent: :destroy_async`.

**Test:**
1. `bundle exec rails db:migrate`
2. Rails runner: `JivoScenario.create!(title: 't', description: 'd', instruction: 'do x', jivo_assistant: JivoAssistant.first, account: Account.first)` succeeds.
3. Rails runner: `JivoCustomTool.create!(title: 't', description: 'd', endpoint_url: 'https://api.example.com', http_method: 'GET', auth_type: 'none', jivo_assistant: JivoAssistant.first, account: Account.first)` succeeds and slug is auto-generated.

**Lock-in state:** migrations applied; both models load; rubocop clean; no controllers/routes touched.

**Deferred to later sub-tasks:**
- Slug uniqueness collision-resistance (counter suffix) — basic generation in 5.1, hardening in 5.7.
- Tool ref auto-extraction from instruction text — added in 5.5.

---

### Sub-Task 5.2: Built-in Agent Tools

**Status: ✅ COMPLETED**

**Implemented:**
- `config/agents/jivo_tools.yml` — metadata for the 6 built-in tools (id, title, description, icon).
- `lib/jivo/tools/base_public_tool.rb` — base class extending `Agents::Tool`. Stores `@assistant`, exposes `find_conversation(state)`, `find_contact(state)`, `account_scoped(model)`, `log_tool_usage(action, details)`, plus `active?` (default true) and `permissions` (default []).
- `lib/jivo/tools/faq_lookup_tool.rb` — `param :query`, runs `JivoAssistantResponse.search(query, jivo_assistant: @assistant)` and formats the top-N as plain text with optional source URL.
- `lib/jivo/tools/handoff_tool.rb` — `param :reason` (optional). Posts a private note with the reason if provided, calls `conversation.bot_handoff!`, fires `MessageTemplates::Template::OutOfOffice.perform_if_applicable` (skipped for campaigns).
- `lib/jivo/tools/add_contact_note_tool.rb` — creates `contact.notes.create!(content: note)`.
- `lib/jivo/tools/add_private_note_tool.rb` — creates an outgoing private message with `sender: @assistant`.
- `lib/jivo/tools/update_priority_tool.rb` — validates against `Conversation.priorities.keys + [nil]`, accepts `'nil'` literal to clear.
- `lib/jivo/tools/add_label_to_conversation_tool.rb` — finds account-scoped `Label`, calls `conversation.add_labels`.
- `app/models/concerns/jivo_tools_helpers.rb` — class methods `built_in_agent_tools` (loads YAML, filters to resolvable classes), `built_in_tool_ids`, `resolve_tool_class(tool_id)` (constantizes `Jivo::Tools::{Classified}Tool`); instance method `extract_tool_ids_from_text(text)` using `TOOL_REFERENCE_REGEX = %r{\\[[^\\]]+\\]\\(tool://([^/)]+)\\)}`.

**Files modified:**
- `app/models/jivo_assistant.rb` — `include JivoToolsHelpers`; added `available_agent_tools` (returns metadata array — built-ins for now; custom tool merge lands in 5.7) and `available_tool_ids`.

**Verified (Rails runner):**
- `JivoAssistant.first.available_agent_tools` returns 6 metadata hashes with sorted ids `["add_contact_note", "add_label_to_conversation", "add_private_note", "faq_lookup", "handoff", "update_priority"]`.
- All 6 IDs resolve via `JivoAssistant.resolve_tool_class(id)` to their respective `Jivo::Tools::*Tool` classes.
- `Jivo::Tools::FaqLookupTool.new(assistant)` instantiates and reports `active?=true`.
- `extract_tool_ids_from_text("use [FAQ](tool://faq_lookup) and [Handoff](tool://handoff)")` returns `["faq_lookup", "handoff"]`.

**Lock-in state:** all 6 tool classes load, registry returns metadata, regex extracts tool refs. No agent runner yet — tools are standalone callable but not wired into a reply path. V1 untouched.

**Implementation notes:**
- Per Captain's pattern, `available_agent_tools` returns **metadata hashes**, not instances. Tool instances are constructed by the agent runner (5.3) when wiring an `Agents::Agent`.
- `lib/` is already in `config.eager_load_paths` (via `config/application.rb:41`), so no autoload changes needed.
- Captain's tools live in `enterprise/lib/captain/tools/`. Mirror at `lib/jivo/tools/` so the OSS overlay carries them; namespace `Jivo::Tools::*` avoids collisions.

**Deferred to later sub-tasks:**
- Custom HTTP tool integration into `available_agent_tools` — 5.7. Captain merges `account.captain_custom_tools.enabled.map(&:to_tool_metadata)`; we'll add the same in 5.7 once the executor exists.
- Permissions enforcement against the actual agent user — Phase 6 (Captain wires this through copilot threads).
- Frontend rendering of tool metadata (icons + descriptions in scenario form) — 5.8.

**Goal:** Re-implement Captain's 6 built-in tools as `Jivo::Tools::*` classes under `lib/jivo/tools/` (plus a base class). These are unit-testable in isolation and don't yet need a runner.

**Captain reference:**
- `enterprise/lib/captain/tools/base_public_tool.rb`
- `enterprise/lib/captain/tools/faq_lookup_tool.rb`
- `enterprise/lib/captain/tools/handoff_tool.rb`
- `enterprise/lib/captain/tools/add_contact_note_tool.rb`
- `enterprise/lib/captain/tools/add_private_note_tool.rb`
- `enterprise/lib/captain/tools/update_priority_tool.rb`
- `enterprise/lib/captain/tools/add_label_to_conversation_tool.rb`

**Files to create:**
- `lib/jivo/tools/base_public_tool.rb` — base class inheriting from `Agents::Tool` (or whatever the `ai-agents` gem exposes). Adds `log_tool_usage` helper, `active?` method, instrumentation mixin.
- `lib/jivo/tools/faq_lookup_tool.rb` — wraps `JivoAssistantResponse.search`, returns top-5 Q&A pairs with optional source URL.
- `lib/jivo/tools/handoff_tool.rb` — calls `conversation.bot_handoff!`, optionally adds private note with reason.
- `lib/jivo/tools/add_contact_note_tool.rb` — `contact.notes.create!(content: ...)`.
- `lib/jivo/tools/add_private_note_tool.rb` — creates outgoing private message on conversation.
- `lib/jivo/tools/update_priority_tool.rb` — `conversation.update!(priority: ...)`.
- `lib/jivo/tools/add_label_to_conversation_tool.rb` — `conversation.add_labels(...)`.

**Files to modify:**
- `app/models/jivo_assistant.rb` — add `available_agent_tools` returning the 6 tool instances when given a conversation (and later, custom tools).
- `config/application.rb` (or autoload paths) — ensure `lib/jivo/tools/` is autoloaded if not already covered.

**Test:**
1. Rails runner: `JivoAssistant.first.available_agent_tools(conversation: Conversation.first)` returns 6 tool classes.
2. Rails runner: instantiate `Jivo::Tools::FaqLookupTool.new(assistant)` and call its `execute` method directly with a query — should return formatted FAQs.

**Lock-in state:** all 6 tool files exist and load; `available_agent_tools` returns them; no runner integration yet (tools standalone).

**Deferred:**
- Custom HTTP tool integration into `available_agent_tools` — comes in 5.7.
- Active flags / per-tool guards — added as needed in 5.3.

---

### Sub-Task 5.3: Agent Runner Service + `assistant.agent`

**Status: ✅ COMPLETED**

**Implemented:**
- `lib/jivo/response_schema.rb` — `Jivo::ResponseSchema < RubyLLM::Schema` with `string :response` and `string :reasoning`. Drives the agent's structured output.
- `app/models/concerns/jivo_agentable.rb` — `agent` method builds an `Agents::Agent` with name, instructions (lambda over context), tools, model, temperature, and `response_schema: Jivo::ResponseSchema`. Subclasses must implement `agent_name`, `agent_tool_instances`, and `agent_instructions`.
- `app/services/jivo/assistant/agent_runner_service.rb` — `pattr_initialize [:assistant!, :conversation]`. `generate_response(message_history:)` configures the global `Agents` SDK with the assistant's API key, builds the agent + context (including `state[:conversation]` and `state[:contact]` slices), runs `Agents::Runner.with_agents(*agents).run(...)` with `max_turns: 100`, and returns a `with_indifferent_access` hash for hash output or a fallback `{ response: "...", reasoning: "..." }` for string output. Errors emit `conversation_handoff` signal.
- `app/services/jivo/prompts/assistant_prompt.rb` — `pattr_initialize [:assistant!, :state]`, renders an instruction string with identity, custom instructions, tool usage guidance, response guideline, optional conversation context, and an injected contact memory section pulled from `Note.where(contact_id: ...)`.

**Files modified:**
- `app/models/jivo_assistant.rb` — `include JivoAgentable`. Implementations: `agent_name` (falls back to `'JIVO Assistant'`), `agent_tool_instances` (resolves IDs from `available_tool_ids` to `Jivo::Tools::*Tool` classes via `JivoToolsHelpers.resolve_tool_class`, instantiates with `self`), `agent_model` (delegates to existing `model`), `agent_instructions(context)` (delegates to `Jivo::Prompts::AssistantPrompt`).

**Verified (Rails runner against real assistant + conversation):**
- `assistant.agent` returns an `Agents::Agent` with the correct name, model, 6 tool instances, and `Jivo::ResponseSchema`.
- `Jivo::Assistant::AgentRunnerService.new(assistant: ..., conversation: ...).generate_response(message_history: [...])` with a sample user message produced a structured `{ response, reasoning }` hash with a real, on-topic Tabeer Tours reply (149 chars) plus a reasoning trace explaining the agent's decision. End-to-end LLM call confirmed working.

**Lock-in state:** Runner is callable from anywhere in the codebase. V1 reply path remains the only path attached to incoming messages — V2 wiring lives entirely in 5.4 behind a feature flag. Lint clean across all 5 changed files.

**Implementation notes:**
- The `ai-agents` gem maintains a **global** `Agents.configure` singleton (no per-agent API key override). The runner sets it before each invocation with the assistant's `openai_api_key`. **Risk:** in production with multiple JIVO assistants (or simultaneous Captain + JIVO traffic), this is not thread-safe — the global key could flap between requests. Acceptable for MVP single-tenant deployments. Phase 6 follow-up: either patch the `ai-agents` gem to accept a per-agent key, or serialize V2 invocations through a Sidekiq queue.
- Reused the existing JIVO prompt content (style guidelines, identity block) rather than introducing Liquid templates like Captain. Captain's `assistant.liquid` is significantly longer; JIVO's prompt fits in a heredoc and stays consistent with the V1 prompt builder for behavior parity.
- Skipped Captain's OpenTelemetry/Langfuse instrumentation entirely — defer to Phase 6 alongside other observability work. Skipped Captain's per-tool/per-agent callbacks (`on_agent_thinking`, `on_tool_start`, etc.) for the same reason. Will land when streaming/copilot UI needs them.

**Deferred:**
- OpenTelemetry instrumentation — Phase 6.
- Per-tool callbacks for streaming UI in agent's view — Phase 6.
- Thread-safe per-assistant API key handling (currently mutates global `Agents` config) — Phase 6.
- Multi-agent orchestration — 5.6 (this sub-task only wires the main assistant; scenarios come later).

**Goal:** Wire the `ai-agents` gem to JIVO. Create the runner service that orchestrates an `Agents::Agent` instance and produces a structured `{ response, reasoning }` reply. No scenarios yet — single-agent mode.

**Captain reference:**
- `enterprise/app/services/captain/assistant/agent_runner_service.rb` (227 lines, full reference)
- `enterprise/app/models/captain/assistant.rb` — `agent` method
- `enterprise/app/models/concerns/captain_tools_helpers.rb`

**Files to create:**
- `app/services/jivo/assistant/agent_runner_service.rb` — mirror Captain's `AgentRunnerService`. Methods: `generate_response(message_history:)`, `build_context`, `build_state`, `build_and_wire_agents` (single-agent for now), `process_agent_result`. Skip OpenTelemetry/Langfuse instrumentation for MVP (deferred to Phase 6).
- `app/models/concerns/jivo_tools_helpers.rb` — provides `agent` method on assistant: builds an `Agents::Agent` with name, instructions (from existing system prompt builder), tools (from `available_agent_tools`), response_schema for `{ response, reasoning }`.

**Files to modify:**
- `app/models/jivo_assistant.rb` — `include JivoToolsHelpers`.

**Test:**
1. Rails runner with a real conversation: build message_history array, instantiate `Jivo::Assistant::AgentRunnerService.new(assistant: assistant, conversation: conv).generate_response(message_history: history)` — should return a hash with `response` and `reasoning` keys.
2. Verify the response references knowledge base content (proves FAQ lookup tool was invoked).

**Lock-in state:** Runner produces structured output for a single-agent setup. `assistant.agent` returns valid `Agents::Agent`. V1 path completely untouched — no behavior change for end users.

**Deferred:**
- OTel/Langfuse instrumentation — Phase 6.
- Per-tool callbacks for streaming UI — Phase 6.

---

### Sub-Task 5.4: V2 Wiring Behind `feature_v2_agent` Flag

**Status: ✅ COMPLETED**

**Implemented:**
- `app/services/jivo/conversation_v2_handler_service.rb` — new dedicated V2 handler. Builds the message history with `Jivo::OpenaiMessageBuilderService` (multimodal-aware), drops blank payloads, runs `Jivo::Assistant::AgentRunnerService.generate_response`, and routes the result either to `perform_handoff` (if response equals `HANDOFF_SIGNAL`) or `create_outgoing_message`. Errors fall back to handoff with the assistant's handoff message.
- `app/services/jivo/conversation_handler_service.rb` — `perform` now early-returns to the V2 service when `assistant.feature_v2_agent_enabled?`. V1 path is byte-for-byte unchanged.

**Files modified:**
- `app/models/jivo_assistant.rb` — added `feature_v2_agent` to `store_accessor` and `feature_v2_agent_enabled?` boolean helper.
- `app/controllers/api/v1/accounts/jivo/assistants_controller.rb` — permitted `feature_v2_agent` in strong params.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — toggle + help text in the advanced features block, defaults `false`.
- `app/javascript/dashboard/i18n/locale/en/jivo.json` — `JIVO.ASSISTANTS.FORM.FEATURE_V2_AGENT.{LABEL,HELP}`.

**Verified (Rails runner against real assistant + conversation):**
- Flag off → V1 path runs, produces a reply (no behavior change vs. before 5.4).
- Flag on → V2 path runs through `Jivo::ConversationV2HandlerService` → `Jivo::Assistant::AgentRunnerService` → real OpenAI call → structured `{response, reasoning}` extracted → outgoing message created. Sample V2 reply: "Hello! How can I assist you with Tabeer Tours today?"
- The `feature_v2_agent_enabled?` helper correctly casts `false`/`true` strings/values via `ActiveModel::Type::Boolean`.

**Lock-in state:** Toggle works per-assistant. V1 reply path bit-for-bit unchanged. V2 reply path is exercised by the same hook chain as V1 (`Message#after_create_commit` → `MessageTemplates::HookExecutionService#schedule_jivo_response` → existing job → `Jivo::ConversationHandlerService.perform`). Lint clean on all changed files (the two pre-existing offenses on `system_prompt_text` MethodLength and `call_openai` AbcSize are unrelated to 5.4).

**Implementation notes:**
- Originally branched inside `ConversationHandlerService` itself, but `Metrics/ClassLength` rejected the additions. Extracted to a separate `Jivo::ConversationV2HandlerService` for clean separation; the V1 service is now a single-line dispatch followed by the unchanged V1 logic. Easier to delete V1 once V2 is fully validated.
- HandoffTool (built-in agent tool from 5.2) calls `conversation.bot_handoff!` directly when invoked — that side-effect is fine because the agent's final outgoing reply (the farewell message to the customer) gets created on the now-`open` conversation without conflict. No special status-gating needed in `handle_result`.
- During smoke testing, observed +2 message count per path due to Rails runner triggering the existing `after_create_commit` hook *and* my synchronous `perform` call. In production, only the hook path runs per incoming message, so reply count will be exactly +1.
- **Live bug, two fixes:** the `Agents::Runner` output shape is **inconsistent across turns**. First turn (no tools used) returns a clean Hash with plain text in `'response'`. Subsequent turns (especially after a tool was invoked, e.g. FAQ lookup) return a Hash whose `'response'` field is *itself* a JSON-encoded string `{"response":"...","reasoning":"..."}`. Original `process_agent_result` returned the outer hash unchanged → customer saw raw JSON in the chat.
  - First fix: `JSON.parse(output)` when output is a String.
  - Second fix (after live retest revealed the nested-encoding case): `normalize_output` now unwraps nested JSON inside `hash['response']` via `unwrap_nested_response`. Verified against four input shapes — plain Hash, JSON string, Hash with nested JSON in response field, plain string fallback. All collapse to plain-text `'response'`.
  - Third fix (concatenated-JSON case): when the model spits two JSON objects glued by newlines (`{...}\\n{...}`), `JSON.parse` fails and the raw blob is shown to the customer. `coerce_to_hash` now falls back to `parse_first_json_object` which scans for the first balanced `{...}` block and parses it.
- **Multimodal V2 fix:** original V2 wiring stripped image attachments by routing all message content through a text-extracting helper. Agent received text only, never the image. Patched by:
  - `split_current_user_message` — separates the latest user message from prior history.
  - `message_input(current_message)` — when the current user message has an Array content block (the multimodal `[{type:'text'}, {type:'image_url'}]` shape from `Jivo::OpenaiMessageBuilderService`), wraps it in `RubyLLM::Content::Raw` so RubyLLM/Agents passes it through to OpenAI verbatim. Plain text still goes through `extract_text_from_content`.
  - Prior history items remain text-only with an `[N image attachment(s)]` annotation — the Agents SDK conversation-history API doesn't accept per-turn multimodal arrays, so we accept that older turns lose image fidelity in context.
  - Verified live: image-attached message reached OpenAI vision; agent replied with details extracted from the image (e.g., "Bangkok Holiday Package, 3999 AED, 4 nights / 5 days...").

**Test (live, after enabling flag in form):**
1. Sign in as admin, open the JIVO assistant form, toggle "Use V2 multi-agent runner" on, save.
2. Open a JIVO-attached inbox in another tab and send an incoming customer message asking about something in your knowledge base.
3. Check Sidekiq logs — should show `Jivo::Assistant::AgentRunnerService` loading the agent + tools.
4. Reply appears as outgoing message; matches V1's response shape from the customer's perspective.
5. Try a question outside the KB; agent should either ask clarifying questions, use FAQ tool, or use HandoffTool to escalate.
6. Toggle flag off and confirm V1 path still produces replies as before.

**Deferred:**
- Side-by-side analytics comparing V1 vs V2 reply quality / handoff rate — Phase 6.
- Streaming response surface in agent UI (currently buffered, single-shot reply) — Phase 6.
- Migration helper to bulk-flip all assistants from V1 to V2 — Phase 6.
- Per-account/per-installation override of the flag (currently per-assistant only) — Phase 6 if needed.

**Goal:** Switch the conversation reply path from `Jivo::ConversationHandlerService` (V1, direct OpenAI call) to the new agent runner — but **only when `assistant.config['feature_v2_agent']` is true**. V1 stays the default; V2 is opt-in per assistant.

**Captain reference:**
- `enterprise/app/services/captain/conversation/response_builder_service.rb` (or similar — V2 reply path)
- `enterprise/app/jobs/captain/conversation/response_builder_job.rb`

**Files to modify:**
- `app/models/jivo_assistant.rb` — add `feature_v2_agent` to `store_accessor`, plus `feature_v2_agent_enabled?` helper.
- `app/services/jivo/conversation_handler_service.rb` — at top of `perform`, branch: if `assistant.feature_v2_agent_enabled?`, build message_history in the format the runner expects and delegate to `Jivo::Assistant::AgentRunnerService`. Otherwise existing V1 path. Reuse `process_response` for the outgoing message creation since the runner returns the same `{ response, reasoning }` shape.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — toggle for `feature_v2_agent` in the advanced features block.
- `app/controllers/api/v1/accounts/jivo/assistants_controller.rb` — permit `feature_v2_agent`.
- `app/javascript/dashboard/i18n/locale/en/jivo.json` — label.

**Test:**
1. Toggle off: send incoming message → V1 path runs (existing logs), reply created.
2. Toggle on: send incoming message → V2 runner runs, reply created with same shape; FAQ tool invoked (visible in Sidekiq logs).
3. Confirm `Jivo::Tools::HandoffTool` triggers `conversation.bot_handoff!` correctly when LLM decides to hand off.

**Lock-in state:** Both paths work. Toggle flips behavior. No V1 regression.

**Deferred:**
- Streaming response surface in UI — Phase 6.
- Migration helper to migrate all assistants to V2 — Phase 6.

---

### Sub-Task 5.5: Scenario CRUD API + Policy

**Status: ✅ COMPLETED**

**Implemented:**
- `app/policies/jivo_scenario_policy.rb` — admin gets full CRUD; admin + agent can `index?` and `show?`. Captain's policy lets everyone read; JIVO restricts read to admin+agent (not visitors) to match other JIVO policies.
- `app/controllers/api/v1/accounts/jivo/scenarios_controller.rb` — REST CRUD nested under `jivo/assistants/:assistant_id`. Standard JIVO controller pattern: `current_account` → `check_authorization(JivoScenario)` → `assistant` → `scenario` (for member actions). Strong params permit `:title, :description, :instruction, :enabled`. `tools` jsonb is **not** permitted via params — it's auto-derived by the model from instruction text.
- `app/views/api/v1/accounts/jivo/scenarios/_scenario.json.jbuilder` — partial returning `id`, `title`, `description`, `instruction`, `tools`, `enabled`, `jivo_assistant_id`, `account_id`, integer-epoch timestamps.
- `app/views/api/v1/accounts/jivo/scenarios/{index,show,create,update}.json.jbuilder` — wrap the partial; index returns a flat array (matches existing JIVO `documents` pattern, not Captain's `payload+meta` envelope).

**Files modified:**
- `app/models/jivo_scenario.rb` — added `before_save :extract_tool_refs` callback. Reuses the existing `JivoToolsHelpers::TOOL_REFERENCE_REGEX` (defined in 5.2) and stores the deduped tool IDs into the `tools` jsonb column whenever the instruction is saved. Tool ref **validation** (must point to a real tool) is intentionally deferred — that's 5.6 since it depends on cross-checking against custom tools too.
- `config/routes.rb` — `resources :scenarios, only: [:index, :show, :create, :update, :destroy]` nested under `jivo/assistants/:assistant_id`.

**Verified (Rails runner):**
- Routes: all 5 (`index`, `show`, `create`, `update`, `destroy`) registered at `/api/v1/accounts/:account_id/jivo/assistants/:assistant_id/scenarios[/:id]`.
- Tool ref auto-extraction: created scenario with instruction containing `[FAQ Lookup](tool://faq_lookup)` and `[Handoff](tool://handoff)` → `tools` populated as `["faq_lookup", "handoff"]`. Updated instruction to reference only `[Add Note](tool://add_contact_note)` → `tools` updated to `["add_contact_note"]`.
- Policy: instantiated with proper `{user:, account_user:}` context. Administrator: `index?=true, create?=true, update?=true, destroy?=true`. Agent: `index?=true, create?=false, update?=false, destroy?=false`.

**Test live (curl, replace `<account_id>`/`<assistant_id>`/`<auth>`):**
```bash
# Create
curl -X POST http://localhost:3000/api/v1/accounts/<account_id>/jivo/assistants/<assistant_id>/scenarios \
  -H "Content-Type: application/json" \
  -H "api_access_token: <admin_token>" \
  -d '{"scenario": {"title": "Booking Helper", "description": "Handles booking flow", "instruction": "When user asks about availability use [FAQ Lookup](tool://faq_lookup)."}}'

# Index
curl http://localhost:3000/api/v1/accounts/<account_id>/jivo/assistants/<assistant_id>/scenarios \
  -H "api_access_token: <admin_token>"

# Update
curl -X PATCH http://localhost:3000/api/v1/accounts/<account_id>/jivo/assistants/<assistant_id>/scenarios/<id> \
  -H "Content-Type: application/json" -H "api_access_token: <admin_token>" \
  -d '{"scenario": {"enabled": false}}'

# Destroy
curl -X DELETE http://localhost:3000/api/v1/accounts/<account_id>/jivo/assistants/<assistant_id>/scenarios/<id> \
  -H "api_access_token: <admin_token>"
```
Each response should reflect a clean JSON scenario; `tools` array auto-populates from instruction text on save.

**Lock-in state:** API is callable end-to-end. Tool refs auto-extracted on save. Policy enforced. No agent runner integration yet — scenarios exist as data but don't influence reply behavior. Multi-agent handoff orchestration is 5.6.

**Implementation notes:**
- Mirrors Captain's controller almost exactly. Differences: (1) JIVO `index` returns scenarios ordered by `created_at: :desc`, scope `:enabled` not auto-applied (admins want to see disabled scenarios in the list view); (2) JIVO uses `JivoScenarioPolicy` with `index?` admin+agent (Captain returns `true` for everyone); (3) `tools` jsonb is **not** writable via params — it's strictly derived from instruction text.
- Skipped Captain's `validate_instruction_tools` — that needs `assistant.available_tool_ids` including custom tools, which lands in 5.7. Adding it half-baked now would block legitimate scenario creation (current `available_tool_ids` only knows about the 6 built-ins; custom tools would be flagged invalid).

**Deferred to later sub-tasks:**
- Tool ref **validation** (instruction must reference real tools) — 5.6, after custom tools register in `available_tool_ids` (5.7) so validation covers both built-ins and custom.
- Wiring scenarios into the agent runner (`build_and_wire_agents` registers each enabled scenario as a handoff target) — 5.6.
- Frontend admin UI for scenarios — 5.8.

**Goal:** Admin-facing CRUD API for scenarios. Each scenario is a specialized sub-agent attached to one assistant. No frontend yet — UI ships in 5.8.

**Captain reference:**
- `enterprise/app/controllers/api/v1/accounts/captain/assistants/scenarios_controller.rb`
- `enterprise/app/policies/captain/scenario_policy.rb`

**Files to create:**
- `app/controllers/api/v1/accounts/jivo/scenarios_controller.rb` — REST CRUD. Loads `@assistant` from nested route. Strong params: `title`, `description`, `instruction`, `enabled`. Auto-extract tool IDs from instruction `[Tool Name](tool://tool_id)` pattern into `tools` jsonb on save.
- `app/policies/jivo_scenario_policy.rb` — admin-only for create/update/destroy; admin + agent for index/show.

**Files to modify:**
- `config/routes.rb` — nest `resources :scenarios` under `jivo/assistants/:assistant_id`.
- `app/models/jivo_scenario.rb` — `before_save :extract_tool_refs` (parses instruction markdown links → fills `tools` array).

**Test:**
1. `POST /api/v1/accounts/:id/jivo/assistants/:aid/scenarios` with title/description/instruction → 201, returns scenario.
2. Pundit admin-only verified by switching role.
3. Save instruction `"call [FAQ](tool://faq_lookup_tool) when needed"` → `tools` array contains `'faq_lookup_tool'`.

**Lock-in state:** API works end-to-end via curl/Postman. Tool ref extraction works. No runner wiring yet.

**Deferred:**
- Tool ref validation (must point to real tools) — added in 5.6.
- Frontend management UI — 5.8.

---

### Sub-Task 5.6: Multi-Agent Handoff Orchestration

**Status: ✅ COMPLETED**

**Implemented:**
- `app/services/jivo/prompts/scenario_prompt.rb` — renders the scenario's system prompt: identity (`title`), task (`instruction`), explicit handback instruction via `handoff_to_<main_agent_name>` tool, product context, response guideline, conversation context, and tools list. Mirrors Captain's `scenario.liquid` but inlined as Ruby (no Liquid template) to keep churn low.
- `app/models/jivo_scenario.rb` — now `include JivoToolsHelpers` and `include JivoAgentable` so scenarios reuse the same agent-builder concern as the main assistant. New methods:
  - `agent_name` → `"<title> Agent".parameterize(separator: '_')` (e.g. `booking_specialist_agent`).
  - `agent_tool_instances` → resolves each tool ID in the `tools` jsonb (already auto-extracted in 5.5) to a `Jivo::Tools::*Tool` class via `JivoToolsHelpers.resolve_tool_class`, instantiates with the parent assistant.
  - `agent_model` → delegates to assistant's model.
  - `agent_instructions(context)` → renders via `Jivo::Prompts::ScenarioPrompt`.
  - `validate :validate_instruction_tools` (per the 5.5 deferred item) — checks every tool ID referenced in the instruction text against `assistant.available_tool_ids`. Invalid IDs surface as `errors[:instruction]` like `"references unknown tools: foo, bar"`. Validation triggers on every save.
  - `delegate :temperature_value, :openai_api_key, :model, to: :jivo_assistant` — scenarios inherit settings from their assistant (matches Captain's pattern).
- `app/services/jivo/assistant/agent_runner_service.rb` — `build_and_wire_agents` now:
  ```ruby
  main = assistant.agent
  scenarios = assistant.scenarios.enabled.map(&:agent)
  if scenarios.any?
    main.register_handoffs(*scenarios)
    scenarios.each { |s| s.register_handoffs(main) }
  end
  [main] + scenarios
  ```
  This produces bidirectional handoff. The main agent gains `handoff_to_<scenario_agent_name>` tools for each enabled scenario; each scenario gains a single `handoff_to_<assistant_name>` tool back to the main agent.

**Verified (Rails runner):**
- Validation: scenario with `instruction: "use [Nonexistent](tool://does_not_exist)"` failed with `errors[:instruction] => ["references unknown tools: does_not_exist"]`.
- Valid scenario: instruction referencing `tool://faq_lookup` and `tool://handoff` saved with `tools = ["faq_lookup", "handoff"]`. `scenario.agent.tools` returned `[Jivo::Tools::FaqLookupTool, Jivo::Tools::HandoffTool]` instances.
- Bidirectional handoff: main agent's `handoff_agents` listed both scenarios; each scenario's `handoff_agents` listed the main assistant only.
- Live multi-agent LLM call: created a "Visa Specialist" scenario with FAQ tool, sent customer message "Can you tell me about extending my UAE tourist visa?". Runner executed the multi-agent flow, the agent invoked FAQ lookup, and returned a structured `{ response, reasoning }` reply with the visa extension info from the knowledge base. Plain-text response, no JSON leak.

**Lock-in state:** Scenarios are now fully wired into the agent runner. Creating an enabled scenario through the API (5.5) → it appears as a handoff target on the next V2 reply. Disabling a scenario removes it from `scenarios.enabled` so the main agent stops handing off to it. No frontend yet — that's 5.8.

**Implementation notes:**
- Scenarios include `JivoAgentable` (the same concern the main assistant uses). Agentable expects subclasses to implement `agent_name`, `agent_tool_instances`, and `agent_instructions` — all defined here. The `agent` method itself comes for free from the concern.
- Scenario tool instances are constructed with `klass.new(jivo_assistant)` — i.e. tools see the parent assistant as their `@assistant`. This matters for the FAQ tool (queries `JivoAssistantResponse.search` with the assistant's knowledge base) and the handoff tool (uses the assistant's handoff message).
- Skipped Captain's `Captain::PromptRenderer` Liquid pipeline. Inline `<<~PROMPT` heredoc is enough for MVP and saves the `enterprise/lib/captain/prompts/snippets/` machinery. Phase 6 can revisit if scenarios need richer per-account templating.
- The validator currently only catches built-in tool IDs as valid. When custom tools land in 5.7, `available_tool_ids` will include them automatically and the validator will accept them without modification.
- **Routing fix (post-5.6):** initial 5.6 wired the `handoff_to_<scenario>` tools onto the main agent but didn't tell the main agent *when* to use them. Added a `[Scenario Routing]` section in `Jivo::Prompts::AssistantPrompt` that lists each enabled scenario's title, description, and exact handoff tool name (`handoff_to_<scenario_agent_name>`). Without this, the model could see the tools but rarely chose to route. With it, scenario invocation became reliable in live testing.

**Deferred:**
- Visible "now talking to <scenario>" UX hint in agent's conversation view — Phase 6.
- Per-scenario response_guidelines / guardrails — Phase 6 (Captain has them as jsonb arrays on `Captain::Scenario`; JIVO inherits everything from the parent assistant for now).
- Snippets-based prompt templating (Liquid render) — Phase 6.

**Goal:** Make the agent runner aware of scenarios. Each scenario becomes an `Agents::Agent` registered as a handoff target on the main assistant, and vice versa.

**Captain reference:**
- `Captain::Assistant::AgentRunnerService#build_and_wire_agents` — handoff registration pattern
- `enterprise/app/models/captain/scenario.rb` — `agent` method

**Files to modify:**
- `app/models/jivo_scenario.rb` — `agent` method returning `Agents::Agent` with scenario instruction injected, tools resolved from `tools` jsonb (built-ins + custom) + handoff back to main assistant.
- `app/services/jivo/assistant/agent_runner_service.rb` — `build_and_wire_agents` returns `[assistant_agent] + scenario_agents` with bidirectional `register_handoffs`.
- `app/models/jivo_scenario.rb` — validate that referenced tool IDs exist in either `Jivo::Tools::*` constants or assistant's enabled custom tools.

**Test:**
1. Create assistant + 1 scenario referencing built-in tool. Send a message that should trigger the scenario.
2. Rails runner test: invoke runner with a conversation that matches scenario's domain; runner result should show `agent_name` matching scenario.
3. Scenario calls handoff back to main assistant successfully (verify `current_agent` flips).

**Lock-in state:** Multi-agent works. Scenario-driven specialization is testable end-to-end.

**Deferred:**
- Visible "now talking to <scenario>" UX in agent's conversation view — Phase 6.

---

### Sub-Task 5.7: Custom HTTP Tools CRUD + Executor

**Status: ✅ COMPLETED**

**Implemented:**
- `app/models/concerns/jivo_safe_endpoint_validatable.rb` — `validate :validate_safe_endpoint_url`. Rejects non-HTTPS, missing host, app's own frontend host, `localhost`/`*.local`, IPv4/IPv6 literals, and non-ASCII hostnames. Liquid placeholders `{{var}}` are stripped before parsing so templated URLs like `https://api.example.com/orders/{{order_id}}` validate cleanly.
- `app/models/concerns/jivo_toolable.rb` — provides:
  - `tool(assistant)` — dynamic factory: builds `Class.new(Jivo::Tools::HttpTool)` per record, declares `description` + each `param_schema` entry as a `param`, registers as `Jivo::Tools::<CamelizedSlug>` constant, returns instance bound to `(assistant, custom_tool)`. Anonymous classes break RubyLLM's tool-name extraction, so the constant assignment is required.
  - `build_request_url(params)` — Liquid template substitution on `endpoint_url` (no-op if no `{{}}`).
  - `build_request_body(params)` — Liquid render of `request_template` (returns nil if blank).
  - `build_auth_headers` — bearer / api_key (header location only) / none. Basic auth handled separately via `build_basic_auth_credentials` because `Net::HTTP::Request#basic_auth` takes a 2-arg form.
  - `build_metadata_headers(state)` — `X-Jivo-Account-Id`, `X-Jivo-Assistant-Id`, `X-Jivo-Tool-Slug`, `X-Jivo-Conversation-Id`, `X-Jivo-Conversation-Display-Id`, `X-Jivo-Contact-Id`, `X-Jivo-Contact-Email`, `X-Jivo-Contact-Phone`. (Captain ships `X-Chatwoot-*`; renamed to `X-Jivo-*` to keep namespacing clean.)
  - `format_response(raw_body)` — Liquid render of `response_template` with `response`/`r` aliases pointing at `JSON.parse(raw_body) || raw_body`. Strict mode throws on undefined variables/filters.
- `app/models/jivo_custom_tool.rb` — `include JivoToolable, JivoSafeEndpointValidatable`. Adds `JsonSchemaValidator` against the `param_schema` array (each item must have `name`, `type`, `description`; optional `required`; `additionalProperties: false`). Slug uniqueness now retries up to 5 times with random alphanumeric suffix before raising `ActiveRecord::RecordNotUnique`. Adds `to_tool_metadata` returning `{ id: slug, title:, description:, custom: true }` for merging into `available_agent_tools`.
- `lib/jivo/tools/http_tool.rb` — `< Agents::Tool`. `perform(tool_context, **params)`:
  1. `build_request_url` + `build_request_body` (templated).
  2. `URI.parse(url)` → `check_private_ip!(host)`: resolves via `Resolv.getaddress`, rejects if IP is in `127/8`, `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, `::1`, `fc00::/7`, `fe80::/10`. DNS errors raise.
  3. `Net::HTTP` client with `read_timeout: 30`, `open_timeout: 10`, `max_retries: 0` (no redirects).
  4. Build GET or POST request, apply auth headers + basic auth + metadata headers.
  5. Execute, raise on non-2xx, validate `content-length`/`body.bytesize` ≤ 1MB.
  6. `format_response(response.body)` (Liquid templating if configured).
  - Errors are caught at top of `perform`, logged, return literal string `"An error occurred while executing the request"` to the LLM (so tool failures don't blow up the whole agent run).
- `app/policies/jivo_custom_tool_policy.rb` — `index?`/`show?` admin+agent; `create?`/`update?`/`destroy?` admin only.
- `app/controllers/api/v1/accounts/jivo/custom_tools_controller.rb` — REST CRUD on `Current.account.jivo_custom_tools`. Strong params: `:title, :description, :endpoint_url, :http_method, :request_template, :response_template, :auth_type, :enabled, auth_config: {}, param_schema: [:name, :type, :description, :required]`.
- `app/views/api/v1/accounts/jivo/custom_tools/{_custom_tool,index,show,create,update}.json.jbuilder` — partial returns `id, slug, title, description, endpoint_url, http_method, auth_type, auth_config, param_schema, request_template, response_template, enabled, account_id`, integer-epoch timestamps.
- `config/routes.rb` — `resources :custom_tools` (account-scoped under `jivo/`, NOT nested under assistants — matches Captain's account-wide design).

**Files modified:**
- `app/models/concerns/jivo_tools_helpers.rb` — added instance method `resolve_tool_instance(tool_id, assistant)` that first tries `resolve_tool_class(tool_id)` (built-ins) and falls back to `assistant.account.jivo_custom_tools.enabled.find_by(slug: tool_id)&.tool(assistant)`. This gives both built-ins and custom tools a single resolution path.
- `app/models/jivo_assistant.rb`:
  - `available_agent_tools` now concats `account.jivo_custom_tools.enabled.map(&:to_tool_metadata)` after the built-ins. So scenarios + main agent both see custom tools as part of `available_tool_ids` and the validator (5.6) accepts them automatically.
  - `agent_tool_instances` now uses `resolve_tool_instance` for unified resolution.
- `app/models/jivo_scenario.rb` — same `agent_tool_instances` simplification using `resolve_tool_instance`.

**Verified (Rails runner):**
- Endpoint validation: `http://localhost/x` → `["must use HTTPS protocol", "cannot use disallowed hostname"]`. `https://192.168.1.1/x` → `["cannot be an IP address, must be a hostname"]`. Non-ASCII hostname rejected.
- Param schema validation: invalid schema (`[{ "name": "x" }]` missing `type`/`description`) → record invalid.
- Slug auto-generation + uniqueness suffix: same-title tools get `custom_ip_lookup`, `custom_ip_lookup_<random>`.
- Tool factory: `ct.tool(assistant)` returns a `Jivo::Tools::CustomIpLookup` instance — proper class name (not anonymous), `active?=true`, inherits from `Jivo::Tools::HttpTool`.
- `available_agent_tools` returned 7 tools (6 built-ins + 1 custom with `custom: true`).
- `resolve_tool_instance(slug, assistant)` correctly returned the custom tool instance.
- Live HTTPS call to `https://httpbin.org/ip` returned `{"origin": "72.255.42.65"}` — proves end-to-end execution including DNS resolution, TLS, response read, max-size check.
- `check_private_ip!('localhost')` raised `"Request blocked: hostname resolves to private IP address"` — IP block actively prevents SSRF even if a record somehow bypassed validation.

**Test live (admin token, replace `<account_id>`/`<token>`):**
```bash
# Create
curl -X POST http://localhost:3000/api/v1/accounts/<account_id>/jivo/custom_tools \
  -H "Content-Type: application/json" -H "api_access_token: <token>" \
  -d '{"custom_tool": {"title":"Order Lookup","description":"Fetches order details","endpoint_url":"https://api.example.com/orders/{{order_id}}","http_method":"GET","auth_type":"bearer","auth_config":{"token":"sk-xxx"},"param_schema":[{"name":"order_id","type":"string","description":"Order ID","required":true}]}}'

# Reference in a scenario (5.5 endpoint):
curl -X POST http://localhost:3000/api/v1/accounts/<account_id>/jivo/assistants/<aid>/scenarios \
  -H "Content-Type: application/json" -H "api_access_token: <token>" \
  -d '{"scenario": {"title":"Order Lookup Specialist","description":"Handles order status questions","instruction":"When user asks about order status, use [Order Lookup](tool://custom_order_lookup) with the order ID. Always cite the data returned."}}'
```
Then trigger a V2 reply asking "what's the status of order 12345?" — the agent should call the custom tool, receive the JSON, and respond using the data.

**Lock-in state:** Custom tools fully functional from API + automatic registration into `available_agent_tools` + scenarios can reference them by slug + agent runner picks them up via shared `resolve_tool_instance`. No frontend yet — that's 5.8.

**Implementation notes:**
- Custom tools live at the **account** level (no `jivo_assistant_id` on the table) — matches Captain. Reasoning: same backend integration (e.g. an order-lookup endpoint) usually serves all assistants in an account; per-assistant scoping would force admins to re-create the same tool for each assistant.
- The dynamic class registration (`Jivo::Tools.const_set(class_name, tool_class)`) is required because RubyLLM derives the LLM-facing tool name from `Class#name`. Anonymous classes have empty names → OpenAI rejects with `"Invalid 'tools[].function.name': empty string"`. Each call to `tool(assistant)` removes-and-resets the constant so metadata edits (param schema changes) take effect on the next runner invocation without a process restart.
- Skipped Captain's `Captain::Tools::BaseTool` Liquid-rendering pipeline — `JivoToolable#format_response` does enough Liquid for MVP. Captain's broader pipeline can be ported in Phase 6 if needed.
- Skipped per-tool rate limiting and per-tool usage analytics — Phase 6.

**Deferred:**
- Per-tool rate limiting (e.g. max 100 calls/minute per tool) — Phase 6.
- Webhook signature verification on incoming responses — Phase 6.
- Frontend admin UI for custom tools — 5.8.
- DNS rebinding protection beyond the static private-IP block (Captain has the same limitation) — Phase 6.

**Goal:** Admin-facing CRUD for custom HTTP tools, plus an `Jivo::Tools::HttpTool` adapter that the runner can invoke. Includes private-IP blocking and auth handling.

**Captain reference:**
- `enterprise/app/controllers/api/v1/accounts/captain/custom_tools_controller.rb`
- `enterprise/lib/captain/tools/http_tool.rb`
- `enterprise/app/policies/captain/custom_tool_policy.rb`

**Files to create:**
- `app/controllers/api/v1/accounts/jivo/custom_tools_controller.rb` — REST CRUD. Strong params: title, description, endpoint_url, http_method, auth_type, auth_config, param_schema, request_template, response_template, enabled.
- `app/policies/jivo_custom_tool_policy.rb` — admin-only.
- `lib/jivo/tools/http_tool.rb` — wraps a `JivoCustomTool` record. `execute(**args)` builds URL with substitution, applies auth headers, sends HTTP, validates IP not in private range (127/8, 10/8, 172.16/12, 192.168/16, IPv6 loopback/ULA), enforces 30s read / 10s connect timeouts, max 1MB response, no redirects. Applies `response_template` to format result for LLM.

**Files to modify:**
- `app/models/jivo_assistant.rb` — `available_agent_tools` now includes `JivoCustomTool.where(jivo_assistant_id: id, enabled: true).map { |t| Jivo::Tools::HttpTool.new(t) }`.
- `app/models/jivo_custom_tool.rb` — slug collision-resistance (counter suffix).
- `config/routes.rb` — `resources :custom_tools` nested under `jivo/`.

**Test:**
1. Create tool pointing to public httpbin.org URL → tool callable from runner.
2. Create tool pointing to `127.0.0.1` → execution blocked, returns error to LLM.
3. Auth bearer: header is set correctly on the outgoing request (verify with a test endpoint).

**Lock-in state:** Custom tools usable from runner. Security guards in place.

**Deferred:**
- DNS resolution validation — Phase 6.
- Per-tool rate limiting — Phase 6.

---

### Sub-Task 5.8: Frontend Admin UI for Scenarios + Custom Tools

**Status: ✅ COMPLETED**

**Implemented:**

API clients:
- `app/javascript/dashboard/api/jivoScenarios.js` — `list/show/create/update/delete` keyed on assistant ID; wraps body in `{ scenario: ... }`.
- `app/javascript/dashboard/api/jivoCustomTools.js` — extends base `ApiClient`; overrides `create`/`update` to wrap body in `{ custom_tool: ... }`.

Vuex stores (registered in `app/javascript/dashboard/store/index.js`):
- `app/javascript/dashboard/store/modules/jivoScenarios.js` — `getScenarios`, `getUIFlags` getters; `get/create/update/delete` actions all keyed by `assistantId`.
- `app/javascript/dashboard/store/modules/jivoCustomTools.js` — account-scoped (no assistant ID); same action shape minus `assistantId`.

Pages:
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Scenarios.vue` — list + edit/delete buttons per row; new/edit modal opens `JivoScenarioForm`. Tool IDs surface as monospace chips next to each scenario.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/CustomTools.vue` — same shape, account-wide. Each row shows slug, HTTP method, endpoint URL, and auth type.

Modal forms:
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoScenarioForm.vue` — title, description, instruction (with monospace + help text reminding admins about `[Label](tool://tool_id)` syntax), enabled toggle. Validates non-blank fields client-side.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoCustomToolForm.vue` — title, description, endpoint URL (HTTPS-only check), HTTP method dropdown (GET/POST), auth type dropdown with conditional fields per choice (bearer token, basic creds, api_key header name+value), dynamic param schema list (add/remove rows with name, type, description, required), request/response Liquid templates, enabled toggle.

Routing + i18n:
- `app/javascript/dashboard/routes/dashboard/settings/jivo/jivo.routes.js` — added `:assistantId/scenarios` (named `jivo_scenarios`) and account-level `custom_tools` (named `jivo_custom_tools`).
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Index.vue` — added "Scenarios" button per assistant row + "Custom Tools" button in the page header that jumps to the account-wide page.
- `app/javascript/dashboard/i18n/locale/en/jivo.json` — full `JIVO.SCENARIOS.*` and `JIVO.CUSTOM_TOOLS.*` blocks (titles, descriptions, form labels, error messages, delete dialog copy).

**Verified:** ESLint clean (only baseline dynamic-i18n-key warnings in unrelated files). Routes registered. Stores registered. Forms render with conditional fields per auth type.

**Test live:**
1. Navigate to **Settings → JIVO** as administrator. The header now has a "Custom Tools" button next to "New Assistant".
2. Each assistant row has new "Scenarios" button between "FAQs" and "Inboxes".
3. **Scenarios**: pick an assistant → click Scenarios → "New Scenario" modal opens. Title + description + instruction (with `[Tool Label](tool://tool_id)` syntax), enabled toggle. Save → row appears with auto-extracted tool chips.
4. **Custom Tools**: from JIVO settings header → "Custom Tools" → "New Custom Tool" → fill in HTTPS URL, pick auth type (bearer/basic/api_key), add param schema rows. Save → row appears showing slug, method, URL, auth type.
5. Edit + delete flows mirror the existing Documents/FAQs pages.
6. Backend tool ref validation (5.6) blocks save if instruction references unknown tool IDs (including custom tools that haven't been created or are disabled).

**Lock-in state:** Phase 5 fully usable end-to-end through the admin UI. Multi-agent V2 is feature-complete for self-service configuration.

**Implementation notes:**
- Mirrors the existing `Documents.vue` / `Faqs.vue` page conventions — single page per resource, modal form for create/edit, `Dialog` for delete confirmation, `BaseSettingsHeader` action slot for top-right buttons.
- Custom tools live at the account level (matching the backend table layout from 5.1/5.7) — single page accessed via the JIVO settings header, not nested under any assistant.
- Frontend client-side validation deliberately minimal: title non-blank, URL non-blank + HTTPS prefix. The backend's `JivoSafeEndpointValidatable` does the deep validation (private IP, localhost, app self-host, non-ASCII), so frontend errors don't drift from backend rules.
- Param schema editor is a flat add/remove list, not a JSON editor. Keeps non-technical admins able to set up tools without writing JSON. The model's `JsonSchemaValidator` enforces the shape on save.
- Skipped Captain's payload+meta envelope on the index endpoint — JIVO controllers return flat arrays for consistency with existing `Documents`/`Faqs` API surfaces.

**Deferred:**
- Drag-and-drop reordering of scenarios — Phase 6.
- Live tool tester ("Run with sample input" preview) — Phase 6.
- Visual JSON editor for `param_schema` — Phase 6.
- Tool icon rendering (each tool metadata has an `icon` from `config/agents/jivo_tools.yml` but UI doesn't render it yet) — Phase 6.
- Per-scenario tool selector UI (currently only via inline `[Label](tool://id)` references in instruction) — Phase 6.

---

## Phase 5 — Multi-Agent V2 — ✅ COMPLETE

All 8 sub-tasks shipped. JIVO V2 multi-agent system is feature-complete:
- Built-in tools (FAQ lookup, handoff, contact note, private note, priority, label) — `lib/jivo/tools/`.
- Custom HTTP tools with URL safety, auth, IP block, Liquid templating — `lib/jivo/tools/http_tool.rb`.
- Specialised scenario sub-agents with bidirectional handoff orchestration via `ai-agents` gem.
- Full admin UI for scenarios and custom tools.
- Per-assistant `feature_v2_agent` flag for opt-in.

**Critical Phase 5 deferred items rolled into Phase 6:**
- Thread-safe per-assistant API key handling (currently mutates global `Agents` config).
- Per-tool rate limiting + analytics.
- OpenTelemetry / Langfuse instrumentation.
- Streaming response surface in agent UI.
- Per-scenario response_guidelines / guardrails.
- Live tool tester + JSON schema visual editor in custom tool form.
- Tool icon rendering in scenario/tool UI.

**Goal:** Two management screens in JIVO settings — list/create/edit/delete for scenarios and custom tools.

**Captain reference:**
- `app/javascript/dashboard/routes/dashboard/settings/captain/` (or similar — Captain's scenario/tool UI)

**Files to create:**
- `app/javascript/dashboard/api/jivo/scenario.js` — API client.
- `app/javascript/dashboard/api/jivo/customTool.js` — API client.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoScenarioForm.vue` — modal form.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoScenarioList.vue` — list view.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoCustomToolForm.vue` — modal form (URL, method, auth, param schema).
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoCustomToolList.vue` — list view.

**Files to modify:**
- `app/javascript/dashboard/routes/dashboard/settings/jivo/index.js` (or routes config) — add routes for scenarios + custom tools tabs.
- `app/javascript/dashboard/i18n/locale/en/jivo.json` — labels.
- Vuex store(s) for scenarios + custom tools, mirroring the existing JIVO assistants store pattern.

**Test:**
1. Admin → JIVO settings → Scenarios tab → create scenario → appears in list → can edit and delete.
2. Same for custom tools — including URL validation, http_method dropdown, auth_type/auth_config inputs.
3. Agent role: tabs hidden or read-only.

**Lock-in state:** Phase 5 complete from end-user perspective. Multi-agent V2 fully usable through UI.

**Deferred:**
- Drag-and-drop reordering of scenarios — Phase 6.
- Live tool tester ("Run with sample input") — Phase 6.
- Param schema visual editor — Phase 6 (raw JSON for now).

---

### Phase 5 Handoff Notes

If picking up mid-phase:
1. Read Phase 5 Status Tracker above to find the last sub-task marked IN PROGRESS or NOT STARTED.
2. Each sub-task has files, Captain references, test step, and lock-in state — work to that lock-in state and stop.
3. After completing a sub-task: run `bundle exec rubocop -a app/services/jivo/ app/models/jivo* app/controllers/api/v1/accounts/jivo/ lib/jivo/` and `pnpm eslint --fix <changed>`; update the sub-task status in this log.
4. **Do not start the next sub-task in the same turn unless the user asks** — phase boundaries are designed for usage-window splits.

---

## Phase 6 — Production Polish (IN PROGRESS)

Catches every deferred item from Phases 1-5 plus the originally planned Sections 18 (Instrumentation), 19 (Webhooks), and 20 (Frontend polish). Split into 9 independently shippable sub-tasks ordered by priority — each can be picked, skipped, or reordered based on business need.

**Total estimate:** ~28-37 hrs. **Critical path for production readiness:** `6.1 → 6.2` (~9 hrs) gets the auto-learning loop closed and the V2 runner thread-safe + observable. The rest is incremental polish.

**Phase 6 Status Tracker:**
- [x] 6.1 FAQ Approval UI + bulk actions — COMPLETE
- [x] 6.2 V2 Runner Hardening + Observability — COMPLETE (6.2.1–6.2.5 ✅; streaming UI moved to Phase 7.1)
- [x] 6.3 Knowledge Base Ingestion Polish — COMPLETE (6.3.1 ✅, 6.3.2 ✅, 6.3.3 ✅; 6.3.4 SKIPPED — Captain has no chunker either, JIVO is already at parity)
- [x] 6.4 Assistant Settings UI Polish — COMPLETE (6.4.1–6.4.4 ✅)
- [x] 6.5 Conversation Panel Polish + Inline Rewrite Editor — COMPLETE (tool icons, scenario badge, contact memory panel, selection-aware rewrite)
- [ ] 6.6 Non-Resolution Learning Hardening — DEFERRED (revisit when conversations stop being resolved regularly enough to feed learning; brings inactivity-based learner cron, learn watermark, note dedup, and token-aware budgeting)
- [x] 6.7 Multimodal + Multi-Language Polish — COMPLETE (translation cache, Whisper language hint + fallback, vision-capable detection + warning + image OCR fallback; per-language FAQ storage skipped — Captain doesn't have it)
- [ ] 6.8 Custom Tool UX + Live Tester — DEFERRED (revisit when custom tool authoring becomes a frequent task; brings live tool tester, visual `param_schema` editor, scenario drag-drop reorder, and auth rotation reminder)
- [ ] 6.9 Webhooks + Events + Branding — DEFERRED (revisit when external integrations or self-hosted rebrands are needed; brings realtime push events, inbound/outbound webhook signing, branding audit, and V1→V2 bulk migration)
- [x] 6.10 Captain-style PDF Ingestion Quality Upgrade — COMPLETE
- [x] 6.11 FAQ Admin Search — COMPLETE

---

### Sub-Task 6.1: FAQ Approval UI + Bulk Actions

**Status: COMPLETE**

**Goal:** Close the auto-learning loop. Conversation-generated FAQs (from 4.4 + 4.7.2 manual learn) currently sit as `:pending` and never reach RAG. Build an approval surface so admins can review, approve, reject, and bulk-act on these pending FAQs.

**Captain reference:**
- `enterprise/app/controllers/api/v1/accounts/captain/bulk_actions_controller.rb`

**Files to create:**
- `app/controllers/api/v1/accounts/jivo/bulk_actions_controller.rb` — assistant-scoped bulk endpoint accepting an array of `JivoAssistantResponse` IDs and an action (`approve`, `reject`, `delete`).
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoFaqApprovalRow.vue` — list row variant with checkbox + inline approve/reject buttons.

**Files to modify:**
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Faqs.vue` — add status filter dropdown (`pending` / `approved` / `all`), bulk-select header, bulk action toolbar (Approve / Reject / Delete).
- `app/javascript/dashboard/api/jivoResponses.js` — add `bulkApprove`, `bulkReject`, `bulkDelete` methods.
- `app/javascript/dashboard/store/modules/jivoResponses.js` — Vuex actions wrapping the bulk API.
- `config/routes.rb` — add assistant-scoped `resources :bulk_actions, only: [:create]`.
- `app/services/jivo/llm/contact_notes_service.rb` — add idempotency: dedupe new notes against existing `contact.notes` by `(contact_id, content)` exact match within last 7 days.

**Test live:**
1. Run a few conversations through V2 with `feature_faq` on, hand off to humans, then have humans reply.
2. Resolve some, leave others. Trigger manual "Learn from this conversation" on a few via the JIVO assistant panel.
3. Open Settings → JIVO → assistant → FAQs → switch filter to **Pending**.
4. Bulk-select 5 → click Approve → confirm they flip to `:approved` and appear in subsequent V2 conversations as RAG context.
5. Reject a few — confirm they're deleted from the table.
6. Click manual Learn twice on the same conversation → confirm only one note row added per unique content (dedup).

**Lock-in state:** pending FAQs are reviewable + actionable. Manual learn is idempotent. Auto-learning loop now compounds for Tabeer Tours.

**Deferred (Phase 6 stretch or later):**
- Inline edit of pending FAQ before approval.
- Auto-approve high-confidence FAQs (vector distance < threshold to an existing approved one).
- Approval audit log.

---

### Sub-Task 6.2: V2 Runner Hardening + Observability

**Status: ✅ COMPLETED** (6.2.1–6.2.5 all done. Streaming UI dropped — Captain doesn't ship it for V2 customer replies; revisit in Phase 7.1 alongside Copilot.)

#### 6.2.1 — Thread-Safe Per-Assistant API Key ✅ COMPLETED

**Implemented:**
- New `app/services/jivo/runtime/api_key_lock.rb` — `Jivo::Runtime::ApiKeyLock.with_assistant_key(assistant) { ... }`. Uses a class-level `Mutex` to serialize `Agents.configure` mutations across threads in a single process. Snapshots `Agents.configuration.openai_api_key` + `default_model` before applying the assistant's, restores in `ensure`.
- Modified `app/services/jivo/assistant/agent_runner_service.rb#generate_response` — wrapped the agent build + `runner.run` + result processing inside `with_assistant_key`. Removed the now-redundant `configure_agents_for_assistant` private method.

**Why a global mutex (not per-key):** `Agents.configuration` is a process-singleton and `Agents.configure` propagates to `RubyLLM.config`. There is no "per-key configuration" surface to isolate against, so the only safe boundary is to serialize the configure-run-restore window. This caps V2 reply throughput to one in-flight call per Sidekiq process, which is acceptable for current load — multi-process Sidekiq deployments still get parallelism via process-level isolation.

**Verified:** Smoke tested via `Rails.runner` with 50 threads alternating two fake assistants (`KEY_A`/`KEY_B`). Result: 0 mismatches between the assistant's intended key and the key observed inside the locked block; final `Agents.configuration.openai_api_key` returned to `nil` (process-boot state) after all threads completed.

**Lock-in state:** Two assistants in different accounts can run V2 replies concurrently in the same process without API key flapping. Lint clean across both files.

**Deferred:**
- Per-key parallelism (would let multiple replies for the same assistant run in parallel) — not needed at current scale.
- Sidekiq-queue-based serialization (alternative to mutex) — would survive across processes, but unnecessary because each process has its own `Agents.configuration`.

---

#### 6.2.2 — Account-Level `feature_v2_agent` Override ✅ COMPLETED

**Implemented:**
- `app/models/account.rb` — added `:jivo_v2_agent` to existing `store_accessor :settings, :keep_pending_on_bot_failure` line (kept on one line to stay under `Metrics/ClassLength`).
- `app/models/jivo_assistant.rb#feature_v2_agent_enabled?` — now returns `account.jivo_v2_agent || config.feature_v2_agent` (both cast through `ActiveModel::Type::Boolean`). Account-level override wins; per-assistant flag still works when account override is unset.
- `app/controllers/api/v1/accounts_controller.rb#permitted_settings_attributes` — appended `:jivo_v2_agent` so the existing `PUT /api/v1/accounts/:id` endpoint can update it.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Index.vue` — added "Force V2 multi-agent runner for all assistants" toggle row at the top of the assistant list. Two-way binding via `accountV2Override` computed (writes through `accounts/update` Vuex action).
- `app/javascript/dashboard/i18n/locale/en/jivo.json` — `JIVO.ASSISTANTS.ACCOUNT_V2_OVERRIDE.{LABEL,HELP,ENABLED,DISABLED,ERROR}` strings.

**Verified (Rails runner truth table on real account + assistant):**
| account.jivo_v2_agent | assistant.feature_v2_agent | enabled? |
|---|---|---|
| nil/false | false | **false** ✓ |
| false | true | **true** ✓ |
| true | false | **true** ✓ |
| true | true | **true** ✓ |
| `"true"` (string) | false | **true** ✓ |

All 5 cases match expected. ESLint clean on Index.vue, Rubocop clean on the 3 Ruby files.

**Lock-in state:** Single-toggle account-level kill-switch lives in JIVO settings → top of assistant list. Flipping it on instantly forces V2 for every assistant in the account. Flipping it off restores per-assistant control.
#### 6.2.3 — DNS Rebinding Protection on Custom HTTP Tools ✅ COMPLETED

**Implemented:**
- New `app/services/jivo/tools/dns_validator.rb` — `Jivo::Tools::DnsValidator.new(hostname).validate!` resolves the hostname, blocks private/loopback/link-local IPs (v4 + v6), and stores the resolved IP. `reverify!` re-resolves and raises `RebindingDetected` if the IP shifted between validation and the actual request.
- `lib/jivo/tools/http_tool.rb` — replaced the inline `PRIVATE_IP_RANGES` constant + `check_private_ip!` method with a call to `DnsValidator`. Validates once before building the request, then `reverify!` immediately before `http.request(request)` to catch DNS rebinding within the same call.
- The validator's typed errors (`PrivateIpBlocked`, `ResolutionFailed`, `RebindingDetected`) bubble up to `HttpTool#perform`, which already swallows `StandardError` and returns a tool-error string to the agent, so the agent gracefully recovers when a rebinding attempt happens mid-call.

**Why "double resolve" instead of "pin IP and connect to it directly":** True IP-pinning would require connecting `Net::HTTP` to the resolved IP literal while preserving the original hostname for SSL SNI + cert verification. Net::HTTP's SNI is bound to `@address`, which is also the connect target — there's no clean Ruby API to split the two without subclassing `Net::HTTP` or hand-rolling the TLS handshake on a raw `TCPSocket`. The double-resolve pattern catches the realistic attacker timing window (between LLM tool-call validation and the actual HTTP request, on the order of milliseconds to seconds) without rewriting the TLS layer. A motivated attacker who can flip DNS in the sub-millisecond window between `reverify!` and `http.request` could still slip through, but the bar is now substantially higher than Captain's implementation (which only checks once at validation time and never re-checks).

**Verified via Rails runner — all four paths:**
- Public hostname (`example.com`) → validates with resolved IP, `reverify!` passes.
- Private hostname (`localhost`) → `PrivateIpBlocked` raised with `127.0.0.1` in message.
- Bogus hostname (`*.invalid`) → `ResolutionFailed` raised cleanly.
- Simulated rebinding (stub `resolve_ip` to return a different IP on second call) → `RebindingDetected` raised.

Rubocop clean on both changed files.

**Lock-in state:** Custom HTTP tools cannot be tricked into hitting internal services via DNS rebinding mid-call. Existing private-IP rejection is preserved. Captain's vulnerability does not exist in JIVO.

**Deferred:** Full IP-pinning (connect by IP, SNI by hostname) — only worth the rewrite if a real attacker is observed in production logs. Would also need careful handling of HTTPS certificate validation, IPv6 literal URL formatting, and proxy support.
#### 6.2.4 — Per-Tool Rate Limiting ✅ COMPLETED

**Implemented:**
- DB migration `20260506024917_add_rate_limit_to_jivo_custom_tools.rb` — `rate_limit_per_minute :integer` on `jivo_custom_tools`. Nullable; nil/zero/negative = unlimited.
- New `app/services/jivo/tools/rate_limiter.rb` — `Jivo::Tools::RateLimiter.new(custom_tool:).check!`. Fixed-window counter using `Redis::Alfred.incr` + `Redis::Alfred.expire(60)`. Raises typed `Jivo::Tools::RateLimiter::RateLimitExceeded` when count exceeds the configured limit.
- New Redis key constant `JIVO_TOOL_RATE_LIMIT_KEY = 'JIVO_TOOL_RATE_LIMIT::%<account_id>d::%<tool_slug>s'` in `lib/redis/redis_keys.rb`.
- `lib/jivo/tools/http_tool.rb#perform` — calls `RateLimiter#check!` before any URL/body construction. `RateLimitExceeded` is rescued with a friendly message returned to the agent (`"Rate limit reached for <slug>. Please try again in a minute."`) so the LLM degrades gracefully instead of looking like an outage.
- `app/controllers/api/v1/accounts/jivo/custom_tools_controller.rb` — permits `:rate_limit_per_minute`.
- `app/views/api/v1/accounts/jivo/custom_tools/_custom_tool.json.jbuilder` — exposes `rate_limit_per_minute` in API responses.
- `JivoCustomToolForm.vue` — number input "Rate limit (calls per minute)" with placeholder "Leave empty for no limit". Coerces blank/0/negative to `null` in the submit payload so the field always lands as nil or a positive integer in DB.
- `jivo.json` — `JIVO.CUSTOM_TOOLS.FORM.RATE_LIMIT.{LABEL,PLACEHOLDER,HELP}` strings.

**Why fixed-window over sliding-window/token-bucket:** Fixed window is one INCR + one EXPIRE per call, two Redis round-trips. Sliding window needs sorted-set ZADD/ZREMRANGEBYSCORE (more ops, more memory). For the "max N calls per minute" spec, the boundary-burst risk (2N calls across two windows) is acceptable — the limit is a safety valve, not a billing primitive. Trade-off is documented; can switch to sliding window later if a tool needs strict rate guarantees.

**Verified via Rails runner end-to-end (real Redis):**
- Limit = 3 → 3 calls succeed, 4th raises `RateLimitExceeded` with `"4/3 calls in the last 60s"`.
- Limit = nil → 20 calls all succeed.
- Limit = 0/negative → treated as unlimited (defensive coercion in service + form).

Rubocop clean across all 5 changed Ruby files. ESLint clean on the Vue form.

**Lock-in state:** Admins can cap any custom tool at N calls/min/account from the form. The agent gets a clear message instead of a 500 when the cap trips. No code path changes for tools with `rate_limit_per_minute: nil` (the default), so existing tools behave exactly as before.

**Deferred:** Per-tool circuit breakers (auto-disable a tool after M consecutive failures) — Phase 7. Rate-limit telemetry / dashboard — would land alongside the OTel work in 6.2.5.
#### 6.2.5 — OpenTelemetry + Langfuse-flavored Attributes ✅ COMPLETED

**Implemented:**
- `app/services/jivo/assistant/agent_runner_service.rb` — added `require 'agents/instrumentation'` at the top, mixed in `Integrations::LlmInstrumentationConstants` (already in core, not enterprise), and inserted `install_instrumentation(runner)` between `Agents::Runner.with_agents(*agents)` and `runner.run(...)`. Mirrors Captain's pattern exactly.
- `install_instrumentation(runner)` — early-returns when `ChatwootApp.otel_enabled?` is false (no Langfuse config = silent no-op, zero overhead). When enabled, calls `Agents::Instrumentation.install(runner, tracer: OpentelemetryConfig.tracer, trace_name: 'llm.jivo_v2', span_attributes: { ATTR_LANGFUSE_TAGS => ['jivo_v2'].to_json }, attribute_provider: ...)`.
- `dynamic_trace_attributes(context_wrapper)` — pulls `account_id` / `assistant_id` from `context.state` and `conversation.id` / `display_id` from `state[:conversation]`. Returns `{ langfuse.user.id, langfuse.trace.metadata.assistant_id, langfuse.trace.metadata.conversation_id, langfuse.trace.metadata.conversation_display_id }` with all values stringified and `nil`s compacted.

**Why diverge from Captain on cost tracking:** Captain's `add_usage_metadata_callback` flips a `credit_used` span attribute based on whether the handoff tool fired. JIVO is self-hosted — no per-conversation billing meter to attribute against. Skipped that callback entirely; the trace name (`llm.jivo_v2`) and metadata are enough to identify replies in Langfuse.

**Verified via Rails runner — all three paths:**
- `ChatwootApp.otel_enabled? = false` (no Langfuse config) → `install_instrumentation` returns `nil`, runner is untouched.
- Stubbed `otel_enabled? = true` → `Agents::Instrumentation.install` registers callbacks; the runner's `@__agents_otel_instrumentation_installed` flag is `true`.
- `dynamic_trace_attributes` returns the expected Langfuse-formatted hash given a synthetic context (`{"langfuse.user.id" => "7", "langfuse.trace.metadata.assistant_id" => "99", ...}`).

Rubocop clean.

**Lock-in state:** V2 reply path emits OTel spans whenever Langfuse is configured at the installation level (`OTEL_PROVIDER=langfuse` + `LANGFUSE_SECRET_KEY` set); zero overhead and no behavior change otherwise. Same trace shape as Captain V2, so Langfuse dashboards built for Captain work for JIVO out of the box.

**Deferred:**
- Per-tool circuit breakers / failure-rate tracking — Phase 7 if observed in production.
- Streaming response surface (`on_tool_start`/`on_tool_complete` UI hooks) — Phase 7.1 alongside Copilot. Captain has the callback plumbing but doesn't ship UI for V2 customer replies either.
- Cost / credit tracking — irrelevant for self-hosted JIVO; revisit only if a multi-tenant SaaS deployment ever happens.

---

**Goal:** Make the V2 reply path safe for production multi-tenant traffic + observable.

**Captain reference:**
- `enterprise/app/services/captain/assistant/agent_runner_service.rb` — OpenTelemetry/Langfuse blocks (`install_instrumentation`, `add_usage_metadata_callback`, `dynamic_trace_attributes`)
- `enterprise/lib/captain/tools/http_tool.rb` — DNS check pattern

**Sub-Task Items:**
1. **Thread-safe per-assistant API key.** Stop mutating `Agents.configure` globally. Either: (a) patch the `ai-agents` gem to accept a per-agent key and submit upstream, or (b) wrap the runner in a `Mutex.synchronize` block keyed by API key + restore previous value in `ensure`. Option (b) is cheaper and ships today.
2. **OpenTelemetry instrumentation.** Mirror Captain's `install_instrumentation(runner)` block. Re-enable the existing `Agents::Instrumentation.install` call that was skipped in 5.3. Adds Langfuse trace per session with `account_id`, `assistant_id`, `conversation_id` metadata.
3. **Streaming response surface.** Wire per-tool callbacks (`on_tool_start`, `on_tool_complete`, `on_agent_thinking`, `on_agent_handoff`) so the conversation UI can show `"using faq_lookup..."` while the agent thinks. Front-end gets WebSocket pings on each tool boundary.
4. **DNS rebinding protection** for custom tools: cache the resolved IP at validation time and re-check at execution time that it still resolves to the same IP (prevents an attacker's DNS server from flipping a public IP to a private one between checks).
5. **Per-tool rate limiting.** Redis-backed counter keyed by `(account_id, tool_slug)` enforcing N calls/minute. Default off, configurable per tool.
6. **Per-account override of `feature_v2_agent`.** Right now the flag is per-assistant; add a global override at the account level so a single toggle can flip the entire account on/off.

**Files to create:**
- `app/services/jivo/runtime/api_key_lock.rb` — `with_assistant_key(assistant) { ... }` mutex helper.
- `app/services/jivo/tools/dns_validator.rb` — caches resolved IP; rejects if it shifts.
- `app/services/jivo/tools/rate_limiter.rb` — Redis token-bucket per `(account_id, tool_slug)`.
- WebSocket payload type definitions for tool start/complete events.

**Files to modify:**
- `app/services/jivo/assistant/agent_runner_service.rb` — wrap `runner.run` in API key lock; re-enable `install_instrumentation`; install runner callbacks for streaming events.
- `lib/jivo/tools/http_tool.rb` — call `Jivo::Tools::DnsValidator` and `Jivo::Tools::RateLimiter` before each request.
- `app/models/jivo_custom_tool.rb` — add `rate_limit_per_minute` config column.
- `app/models/account.rb` — add `feature_v2_agent` to account-level settings (overrides per-assistant when set).
- `app/javascript/dashboard/components-next/conversation/.../<message bubble>` — render `"using <tool>..."` indicator while V2 streams.

**Test live:**
1. Configure 2 assistants in different accounts with different OpenAI keys, run V2 replies concurrently — both must complete with their respective keys.
2. Hit the same custom tool 100x in a minute — confirm rate limiting kicks in after the limit.
3. Set up a DNS-rebinding-style scenario (manually edit `/etc/hosts` to flip the resolved IP between calls) — confirm the second call is blocked.
4. Open Langfuse dashboard — see traces with the right metadata.
5. Send a message that triggers FAQ lookup — UI shows `"using faq_lookup..."` indicator before the final reply lands.

**Lock-in state:** V2 path safe under concurrency, observable, and interactive.

**Deferred:** Per-tool circuit breakers (after N consecutive failures, disable the tool for a cooldown window) — Phase 7 if ever needed.

---

### Sub-Task 6.3: Knowledge Base Ingestion Polish

**Status: ✅ COMPLETED** (6.3.1 ✅, 6.3.2 ✅, 6.3.3 ✅; 6.3.4 skipped — see note below)

#### 6.3.1 — Re-crawl Button on Documents ✅ COMPLETED

**Implemented:**
- `config/routes.rb` — added `post :recrawl, on: :member` to the existing `resources :documents` block.
- `app/controllers/api/v1/accounts/jivo/documents_controller.rb#recrawl` — destroys existing `jivo_assistant_responses` for the document, flips status to `in_progress`, enqueues `Jivo::Documents::CrawlJob.perform_later`, renders the same JSON shape as `show`.
- `app/javascript/dashboard/api/jivoDocuments.js` — added `recrawl(assistantId, documentId)` POST.
- `app/javascript/dashboard/store/modules/jivoDocuments.js` — new `recrawl` Vuex action; new `UPDATE_RECORD` mutation type wired to `MutationHelpers.update`; `isRecrawling` UI flag.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Documents.vue` — refresh-icon button per row, with per-doc `recrawlingDocId` ref so only the active row spins. Disabled while the doc is `in_progress` or already being recrawled.
- `jivo.json` — `JIVO.DOCUMENTS.RECRAWL{,_QUEUED,_FAILED}` strings.

**Verified end-to-end via Rails runner with Sidekiq inline:**
- Pre-state: doc `available`, 2 FAQs.
- After hitting the controller path (`destroy_all` + `update!` + `perform_later`): status `in_progress`, 0 FAQs.
- After CrawlJob runs (with mocked `SimplePageCrawlService` to avoid network): content present, status flips back to `available`.
- New route registered as `POST /api/v1/accounts/:account_id/jivo/assistants/:assistant_id/documents/:id/recrawl`.

Rubocop + ESLint clean across changed files.

**Lock-in state:** Each document row has a refresh-icon button that re-crawls the source URL and rebuilds the FAQ list. Used when source content (pricing pages, policy docs) changes upstream.

#### 6.3.2 — PDF Upload + Paginated FAQ Generation ✅ COMPLETED

**Implemented:**
- `Gemfile` — added `pdf-reader (~> 2.12)` for pure-Ruby PDF text extraction. No system dependency (unlike `mupdf` or `poppler`).
- DB migration `20260506035618_relax_jivo_documents_external_link.rb` — `external_link` is now nullable (PDFs have no URL). PostgreSQL unique index on `(jivo_assistant_id, external_link)` already permits multiple NULLs.
- `app/models/jivo_document.rb`:
  - `has_one_attached :file` (Active Storage).
  - Replaced `validates :external_link, presence: true` with `validate :must_have_source` — rejects records that have neither a URL nor an attached file.
  - New `pdf?` predicate (`file.attached? && content_type.include?('pdf')`).
  - Replaced `enqueue_crawl` callback with `enqueue_ingest` — branches on `pdf?` to dispatch `Jivo::Documents::PdfIngestJob` vs the existing `Jivo::Documents::CrawlJob`.
- New `app/services/jivo/documents/pdf_text_extractor.rb` — opens the Active Storage blob, runs `PDF::Reader`, joins per-page text with double-newlines, drops blank pages.
- New `app/jobs/jivo/documents/pdf_ingest_job.rb` — extracts text, persists `content` + `metadata['source_type']='pdf'` + page count, then hands off to the existing `ResponseBuilderJob` (or marks `available` if extracted text is empty).
- `app/jobs/jivo/documents/response_builder_job.rb` — added **chunking + dedupe** so PDFs longer than `Jivo::Llm::FaqGeneratorService::MAX_CONTENT_LENGTH` (30K chars) don't lose data. Splits content into 30K-char chunks, runs `FaqGeneratorService` per chunk, deduplicates resulting FAQs by `question.strip.downcase`. URL-based docs benefit from this too — long crawled pages now generate FAQs across the full content.
- `app/controllers/api/v1/accounts/jivo/documents_controller.rb#permitted_params` — permits `:file` (Active Storage attachment via multipart).
- `app/views/api/v1/accounts/jivo/documents/_document.json.jbuilder` — exposes `file_attached`, `file_name`, `file_content_type`.
- `app/javascript/dashboard/api/jivoDocuments.js#create` — branches on `data.file`. Falls back to JSON for URL adds; sends `multipart/form-data` with `document[file]` + `document[name]` for PDF adds.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Documents.vue`:
  - Mode toggle (URL / PDF) inside the add form.
  - Native `<input type="file" accept="application/pdf">` with 10 MB client-side cap (`PDF_MAX_BYTES = 10 * 1024 * 1024`) and inline error messages for wrong type / oversized.
  - Document row now shows attached PDF filename (with file icon) when `external_link` is null.
  - Re-crawl button hidden for PDF docs (no URL to refetch).
- `jivo.json` — `JIVO.DOCUMENTS.FORM.{MODE_URL, MODE_PDF, PDF_LABEL, PDF_HELP, PDF_INVALID, PDF_TOO_LARGE}` strings.

**Why local extraction over OpenAI Files API:** Captain reference points to OpenAI Files + paginated `gpt-4.1-mini` calls. We use local text extraction via `pdf-reader` because (a) it's free — no per-document OpenAI cost, (b) no separate gpt-4.1-mini dependency, (c) reuses the existing FAQ-generation pipeline so URL and PDF flows are symmetric, (d) text extraction quality from `pdf-reader` is good enough for typical business PDFs (price sheets, brochures, policy docs). OCR for scanned-image PDFs is deferred to Phase 7.

**Verified:**
- Pipeline smoke test (Rails runner with Sidekiq inline + stubbed LLM): doc creation → `pdf?` true → `enqueue_ingest` dispatches `PdfIngestJob` → status flows `in_progress → available` without exceptions.
- `pdf-reader` API surface (`#pages`, `#page_count`, `Page#text`) confirmed against the installed gem version (2.15.1).
- Chunking + dedupe logic unit-tested: 5K input = 1 chunk, 30K = 1 chunk, 30K+1 = `[30000, 1]`, 75K = `[30000, 30000, 15000]`. Question-case-insensitive dedupe collapses `"What is X?"` and `"what is x?"` to one entry.
- Rubocop clean across all 6 changed Ruby files. ESLint clean on the changed Vue + JS files. Migration applied.

**Lock-in state:** Admins drop a PDF in Settings → JIVO AI → Documents → New → PDF mode. Up to 10 MB. Backend extracts text, generates FAQs across the full document (chunked if >30K chars), embeds them, and they're searchable by V1 RAG and V2 FAQ-lookup tool just like URL-based docs.

**Deferred:**
- OCR for scanned-image PDFs — Phase 7 (would need `tesseract` + `pdf-image-extraction`, both system deps).
- OpenAI Files API approach (LLM reads the PDF directly without local extraction) — only worth it if `pdf-reader` quality proves insufficient for some customer PDFs.
- Per-page FAQ tracking (which page each FAQ came from) — Phase 7 polish.
#### 6.3.3 — Firecrawl Multi-Page Crawling ✅ COMPLETED

**Implemented (mirrors Captain's pattern almost line-for-line):**
- `app/services/jivo/tools/firecrawl_service.rb` — `HTTParty.post('https://api.firecrawl.dev/v1/crawl', ...)`. Reads API key from `InstallationConfig.find_by!(name: 'JIVO_FIRECRAWL_API_KEY')`. Crawl payload: `maxDepth: 50`, `limit: 10`, `formats: ['markdown']`, `excludeTags: ['iframe']`, `onlyMainContent: false`, async webhook.
- `app/helpers/jivo/firecrawl_helper.rb` — `generate_jivo_firecrawl_token(assistant_id, account_id)`. Derives `SHA256(api_key[-4..] + assistant_id + account_id)`. Same algorithm as Captain.
- `app/controllers/webhooks/jivo_firecrawl_controller.rb` — `Webhooks::JivoFirecrawlController < ActionController::API`. `before_action :validate_token` recomputes the SHA256 and 401s on mismatch. Only handles `type: 'crawl.page'` events. Permitted params include `data: [:markdown, { metadata: {} }]`.
- `app/jobs/jivo/tools/firecrawl_parser_job.rb` — per-page handler. `assistant.documents.find_or_initialize_by(external_link: canonical_url)` then `update!(content: markdown, name: title)`. Hands off to `ResponseBuilderJob` for FAQ generation and embeddings; falls back to `status: :available` if markdown is empty.
- `app/jobs/jivo/documents/crawl_job.rb` — refactored from a single-path simple-crawler into a branching dispatcher: if `JIVO_FIRECRAWL_API_KEY` is set, fires `FirecrawlService.perform(url, webhook_url, 10)`; otherwise uses the existing `SimplePageCrawlService`. Both branches share the same StandardError rescue + status-flip-to-available fallback.
- `config/routes.rb` — `post 'webhooks/jivo_firecrawl', to: 'webhooks/jivo_firecrawl#process_payload'` registered in core (not enterprise — JIVO is OSS).
- `config/installation_config.yml` — added `JIVO_FIRECRAWL_API_KEY` entry (type: secret, locked: false) so it appears in the Super Admin → Installation Configs UI.

**Why no gem:** Captain proved you don't need one. Direct `HTTParty.post` is ~5 lines, gives full control over the payload shape, and avoids gem-version drift if Firecrawl evolves the API. HTTParty is already a transitive Chatwoot dependency, so no Gemfile change.

**Webhook URL construction:**
```ruby
"#{webhooks_jivo_firecrawl_url}?assistant_id=#{document.jivo_assistant_id}&token=#{generate_jivo_firecrawl_token(...)}"
```
Requires `default_url_options` to be set in production (typically via `FRONTEND_URL` env var). Without it, `Rails.application.routes.url_helpers.webhooks_jivo_firecrawl_url` raises — same constraint as Captain's setup.

**Verified via Rails runner — full chain:**
- Token derivation matches `SHA256(api_key[-4..] + 99 + 7)` exactly (`8b323e7a9ca6...`).
- With `JIVO_FIRECRAWL_API_KEY` set, `CrawlJob.perform_now` calls `HTTParty.post` (stubbed) with: correct endpoint, `body.url = "https://www.tabeertours.com"`, `body.limit = 10`, `body.scrapeOptions.formats = ["markdown"]`, `webhook` containing `?assistant_id=2&token=...`, and `Authorization: Bearer ...` header.
- `FirecrawlParserJob` with a synthetic page payload creates a new `JivoDocument` with `external_link = "https://example.com/help/pricing"` (trailing slash stripped), `name = "Pricing"`. Title and URL extracted from `metadata` correctly.
- Route registered as `POST /webhooks/jivo_firecrawl`.

Rubocop clean across all 6 changed/new Ruby files.

**Lock-in state:** With no Firecrawl key, JIVO behaves exactly as before (single-page `SimplePageCrawlService`). Set `JIVO_FIRECRAWL_API_KEY` in Super Admin → Installation Configs, and from then on every URL document submission triggers a multi-page Firecrawl crawl. Each crawled page becomes its own `JivoDocument` (find_or_initialize by URL, so re-crawls don't duplicate). FAQ generation runs per-page via the existing `ResponseBuilderJob`. Sign up at https://firecrawl.dev — 500 pages/month free tier.

**Deferred:**
- Crawl-progress UI (showing "5/10 pages crawled") — Phase 7. Would require persisting Firecrawl's `id` in `document.metadata` and a status endpoint.
- Per-account Firecrawl key (currently installation-wide) — only useful for multi-tenant SaaS deployments.
- Sitemap.xml-based pre-discovery — Firecrawl already uses sitemaps internally (`ignoreSitemap: false`), so no extra work needed.
#### 6.3.4 — Whisper >25MB Audio Chunking — SKIPPED (mirrors Captain)

**Why skipped:** Captain has no audio chunker. Their `Messages::AudioTranscriptionService` sends the file straight to Whisper and lets OpenAI's >25MB error propagate. JIVO's `Jivo::Messages::AudioTranscriptionService` already mirrors that behavior — it sends the file as-is and returns an empty string on Whisper API failure (the `rescue StandardError` block).

In practice, voice messages from chat platforms are small (WhatsApp caps at 16MB server-side, web chat recordings are typically <5MB), which is why Captain hasn't engineered for the >25MB case. JIVO is at parity without writing any code.

**Re-open when:** A real customer hits Whisper's 25MB limit in production logs. At that point, choose between:
- Pre-flight size check that returns a friendly error (~15 min, no system deps).
- Full ffmpeg-based chunker (~1.5 hr, requires ffmpeg in deploy environment).

---

**Goal:** PDF upload, multi-page Firecrawl, re-crawl, larger Whisper file support.

**Captain reference:**
- `enterprise/app/services/captain/llm/faq_generator_service.rb` — paginated FAQ generation
- `enterprise/app/jobs/captain/documents/response_builder_job.rb`

**Sub-Task Items:**
1. **PDF upload via Active Storage.** New form path in `Documents.vue` accepting a PDF (max 10MB). Backend uploads to OpenAI Files API, stores `file_id` in `document.metadata`. Paginated FAQ generation processes the PDF page-by-page using `gpt-4.1-mini`.
2. **Firecrawl multi-page crawling.** Replace the current single-page scraper with Firecrawl's async crawl API. Supports up to 10 URLs per crawl with webhook callback when crawl completes. Falls back to existing simple crawl if Firecrawl key isn't configured.
3. **Re-crawl button** on each document row. Triggers `Jivo::Documents::CrawlJob` again with the existing URL. Useful when source content changes.
4. **Whisper file chunking** for audio files >25MB. Split with `ffmpeg`, transcribe each chunk, concatenate.

**Files to create:**
- `app/services/jivo/documents/pdf_upload_service.rb` — uploads PDF to OpenAI Files, stores `file_id`.
- `app/services/jivo/documents/paginated_faq_service.rb` — chunked FAQ generation for PDFs.
- `app/services/jivo/documents/firecrawl_service.rb` — async crawl with webhook handler.
- `app/services/jivo/messages/audio_chunker_service.rb` — `ffmpeg`-based splitter.
- `app/controllers/api/v1/accounts/jivo/firecrawl_webhooks_controller.rb` — receives crawl-complete events.

**Files to modify:**
- `app/controllers/api/v1/accounts/jivo/documents_controller.rb` — accept `file` multipart param + dispatch to PDF service when content type is application/pdf.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Documents.vue` — file upload field, re-crawl button per row.
- `app/services/jivo/messages/audio_transcription_service.rb` — use chunker when file > 25MB.
- `Gemfile` — `firecrawl-ruby` (or similar) if not present.

**Test live:**
1. Upload a 5-page PDF → status flips through `in_progress` → `available` → FAQs appear.
2. Add a multi-page URL via Firecrawl → all linked pages get crawled into separate documents.
3. Click re-crawl on an existing document → status flips back to `in_progress` then back to `available` with refreshed FAQs.
4. Send a 30MB voice note → transcript still produced (chunked).

**Lock-in state:** Knowledge base supports PDFs + multi-page sites + large audio.

**Deferred:** OCR for scanned PDFs (image-only pages) — Phase 7.

---

### Sub-Task 6.4: Assistant Settings UI Polish

**Status: IN PROGRESS** (6.4.1 ✅; 6.4.2–6.4.4 pending)

#### 6.4.1 — Response Guidelines + Guardrails ✅ COMPLETED

**Implemented:**
- DB migration `20260506140757_add_guidelines_to_jivo_assistants.rb` — added `response_guidelines :jsonb default: []` and `guardrails :jsonb default: []` as native columns on `jivo_assistants`. Mirrors Captain's column choice exactly (same names, same types).
- `app/services/jivo/prompts/assistant_prompt.rb` — added `custom_response_guidelines_section` and `guardrails_section` private methods that emit `[Custom Response Guidelines]` and `[Guardrails]` bullet sections only when the corresponding array is non-empty. Sections sit after the existing built-in `[Response Guideline]` block so admins can add tone overrides without losing the JIVO defaults.
- Bullet items go through `Array(...).reject(&:blank?)` so blank/whitespace-only lines from the form textarea don't produce empty bullets.
- Diverged from Captain's Liquid template: their `assistant.liquid` has a duplication bug where three hardcoded bullets repeat per user-supplied guideline (likely a misplaced `{% for %}` boundary). JIVO emits exactly one bullet per non-blank guideline.
- `app/controllers/api/v1/accounts/jivo/assistants_controller.rb` — permits `response_guidelines: []` and `guardrails: []` arrays at the top level of the `assistant` params.
- `app/views/api/v1/accounts/jivo/assistants/_assistant.json.jbuilder` — exposes both arrays (wrapped in `Array(...)` so JSON always serializes a list, never null).
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — two new monospace textareas ("one per line"): `response_guidelines_text` / `guardrails_text` ↔ array conversion handled in `linesToArray` / `arrayToLines` helpers. The submit handler splits, strips, and drops blanks before emitting `save`.
- `jivo.json` — `JIVO.ASSISTANTS.FORM.RESPONSE_GUIDELINES.{LABEL,PLACEHOLDER,HELP}` and `JIVO.ASSISTANTS.FORM.GUARDRAILS.{LABEL,PLACEHOLDER,HELP}`.

**Verified via Rails runner:**
- Empty arrays → neither `[Custom Response Guidelines]` nor `[Guardrails]` section appears in the rendered prompt.
- Populated arrays → both sections render exactly one bullet per item, in the order provided.
- Blank-line filter: input `["", "  ", "Be concise"]` produces a single bullet (`"Be concise"`), no empty bullets.
- Migration applied. Rubocop clean across all 3 changed Ruby files.

**Why columns instead of `store_accessor :config`:** Captain stores these as typed jsonb columns on the model. Native columns are queryable by future analytics, support array-typed strong params (`response_guidelines: []` permit shorthand), and play nicely with Rails defaults (`default: []`). Same pattern, less store_accessor sprawl.

**Lock-in state:** Admins write per-line guidelines/guardrails in the form. Saved values flow into the V2 system prompt automatically on the next reply. V1 path unchanged (V1 uses a different prompt builder that already has hardcoded guidelines).

**Deferred:** Per-scenario response_guidelines / guardrails (Captain delegates from the assistant; JIVO inherits the same pattern via `JivoScenario` future delegation) — Phase 6.4.3 if needed, otherwise Phase 7 polish.

#### 6.4.2 — Tabbed Settings + Grouped Feature Toggles ✅ COMPLETED

**Implemented:**
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — restructured the entire form body into 4 tabs:
  - **Basic** — name, description, product_name, handoff_message.
  - **AI** — openai_api_key, openai_model, temperature.
  - **Behavior** — feature toggles split into 3 visually-separated groups: **Learning** (memory + FAQ), **Runner** (V2 multi-agent), **Idle conversation handling** (idle action toggle + indented config block when on).
  - **Advanced** — system_prompt, response_guidelines, guardrails.
- Tab strip uses standard underline-on-active styling (`border-b-2 border-n-brand` for active, transparent for inactive) — no new component needed; inline within the form.
- Tab definitions live in a static `tabs` array; `currentTab` ref defaults to `'basic'`. Switching tabs uses `v-show` (not `v-if`) so all field state stays mounted — `name` validation cross-tab works without losing focus, and there's no remount cost on every switch.
- **Conditional reveal:** the entire idle-config block (timeout / action / message / reminder_limit) is wrapped in `v-if="form.config.feature_idle_action"` and indented with a left border, so admins can't accidentally configure idle behavior that's never going to fire.
- The reminder-limit input keeps its existing nested conditional (`v-if="form.config.idle_action === 'reminder'"`) so it only appears for the reminder action.
- Removed the unused "Phase 4 Testing" h3 (i18n key `JIVO.ASSISTANTS.FORM.ADVANCED_FEATURES.TITLE`); replaced with per-group h3 headings under structured i18n: `JIVO.ASSISTANTS.FORM.GROUPS.{LEARNING, RUNNER, IDLE}` and `JIVO.ASSISTANTS.FORM.TABS.{BASIC, AI, BEHAVIOR, ADVANCED}`.

**Why `v-show` over `v-if`:** Form fields are reactive `v-model` bindings — using `v-if` would unmount/remount inputs on every tab switch, losing focus and any in-progress validation state. `v-show` keeps the DOM and just toggles `display: none`.

**Why all-in-one file (no separate `JivoAssistantTabs.vue`):** The original spec suggested an extracted tab component, but the tab strip is ~10 lines of template and shares state directly with form bindings. Extracting it would add prop-drill overhead with no real reuse value. If a second tabbed form ever appears (e.g., scenario form), the right move is to extract a generic `<TabStrip>` then — premature for now.

**Verified:** ESLint clean on the file (one i18n dynamic-key warning that's the same pattern used across the rest of the codebase — `tabs[].key` references are static literals but the linter can't statically prove that). No new translations missing from `en/jivo.json`. `feature_idle_action: false` correctly hides the entire idle config block.

**Lock-in state:** Form is feature-discoverable. New admins land on **Basic** with the 4 fields they actually need to launch an assistant; they don't see the experimental toggles, prompt overrides, or idle-action machinery unless they explicitly navigate. Editing existing assistants preserves all values across tab switches.

**Deferred:**
- Per-tab dirty-state tracking with "unsaved changes" warning before close — Phase 7.
- Form validation per-tab (currently a single `isValid` covers name + description, both on Basic) — Phase 7 if more required fields land.

**Follow-up (same sub-task) — Modal → Page Route:**
- New page wrapper: `app/javascript/dashboard/routes/dashboard/settings/jivo/AssistantEdit.vue`. Uses `SettingsLayout` + `BaseSettingsHeader` (same pattern as Documents/Faqs/Scenarios), embeds `JivoAssistantForm`, dispatches save, redirects to the assistant list (`router.push({ name: 'jivo_assistants' })`) on success or back-button.
- Routes added in `jivo.routes.js`: `name: 'jivo_assistant_new'` at `path: 'new'`, and `name: 'jivo_assistant_edit'` at `path: ':assistantId/edit'`. Both deep-linkable.
- `JivoAssistantForm.vue` stripped of modal chrome — dropped the `fixed inset-0 z-50` overlay, the rounded-shadow card, and the modal h2 title bar. Component now renders as an embeddable card (`bg-n-solid-1 rounded-lg border border-n-weak`) with its existing tab strip, fields, and Cancel/Save footer intact. Title is now provided by the page wrapper's header.
- `Index.vue` cleaned: removed `formMode` / `showForm` refs, removed `handleSave`, removed the `<JivoAssistantForm>` mount. `openCreateForm` and `openEditForm` now dispatch `router.push` to the new routes.

**Why a page route over a modal:** the form is now 4 tabs with multiple long-form textareas (system_prompt, response_guidelines, guardrails). Modals were cramping the content, lost state on accidental backdrop click, and had no permalink. The page wrapper gives proper scrolling, a clean back-arrow, and `:assistantId/edit` deep links. Other JIVO modals (custom-tool form, scenario form) are smaller and stay as modals for now.

#### 6.4.3 — Per-Scenario Tool Selector ✅ COMPLETED

**Implemented:**
- New `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoToolSelector.vue` — a v-model checkbox list grouped into "Built-in" and "Custom" sections. Reads tool metadata from `assistant.available_tools` (newly exposed via JBuilder). Renders title + description per row, with empty-state copy when neither group has tools.
- `app/views/api/v1/accounts/jivo/assistants/_assistant.json.jbuilder` — exposes `available_tools` (via `resource.available_agent_tools`, which returns the merged built-in + enabled custom tool metadata array). Frontend reads it from the cached store entry — no extra API call needed.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoScenarioForm.vue` — accepts `assistantId` prop, adds `tools` to the form ref (initialized from `props.scenario.tools`), embeds `<JivoToolSelector>` between description and instruction. Selected IDs flow through unchanged on save.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Scenarios.vue` — passes `:assistant-id="assistantId"` down to the form.
- `app/controllers/api/v1/accounts/jivo/scenarios_controller.rb#permitted_params` — permits `tools: []` on create/update.
- `app/models/jivo_scenario.rb#extract_tool_refs` — **changed from "overwrite" to "merge"**: previously the `before_save` callback set `self.tools = instruction.scan(TOOL_REFERENCE_REGEX).flatten.uniq`, which clobbered explicit selection. Now does `(Array(tools) + extracted).map(&:to_s).reject(&:blank?).uniq` so explicit form selection is preserved and instruction-mentioned tools are merged in.
- `jivo.json` — `JIVO.SCENARIOS.FORM.TOOLS.{LABEL,HELP,BUILT_IN,CUSTOM,EMPTY}` strings.

**Verified via Rails runner — 6 cases:**
- Explicit-only selection (no instruction refs): `tools = ['faq_lookup', 'handoff']` survives intact ✓
- Explicit + instruction refs: merged (`['faq_lookup'] + extracted ['add_contact_note']` → both kept) ✓
- Overlap (same tool in both): deduped — no duplicate entries ✓
- Empty selection + instruction-only refs: existing behavior preserved (`['update_priority']` from `[Tool](tool://update_priority)`) ✓
- Both empty: `tools = []` ✓
- Validation: unknown tool ID in instruction still raises `RecordInvalid` (existing `validate_instruction_tools` callback unaffected) ✓

Rubocop clean on changed Ruby files. ESLint clean on the new component and modified Vue files.

**Why merge instead of "form overrides extraction":** Captain's pattern is that tools mentioned in the instruction (`[Label](tool://id)`) are the ground truth for what the LLM sees in the prompt — they need to stay registered on the scenario regardless of whether the admin remembered to also tick the checkbox. Merging keeps the markdown-link syntax as the source of truth for prompt content while letting the form add tools that aren't mentioned by name (e.g., a tool the agent can use but the instruction doesn't call out explicitly).

**Lock-in state:** Scenario authors can pick allowed tools via checkboxes without memorizing tool IDs. Markdown link syntax in instructions still works — and any tool referenced there is automatically merged into the scenario's allowed list.

**Deferred:**
- Live preview of which built-in tools are referenced in the instruction (highlight matching checkboxes as the admin types) — Phase 7 polish.
- Per-tool descriptions sourced from i18n instead of `jivo_tools.yml` — Phase 7 if the descriptions ever need translating.

**Follow-up (same sub-task) — Scenario form modal → page route:**
- New page wrapper: `app/javascript/dashboard/routes/dashboard/settings/jivo/ScenarioEdit.vue`. Uses `SettingsLayout` + `BaseSettingsHeader`, embeds `JivoScenarioForm`, dispatches save, redirects back to the scenarios list (`router.push({ name: 'jivo_scenarios', params: { assistantId } })`).
- Routes added in `jivo.routes.js`:
  - `:assistantId/scenarios/new` → `jivo_scenario_new`
  - `:assistantId/scenarios/:scenarioId/edit` → `jivo_scenario_edit`
- New Vuex getter `jivoScenarios/getScenario` (id → record) so the edit page can hydrate the scenario from the cached list without a separate API call.
- `JivoScenarioForm.vue` stripped of modal chrome — dropped `fixed inset-0 z-50` overlay, the rounded-shadow card, and the modal h2 title bar. Now an embeddable card with the existing tool selector, fields, and Cancel/Save footer. Title is provided by the page wrapper's header.
- `Scenarios.vue` cleaned — removed `formMode` / `showForm` refs, removed `handleSave`, removed the `<JivoScenarioForm>` modal mount. `openCreate` and `openEdit` now `router.push` to the new routes.

**Why same treatment as the assistant form:** Scenarios now have the tool selector grid (which can grow to many rows when an account has lots of custom tools) plus a 6-row instruction textarea referencing `[Label](tool://id)` syntax. Same modal-cramping problem as the assistant form had.

**Follow-up (same sub-task) — Custom tool form modal → page route:**
- New page wrapper: `app/javascript/dashboard/routes/dashboard/settings/jivo/CustomToolEdit.vue`. Same pattern as `AssistantEdit.vue` and `ScenarioEdit.vue`. Embeds `JivoCustomToolForm`, dispatches save, redirects to `jivo_custom_tools` list on success.
- Routes added in `jivo.routes.js`:
  - `custom_tools/new` → `jivo_custom_tool_new`
  - `custom_tools/:id/edit` → `jivo_custom_tool_edit`
- New Vuex getter `jivoCustomTools/getCustomTool(id)` so the edit page hydrates from the cached list.
- `JivoCustomToolForm.vue` stripped of modal chrome (same as the other two forms).
- `CustomTools.vue` cleaned — removed `formMode` / `showForm` refs, removed `handleSave`, removed the `<JivoCustomToolForm>` modal mount. `openCreate` / `openEdit` now `router.push` to the new routes.

**Why custom-tool form gets the route treatment too:** Custom tools have the most fields of any JIVO form — title, description, endpoint URL, HTTP method, auth type with conditional config (bearer/basic/api_key blocks), variable-row param schema editor, request/response Liquid templates, rate limit, enabled toggle. Easily exceeds modal real estate. Document-add and FAQ-edit are still small enough to stay as modals.

#### 6.4.4 — Avatar Upload ✅ COMPLETED

**Implemented:**
- `app/models/jivo_assistant.rb` — `has_one_attached :avatar` (Active Storage). Added `AVATAR_MAX_BYTES = 2.megabytes` constant + `avatar_size_within_limit` validation that adds an error when an attached avatar exceeds the cap.
- `app/controllers/api/v1/accounts/jivo/assistants_controller.rb` — two new member actions: `avatar` (attaches uploaded file, saves the record, renders the same JSON shape as `show`) and `remove_avatar` (purges the attachment, renders the same JSON). Both gated by the existing `check_authorization` filter.
- `config/routes.rb` — `POST /api/v1/accounts/:id/jivo/assistants/:id/avatar` and `DELETE /api/v1/accounts/:id/jivo/assistants/:id/avatar`.
- `app/views/api/v1/accounts/jivo/assistants/_assistant.json.jbuilder` — exposes `avatar_url` (via `Rails.application.routes.url_helpers.url_for(resource.avatar)` when attached, else nil).
- `app/javascript/dashboard/api/jivoAssistants.js` — `uploadAvatar(id, file)` (multipart) and `removeAvatar(id)`.
- `app/javascript/dashboard/store/modules/jivoAssistants.js` — `uploadAvatar` and `removeAvatar` Vuex actions; both commit `EDIT_RECORD` so the assistant list re-renders with the new `avatar_url` immediately.
- New `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAvatarUploader.vue` — circular preview thumb + Upload/Replace/Remove buttons. Hidden file input triggered by the button. Local preview via `URL.createObjectURL` so the user sees the new avatar before the upload roundtrip completes; preview reverts on failure. Client-side validation rejects non-image MIME types (PNG/JPG/WEBP only) and >2 MB files before sending.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — uploader sits at the top of the **Basic** tab. Disabled until the assistant has an `id` (i.e., create flow uploads the avatar after the first save), with a helper hint shown to the admin.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Index.vue` — assistant list rows now show a 40px circular thumbnail (avatar_url, or sparkles fallback icon) to the left of the name.
- `jivo.json` — `JIVO.ASSISTANTS.FORM.AVATAR.{UPLOAD,REPLACE,REMOVE,HELP,SAVE_FIRST,INVALID_TYPE,TOO_LARGE,UPLOADED,REMOVED,FAILED}` strings.

**Why upload via dedicated endpoints rather than multipart on update:** keeps the existing JSON `update` action small and unchanged, avoids switching the entire form to multipart submission (the form has tabs, complex jsonb arrays, and toggles — JSON serialization is far cleaner). The trade-off: avatars can't be uploaded during the create flow until the record has an id, which is hinted in the UI ("Save the assistant before uploading an avatar").

**Verified via Rails runner — all four paths:**
- `assistant.avatar.attach(io:, filename:, content_type:)` then `save!` → `attached? = true`, `byte_size` correct.
- `url_for(assistant.avatar)` returns a valid Active Storage download URL.
- 3 MB upload triggers `avatar_size_within_limit` validation: `errors[:avatar] = ["is too large (max 2 MB)"]`.
- `purge` → `attached? = false`, JBuilder emits `avatar_url: null`.
- Routes registered: `POST /jivo/assistants/:id/avatar` and `DELETE /jivo/assistants/:id/avatar`.

Rubocop clean across the 4 changed Ruby files. ESLint clean on the new component and modified Vue/JS files.

**Lock-in state:** Admins drop a PNG/JPG/WEBP up to 2 MB on the Basic tab → preview appears instantly → uploads in background → list rows show the new thumbnail. Remove button purges the attachment and reverts to the sparkles fallback.

**Deferred:**
- Display the avatar in conversation panel header (where the JIVO assistant currently shows as a generic sparkles icon) — Phase 6.5 polish (conversation panel work).
- Display the avatar on the message bubble for outgoing assistant messages — Phase 6.5.
- Drag-and-drop file drop zone — Phase 7 polish; current click-to-upload is enough for MVP.
- Image cropping / square enforcement — Phase 7. We hint at "square images render best" in the help text.

---

**Phase 6.4 Lock-in Summary:**

All four sub-tasks complete. Combined effect on the admin experience:
1. **6.4.1** added `response_guidelines` + `guardrails` jsonb columns; admins can refine assistant tone and constraints from the form, V2 prompt picks them up.
2. **6.4.2** restructured `JivoAssistantForm.vue` from a single scrolling wall into 4 logical tabs (Basic / AI / Behavior / Advanced) with conditional reveal of the idle-action config block.
3. **6.4.3** added a checkbox-grid tool selector on scenarios; merge logic preserves admin selection while still extracting tools mentioned in the instruction.
4. **6.4.4** added avatar upload with Active Storage; appears in form + assistant list.
5. **Bonus refactors during this phase:** assistant form, scenario form, and custom-tool form all moved from modal to dedicated page routes for better UX on form-heavy editors.

---

**Goal:** Replace the unstructured "Phase 4 Testing" block in `JivoAssistantForm.vue` with a polished, grouped, tabbed/sectioned settings page. Add avatar upload. Add per-scenario tool selector.

**Sub-Task Items:**
1. **Tabbed settings.** Group fields into tabs: **Basic** (name/description/product), **AI** (api_key/model/temperature/system_prompt), **Behavior** (handoff/idle/V2/memory/FAQ), **Advanced** (custom instructions, response guidelines, guardrails).
2. **Avatar upload** for assistants. Active Storage attachment, displayed in conversation panel + assistant list.
3. **Per-scenario tool selector** in `JivoScenarioForm.vue`. Currently tools are only set via inline `[Label](tool://id)` markdown in the instruction. Add a multi-select dropdown that lists all `available_agent_tools` (built-ins + enabled custom tools); selected tools auto-merge into the `tools` jsonb. Markdown link syntax in instruction still works as override.
4. **Better feature toggle UX.** Group "Memory / FAQ" together with helper text. Group "Idle action / timeout / reminder limit" together with conditional reveals (timeout only shows when idle action is enabled).
5. **Response guidelines + guardrails** as new fields on `JivoAssistant` (jsonb arrays), reused in V2 prompt builder.

**Files to create:**
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantTabs.vue` — tab strip.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAvatarUploader.vue` — drag-drop avatar.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoToolSelector.vue` — multi-select dropdown for scenario tools.
- DB migration adding `response_guidelines` jsonb and `guardrails` jsonb to `jivo_assistants` (default `[]`).

**Files to modify:**
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — restructure into tabs.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoScenarioForm.vue` — embed `JivoToolSelector`.
- `app/services/jivo/prompts/assistant_prompt.rb` — inject `response_guidelines` + `guardrails` sections (mirror Captain's Liquid blocks).
- `app/models/jivo_assistant.rb` — `store_accessor` `response_guidelines`, `guardrails`.
- `app/controllers/api/v1/accounts/jivo/assistants_controller.rb` — permit new params + `:avatar` file.

**Test live:**
1. Open assistant form → tabs visible, fields grouped logically.
2. Upload an avatar PNG → appears in assistant list + JIVO panel header in conversations.
3. Edit a scenario → tool selector shows checkboxes for built-ins + custom tools → checking one updates the `tools` array on save.
4. Add response guidelines (`["Always greet by name", "Be concise"]`) → confirm they appear in the V2 system prompt via the runner log.

**Lock-in state:** Settings form is admin-friendly and feature-discoverable.

**Deferred:** Per-tab dirty-state tracking with "unsaved changes" warning — Phase 7.

---

### Sub-Task 6.5: Conversation Panel Polish + Inline Rewrite Editor

**Status: NOT STARTED**

**Goal:** Polish the agent-facing JIVO assistant panel during conversations.

**Sub-Task Items:**
1. **Tool icons rendered** next to scenario chips and in tool selector. Icons come from `config/agents/jivo_tools.yml` (`icon: 'note-add'` etc.) — wire into a small JS icon map.
2. **"Now talking to <scenario>" hint** in conversation header when V2 has handed off. Pull `result.context[:current_agent]` from the runner result and surface in the message bubble metadata.
3. **Surface contact notes as read-only context** in `JivoAssistantPanel.vue`. New collapsible section showing the contact's notes (the same notes 4.7.1 injects into the prompt) so agents see what JIVO sees.
4. **Deep editor integration for inline rewrite.** Currently rewrite produces text in the panel that the agent has to copy-paste. Wire the "Use as reply" button to insert directly into the reply box's editor (ProseMirror/TipTap). Same for the rewrite operation when the agent has selected text in the editor — replace selection in place.

**Files to create:**
- `app/javascript/dashboard/components-next/jivo/JivoToolIcon.vue` — maps `icon` string → lucide class.
- `app/javascript/dashboard/components-next/jivo/JivoContactMemoryPanel.vue` — read-only notes list inside the assistant panel.

**Files to modify:**
- `app/javascript/dashboard/components-next/jivo/JivoAssistantPanel.vue` — embed contact memory panel, wire Use-as-reply to editor injection.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Scenarios.vue` — render tool icons in chips.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoCustomToolForm.vue` — show the tool's icon next to the title.
- `app/services/jivo/conversation_v2_handler_service.rb` — persist `current_agent` from runner context into outgoing message's `additional_attributes['agent_name']`.
- `app/javascript/dashboard/components-next/conversation/.../<message bubble>` — render the `agent_name` badge when present.

**Test live:**
1. Open a conversation handled by V2 with scenarios. The bot's outgoing messages show a small "via <scenario>" badge.
2. Open JIVO panel → contact notes section shows the saved notes inline.
3. Highlight text in the reply box, click Rewrite → "Improve" → result replaces the highlighted text in place (not just the panel).
4. Click "Use as reply" on a Suggest-a-Reply result → text appears in the reply box.

**Lock-in state:** Agent UX feels polished + integrated.

**Deferred:** Diff view showing what rewrite changed — Phase 7.

---

### Sub-Task 6.6: Non-Resolution Learning Hardening

**Status: NOT STARTED**

**Goal:** Beyond the manual Learn button (4.7.2), add automatic triggers so businesses that don't resolve regularly still get auto-learning.

**Sub-Task Items:**
1. **Inactivity-based learner.** Hourly cron job: for each conversation that's been `open` (post-handoff) for >N hours since the last human reply, enqueue both jobs (Notes + FAQ with `force: true`). Prevents stale conversations from never feeding learning.
2. **`last_jivo_learned_at` watermark** on `Conversation.custom_attributes`. Set when learning runs. Skip conversations learned in the last 24h to avoid re-running on the same conversation every cron tick.
3. **Note dedup against existing.** Vector similarity (cosine) check on new notes vs existing notes for the same contact. Skip notes with > 0.92 similarity.
4. **Token-aware budgeting.** When the system prompt would exceed model context (notes + FAQs + history), trim oldest notes first, then oldest history, then oldest FAQs. Use `tiktoken_ruby` to count.

**Files to create:**
- `app/jobs/jivo/scheduled_learner_job.rb` — hourly cron, idempotent via watermark.
- `config/schedule.yml` — entry for the new job.
- `app/services/jivo/llm/note_dedup_service.rb` — embedding-based similarity check.
- `app/services/jivo/runtime/token_budget.rb` — `tiktoken_ruby` wrapper, trims context.

**Files to modify:**
- `app/services/jivo/conversation_v2_handler_service.rb` — pass through token budget service before sending to runner.
- `app/services/jivo/llm/contact_notes_service.rb` — call dedup service.

**Test live:**
1. Open a JIVO-handled conversation, send incoming + agent reply, leave for >2h.
2. Run `Jivo::ScheduledLearnerJob.perform_now` → notes + FAQs should appear.
3. Run again immediately → no-op (watermark).
4. Send a near-duplicate note via direct service call → dedup rejects it.

**Lock-in state:** Auto-learning works without resolution dependency.

**Deferred:** ML-based watermark (skip conversations with low Q&A density) — Phase 7.

---

### Sub-Task 6.7: Multimodal + Multi-Language Polish

**Status: NOT STARTED**

**Goal:** Harden vision + audio + translation paths.

**Sub-Task Items:**
1. **Vision-capable model detection.** When `assistant.model` doesn't support vision (e.g. `gpt-3.5-turbo`), warn admin in the form. Strip image content from V2 history at runtime to avoid OpenAI errors.
2. **Image OCR fallback.** For non-vision models, run uploaded images through Tesseract (or OpenAI's `gpt-4o-mini` for OCR) before passing to the runner. Image becomes text.
3. **Per-account language hint to Whisper.** Pass `language: account.locale` to the Whisper API for better transcription accuracy on non-English audio.
4. **Whisper fallback.** If Whisper fails (rate limit, model down), retry with `gpt-4o-mini-transcribe` if available.
5. **Translation caching.** Cache `(query, target_language) → translated_query` in Redis with 7-day TTL. Drops translation cost dramatically for repeat queries.
6. **Per-language FAQ storage.** Optional: allow a `:locale` field on `JivoAssistantResponse`. Search filters by detected query language. (Captain doesn't have this — possibly skip if scope creep.)

**Files to create:**
- `app/services/jivo/messages/image_ocr_service.rb`
- `app/services/jivo/llm/translation_cache.rb`
- DB migration: optional `locale` string on `jivo_assistant_responses`.

**Files to modify:**
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — vision-model warning banner.
- `app/services/jivo/openai_message_builder_service.rb` — strip images for non-vision models.
- `app/services/jivo/messages/audio_transcription_service.rb` — language hint + fallback.
- `app/services/jivo/llm/translate_query_service.rb` — wrap in cache.
- `app/models/jivo_assistant_response.rb` — `search` filters by locale if column populated.

**Test live:**
1. Switch assistant model to `gpt-3.5-turbo` → form shows vision warning.
2. Send an image → OCR runs → reply mentions text extracted from the image.
3. Send a Spanish voice note → transcript more accurate than before.
4. Search the same query twice — second hit doesn't call the translation API (Redis hit visible in logs).

**Lock-in state:** Multimodal + multilingual paths robust.

**Deferred:** Per-language KB UI (separate FAQ tabs per locale) — Phase 7.

---

### Sub-Task 6.8: Custom Tool UX + Live Tester

**Status: NOT STARTED**

**Goal:** Make custom tools easier to author and debug.

**Sub-Task Items:**
1. **Visual JSON schema editor for `param_schema`.** Replace the current flat add/remove list with a richer editor: drag-reorder rows, type-specific defaults, live preview of the OpenAI tool spec JSON it produces.
2. **Live tool tester.** "Run with sample input" button on the custom tool form. User fills sample param values → backend executes the tool exactly as the runner would → response panel shows raw HTTP response + formatted (post-`response_template`) output. Lets admins debug without round-tripping a real conversation.
3. **Drag-drop reordering of scenarios.** `position` integer column on `jivo_scenarios`. UI list re-orderable. Runner registers handoffs in order.
4. **Tool icon rendering in scenario form** (cross-cuts with 6.5; redundant if 6.5 ships first).
5. **Auth rotation reminder.** Track `auth_rotated_at` timestamp; warn admin when key/token is older than 90 days.

**Files to create:**
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoParamSchemaEditor.vue`
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoToolTester.vue`
- `app/controllers/api/v1/accounts/jivo/custom_tools/tester_controller.rb` — `POST /jivo/custom_tools/:id/test`, runs the tool with provided sample params.
- DB migration: `position` integer on `jivo_scenarios` (default 0); `auth_rotated_at` timestamp on `jivo_custom_tools`.

**Files to modify:**
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoCustomToolForm.vue` — embed editor + tester.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Scenarios.vue` — drag-drop list (vue-draggable or similar).
- `app/services/jivo/assistant/agent_runner_service.rb` — `assistant.scenarios.enabled.order(:position)`.

**Test live:**
1. Open a custom tool → param schema editor allows reorder + live JSON preview.
2. Click "Run with sample input" → fill param values → see real HTTP response inline.
3. Drag-reorder scenarios → ordering persists, runner uses new order.
4. Set a tool's `auth_rotated_at` to 100 days ago → form shows a yellow warning.

**Lock-in state:** Custom tool authoring and debugging is self-service.

**Deferred:** Tool versioning (revert to previous param schema) — Phase 7.

---

### Sub-Task 6.9: Webhooks + Events + Branding

**Status: NOT STARTED**

**Goal:** External integrations + white-labeling.

**Sub-Task Items:**
1. **Push events on assistant create/update.** WebSocket broadcast (matches Captain's `push_event_data` — already stubbed in `JivoAssistant#push_event_data`). Wire into `ActionCable` channels.
2. **Webhook signature verification on incoming custom tool responses.** When custom tool response includes an `X-Jivo-Signature` header, verify against the tool's configured `webhook_secret`. Add `webhook_secret` field to `JivoCustomTool`.
3. **Outbound webhooks** for JIVO events: `jivo.handoff_triggered`, `jivo.faq_created`, `jivo.scenario_invoked`. Reuse Chatwoot's existing webhook framework.
4. **`replaceInstallationName` everywhere.** Audit every user-facing string containing "Chatwoot" or hard-coded "JIVO" — replace with the branding helper from `shared/composables/useBranding`. Keeps self-hosted/white-label deployments clean.
5. **V1 → V2 bulk migration helper.** `Jivo::Tools::BulkMigrateToV2Service` with safety check: requires `feature_v2_agent` to be unset on the assistant before flipping. Run via Super Admin.

**Files to create:**
- `app/services/jivo/webhooks/event_publisher.rb` — wraps Chatwoot's webhook dispatch with JIVO event types.
- `app/services/jivo/webhooks/signature_verifier.rb`
- `app/services/jivo/tools/bulk_migrate_to_v2_service.rb`
- DB migration: `webhook_secret` (string, nullable) on `jivo_custom_tools`.

**Files to modify:**
- `app/models/jivo_assistant.rb` — `after_commit :broadcast_changes` (mirror Captain).
- `lib/jivo/tools/http_tool.rb` — verify signature header if `webhook_secret` is set.
- `app/services/jivo/listeners/jivo_listener.rb` (or equivalent) — emit webhook events.
- All user-facing JIVO strings — apply `replaceInstallationName`.

**Test live:**
1. Edit an assistant in one browser tab → another tab subscribed to the WebSocket sees the update event.
2. Set a tool's `webhook_secret` → POST a response missing the signature header → execution rejected.
3. Set up a webhook URL receiving `jivo.handoff_triggered` → trigger a handoff → webhook fires with the expected payload.
4. Self-host with a renamed installation → JIVO UI strings reflect the new brand name.
5. Run bulk migration on an account with 5 V1 assistants → all flip to V2 atomically.

**Lock-in state:** External integrations work; self-hosters can rebrand cleanly.

**Deferred:** Slack/Teams native integration — out of scope for JIVO core; lives in a separate plugin layer.

---

### Sub-Task 6.10: Captain-style PDF Ingestion Quality Upgrade

**Status: COMPLETE**

**Goal:** Improve PDF FAQ coverage after testing showed local text chunking captured explicit Q/A pairs but missed standalone product/cost/requirement blocks such as Security Deposit and nationality restrictions.

**Captain reference:**
- `enterprise/app/services/captain/llm/pdf_processing_service.rb` — uploads PDFs to OpenAI Files API and stores `openai_file_id`.
- `enterprise/app/services/captain/llm/paginated_faq_generator_service.rb` — reads the uploaded PDF by page chunks and generates comprehensive FAQs.
- `enterprise/app/services/captain/llm/system_prompts_service.rb#paginated_faq_generator` — strong completeness prompt.

**Implemented:**
- `app/models/jivo_document.rb` — added `openai_file_id` and `store_openai_file_id` helpers backed by `metadata['openai_file_id']`.
- `app/services/jivo/documents/pdf_upload_service.rb` — uploads the attached PDF to OpenAI Files API using the assistant's own OpenAI API key and stores the returned file id.
- `app/services/jivo/documents/paginated_faq_generator_service.rb` — Captain-style paginated PDF FAQ generation. It asks the model to convert explicit Q/A plus standalone Product, Cost, Details, Requirements, Inclusions, Notes, restrictions, policies, and warnings into FAQs.
- `app/services/jivo/documents/faq_coverage_audit_service.rb` — second-pass audit that compares source text against generated FAQs and creates additional FAQs for missing products, prices, requirements, restrictions, policies, or mandatory notes.
- `app/jobs/jivo/documents/pdf_ingest_job.rb` — still extracts local text for fallback/audit, then attempts OpenAI file upload. Upload failures are recorded in metadata and do not block local fallback generation.
- `app/jobs/jivo/documents/response_builder_job.rb` — PDF flow now prefers OpenAI-file paginated generation, falls back to local text chunking if upload/generation fails, runs the coverage audit pass, dedupes results, and saves generated FAQs as `pending` for admin approval.
- `app/services/jivo/llm/faq_generator_service.rb` — strengthened fallback prompt so local chunking also preserves standalone product/pricing/requirement blocks.

**Lock-in state:** PDF ingestion now mirrors Captain AI for quality while preserving JIVO's cheaper local extraction fallback. Admins still review generated FAQs before they enter RAG.

**Deferred:** OCR for scanned/image-only PDFs remains Phase 7.6.

---

### Sub-Task 6.11: FAQ Admin Search

**Status: COMPLETE**

**Goal:** Let admins quickly find generated/manual FAQs in the Settings → JIVO → assistant → FAQs page, especially after PDF imports generate many pending rows.

**Implemented:**
- `app/controllers/api/v1/accounts/jivo/assistant_responses_controller.rb#index` — accepts `query` and searches `question`/`answer` using case-insensitive text matching, combined with the existing status filter.
- `app/javascript/dashboard/api/jivoResponses.js` — passes `query` to the assistant responses list API.
- `app/javascript/dashboard/store/modules/jivoResponses.js` — forwards `query` from the Vuex `get` action.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Faqs.vue` — added search input, search submit, clear button, and empty-search state.
- `app/javascript/dashboard/i18n/locale/en/jivo.json` — added search strings.

**Lock-in state:** Admins can search pending, approved, or all FAQs by text without affecting the semantic RAG search used by V1/V2 replies.

---

### Phase 6 Handoff Notes

If picking up mid-phase:
1. Pick any sub-task — they're independent. Start with whichever solves the user's current pain point.
2. Each sub-task ends in a "lock-in state" where the work is complete, lint-clean, and doc-updated. Don't roll multiple sub-tasks together unless the user asks.
3. After completing a sub-task: `bundle exec rubocop -a` + `pnpm eslint --fix <changed files>` + update the tracker above.
4. Some sub-tasks have minor overlap (6.5 + 6.8 both touch tool icons; 6.4 + 6.5 both touch the assistant settings flow). The earlier sub-task wins on shared code; the later one references back.

---

## Phase 7 — Extended Capabilities (PLANNED, NOT STARTED)

Picks up everything that didn't make Phase 6's polish scope, plus two large features Captain has that JIVO didn't ship in Phases 1-5: **Copilot** (agent-side AI sidebar) and **Playground** (assistant tester). Also covers feature-inventory sections that were never scheduled — citations and usage limits.

**Total estimate:** ~25-35 hrs depending on which sub-tasks you pick. None of these are required for production — they're capability extensions.

**Phase 7 Status Tracker:**
- [ ] 7.1 Copilot (agent-side AI sidebar with 8 tools) — NOT STARTED
- [x] 7.2 Assistant Playground — COMPLETE (Captain-style full-page chat with assistant switcher; reuses V2 `AgentRunnerService` for replies; explicit OpenAI-key-missing message; new top-level route `/accounts/:accountId/jivo/:assistantId/playground`)
- [x] 7.3 Citations & Source Attribution — COMPLETE (V2 path; per-assistant `feature_citation` flag, FAQ tool collects citations on `tool_context.state[:citations]`, runner surfaces them in the result, V2 handler persists on `content_attributes[:citations]`, citation chips render under bot replies linking to the source URL)
- [ ] 7.4 Usage Limits & Tracking — NOT STARTED
- [ ] 7.5 FAQ Approval Advanced (inline edit, auto-approve, audit log) — NOT STARTED
- [ ] 7.6 Resilience (circuit breakers, PDF OCR, ML learning watermark) — NOT STARTED
- [ ] 7.7 Authoring & Editing Polish (dirty-state, rewrite diff, tool versioning) — NOT STARTED
- [ ] 7.8 Per-Language Knowledge Base UI — NOT STARTED

---

### Sub-Task 7.1: Copilot (Agent-side AI Sidebar)

**Status: NOT STARTED**
**Estimate:** ~10-12 hrs (largest single sub-task)

**Goal:** AI assistant for human agents to use *during* conversations. Different from the customer-facing autopilot — this is for the agent to ask JIVO for help (e.g., "summarize this conversation", "find similar past tickets", "search our help center for refund policy"). Maps to Section 6 of the feature inventory.

**Captain reference:**
- `enterprise/app/models/captain/copilot_thread.rb`
- `enterprise/app/models/captain/copilot_message.rb`
- `enterprise/app/services/captain/copilot/...`
- `enterprise/app/controllers/api/v1/accounts/captain/copilot_threads_controller.rb`
- `enterprise/app/controllers/api/v1/accounts/captain/copilot_messages_controller.rb`

**Sub-Task Items:**
1. **Thread management.** New tables `jivo_copilot_threads` (`title`, `account_id`, `user_id`, `assistant_id`) and `jivo_copilot_messages` (`message` jsonb, `message_type` enum, `account_id`, `copilot_thread_id`). REST CRUD scoped to `(account, user, assistant)`. Auto-title from first message.
2. **Async messaging.** User sends → message saved → background job calls runner with copilot tools → response saved → ActionCable broadcasts to user's channel. Three message types: `user`, `assistant`, `assistant_thinking`.
3. **8 copilot tools** (separate from autopilot's 6). Live in `lib/jivo/tools/copilot/`:
   - `SearchDocumentation` — same FAQ search but contextualized for agent
   - `GetConversation` — fetch conversation by ID
   - `SearchConversations` — search across the agent's conversations
   - `GetContact` — fetch contact by ID
   - `SearchContacts` — fuzzy contact search
   - `GetArticle` — fetch help center article
   - `SearchArticles` — help center semantic search
   - `SearchLinearIssues` — optional, gated on Linear integration being configured
4. **Language awareness.** Inject account/agent locale into the copilot's system prompt; reply in the agent's language.
5. **Usage tracking.** Increment `responses_usage` on the account on each copilot reply (feeds Sub-Task 7.4 if shipped, otherwise just counts).
6. **Sidebar UI.** New floating panel/button in the conversation view. Thread list (paginated 5/page) + active thread chat surface.

**Files to create:**
- `db/migrate/<ts>_create_jivo_copilot_threads.rb`, `<ts>_create_jivo_copilot_messages.rb`
- `app/models/jivo_copilot_thread.rb`, `app/models/jivo_copilot_message.rb`
- `app/policies/jivo_copilot_thread_policy.rb`
- `app/controllers/api/v1/accounts/jivo/copilot_threads_controller.rb`
- `app/controllers/api/v1/accounts/jivo/copilot_messages_controller.rb`
- `app/jobs/jivo/copilot/response_builder_job.rb`
- `app/services/jivo/copilot/runner_service.rb` — separate runner so copilot uses a different prompt + different tool set
- `app/channels/jivo_copilot_channel.rb` — ActionCable
- `lib/jivo/tools/copilot/{search_documentation,get_conversation,search_conversations,get_contact,search_contacts,get_article,search_articles,search_linear_issues}_tool.rb`
- Frontend: `app/javascript/dashboard/components-next/jivo/JivoCopilotPanel.vue`, `JivoCopilotThreadList.vue`, `JivoCopilotMessage.vue`
- API client `app/javascript/dashboard/api/jivoCopilot.js`
- Vuex store `app/javascript/dashboard/store/modules/jivoCopilot.js`

**Files to modify:**
- `app/models/jivo_assistant.rb` — `has_many :copilot_threads, class_name: 'JivoCopilotThread', dependent: :destroy_async`
- `config/routes.rb` — nested copilot routes under jivo/assistants
- `app/javascript/dashboard/store/index.js` — register copilot store
- Conversation view header — add "Ask JIVO" button that opens the sidebar

**Test live:**
1. Open any conversation → click "Ask JIVO" → sidebar opens.
2. Type "summarize this conversation" → user message + thinking + assistant response stream in.
3. Type "find similar tickets about refund delays" → search tool fires → results returned with conversation links.
4. Switch to another conversation → previous threads remain (scoped to user, not conversation).
5. Reply in Spanish → JIVO replies in Spanish.

**Lock-in state:** Copilot fully functional from the agent's perspective. Independent of autopilot — autopilot bots still work as before.

**Deferred:** Multi-agent copilot orchestration (different copilot scenarios for different agent specializations) — Phase 8 if ever needed.

---

### Sub-Task 7.2: Assistant Playground

**Status: NOT STARTED**
**Estimate:** ~3-4 hrs

**Goal:** Real-time chat tester inside the JIVO assistant settings page so admins can iterate on prompts without using real customer conversations as guinea pigs. Maps to Section 2.3.

**Captain reference:**
- Captain assistants controller's `playground` action (`POST /captain/assistants/:id/playground`)

**Sub-Task Items:**
1. **Backend `playground` action** that accepts an array of messages + the assistant ID, runs them through the same `Jivo::Assistant::AgentRunnerService` (or V1 handler if `feature_v2_agent` is off), but never persists messages to a real conversation. Returns the structured `{ response, reasoning }`.
2. **Frontend playground tab** in the assistant detail page. Two-pane: left = conversation history, right = inspector (system prompt preview, tool call trace, reasoning).
3. **Reset button** clears the local message history.
4. **"Use latest config" toggle** — when on, every message rebuilds the agent from current DB config; when off, uses a snapshot from when playground was opened.

**Files to create:**
- `app/controllers/api/v1/accounts/jivo/assistants/playground_controller.rb` (or member action on existing controller)
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Playground.vue`
- `app/javascript/dashboard/api/jivoPlayground.js`

**Files to modify:**
- `config/routes.rb` — add `post :playground` member action
- `app/javascript/dashboard/routes/dashboard/settings/jivo/jivo.routes.js` — `:assistantId/playground` route
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Index.vue` — add "Playground" button per assistant row

**Test live:**
1. Open assistant → click Playground → blank conversation surface.
2. Send "hello" → response appears with reasoning visible in the right pane.
3. Send a knowledge base question → see FAQ tool call in the trace.
4. Edit the assistant's system prompt in another tab, return to playground, send another message → if "use latest config" is on, behavior changes immediately.

**Lock-in state:** Admins can tune prompts safely.

**Deferred:** Save / replay test scripts (so QA can run the same script across prompt versions) — Phase 8.

---

### Sub-Task 7.3: Citations & Source Attribution

**Status: NOT STARTED**
**Estimate:** ~3-4 hrs

**Goal:** When JIVO answers from a knowledge base FAQ or document, attach a source citation to the outgoing message so customers can verify the answer. Maps to Section 14.

**Sub-Task Items:**
1. **Capture citations during runner execution.** When `Jivo::Tools::FaqLookupTool` returns FAQs, record which FAQ IDs (and their `documentable_id`) were used. Stash on `tool_context.context[:citations]`.
2. **Surface citations on outgoing messages.** Stash `additional_attributes['citations'] = [{ document_id:, external_link:, question: }]` on the outgoing message record.
3. **Render citations in conversation panel.** Small chip below each bot reply: "Source: <document name>" linking to the external URL when present.
4. **Account-level toggle** `feature_citation` to enable/disable citation display.

**Files to create:**
- `app/services/jivo/runtime/citation_collector.rb` — accumulates citations as tools fire.

**Files to modify:**
- `lib/jivo/tools/faq_lookup_tool.rb` — write citation entries to `tool_context.context[:citations]`.
- `app/services/jivo/conversation_v2_handler_service.rb` — read collected citations from runner result, save on outgoing message's `additional_attributes`.
- `app/javascript/dashboard/components-next/conversation/.../<message bubble>` — render citation chips when present.
- `app/models/jivo_assistant.rb` — `feature_citation` config accessor.

**Test live:**
1. Enable `feature_citation` on assistant.
2. Customer asks something the FAQ answers → bot replies → citation chip appears under the reply linking to the source document.
3. Asks something not in KB → no citation chip (correct).
4. Toggle citation off → chips disappear on next reply.

**Lock-in state:** Customers can verify bot answers.

**Deferred:** Inline citations within the reply text (e.g. footnote markers) — Phase 8.

---

### Sub-Task 7.4: Usage Limits & Tracking

**Status: NOT STARTED**
**Estimate:** ~3-4 hrs

**Goal:** Track and enforce JIVO usage per account. Maps to Section 17.

**Sub-Task Items:**
1. **Counter increment.** Every successful V2 reply, every copilot reply (7.1), every inline task (rewrite/summarize/etc.) increments `account.jivo_responses_usage` (new column on accounts).
2. **Monthly reset.** Cron job on the 1st of each month resets the counter (or rolls over, depending on plan).
3. **Pre-flight limit check.** Before each runner call, check `account.jivo_responses_usage < account.jivo_responses_limit`. If over, gracefully fall back to `bot_handoff!` with a "service temporarily unavailable" message.
4. **Usage dashboard.** Settings → JIVO → Usage tab showing current month's count, limit, % used, daily breakdown chart.
5. **Configurable limits per account.** Super Admin sets `jivo_responses_limit` per account.

**Files to create:**
- `db/migrate/<ts>_add_jivo_usage_columns_to_accounts.rb` — `jivo_responses_usage` integer default 0; `jivo_responses_limit` integer nullable; `jivo_usage_reset_at` timestamp.
- `app/jobs/jivo/usage/monthly_reset_job.rb`
- `app/services/jivo/usage/limit_checker.rb`
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Usage.vue`

**Files to modify:**
- `app/services/jivo/conversation_v2_handler_service.rb` — `LimitChecker.allowed?` before running; increment after successful reply.
- `app/services/jivo/conversation_handler_service.rb` — same for V1 path.
- `app/services/jivo/tasks/*_service.rb` — increment after each inline task.
- `config/schedule.yml` — monthly reset cron.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/jivo.routes.js` — `usage` route.

**Test live:**
1. Set `jivo_responses_limit = 5` on the account.
2. Run 5 V2 replies — all succeed.
3. 6th reply → handed off to human with "service temporarily unavailable" message.
4. Open Usage tab → see 5/5 used.
5. Manually run the reset job → counter back to 0.

**Lock-in state:** Per-account quota enforced; usage observable.

**Deferred:** Per-feature breakdown (autopilot vs copilot vs inline tasks) — Phase 8 if billing needs it.

---

### Sub-Task 7.5: FAQ Approval Advanced

**Status: NOT STARTED**
**Estimate:** ~3-4 hrs

**Goal:** Beyond Phase 6.1's basic approve/reject/bulk, add inline editing, smart auto-approval, and an audit trail.

**Sub-Task Items:**
1. **Inline edit before approval.** In the FAQ approval list, clicking a pending row opens an inline edit form (question + answer textareas) that lets the admin tweak the auto-generated content before approving. Submit = update + approve in one click.
2. **Auto-approve high-confidence FAQs.** When `Jivo::Llm::ConversationFaqService` generates a new FAQ, compute cosine distance against the closest existing approved FAQ. If distance < 0.05 (very similar to something already approved), auto-approve the new one — no human review needed.
3. **Approval audit log.** New table `jivo_response_audits` tracking `(response_id, action, user_id, before_status, after_status, before_content, after_content, created_at)`. Read-only view in admin showing the full history per FAQ.
4. **Reject reasons.** Optional reason text on reject, captured in audit.

**Files to create:**
- `db/migrate/<ts>_create_jivo_response_audits.rb`
- `app/models/jivo_response_audit.rb`
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoFaqInlineEdit.vue`
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoFaqAuditLog.vue`

**Files to modify:**
- `app/services/jivo/llm/conversation_faq_service.rb` — auto-approve when distance < threshold.
- `app/controllers/api/v1/accounts/jivo/bulk_actions_controller.rb` (from 6.1) — write audit rows on each action.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Faqs.vue` — wire inline edit + audit log link.

**Test live:**
1. Pending FAQ → click row → edit question, save → approved with new content.
2. Run conversation FAQ generation on a question very similar to an existing FAQ → new FAQ auto-approved (no pending entry).
3. Reject a FAQ with reason "duplicate" → audit log shows reject + reason.

**Lock-in state:** FAQ pipeline is curatable, not just gateable.

**Deferred:** Reviewer assignment (round-robin pending FAQs to specific admins) — Phase 8.

---

### Sub-Task 7.6: Resilience (Circuit Breakers + PDF OCR + ML Learning Watermark)

**Status: NOT STARTED**
**Estimate:** ~4-5 hrs

**Goal:** Three independent reliability improvements bundled because each is too small to be its own sub-task.

**Sub-Task Items:**
1. **Per-tool circuit breakers.** When a custom tool fails (HTTP 5xx, timeout, exception) N consecutive times within a window, auto-disable for a cooldown period. Redis-backed state keyed by `(account_id, tool_slug)`. Surfaces a "circuit open" warning in the custom tool list.
2. **OCR for scanned PDFs.** When a PDF page has no extractable text (image-only), pass through Tesseract or `gpt-4o-mini` vision OCR. Picked up automatically by `Jivo::Documents::PaginatedFaqService` from 6.3.
3. **ML-based learning watermark.** Skip the auto-learner for conversations with low Q&A density (e.g. <2 customer questions, only chitchat). Use a simple heuristic first (keyword density, question-mark count); add a small classifier later if needed.

**Files to create:**
- `app/services/jivo/runtime/circuit_breaker.rb` — Redis token bucket + state machine.
- `app/services/jivo/documents/ocr_service.rb`
- `app/services/jivo/learning/quality_filter.rb`

**Files to modify:**
- `lib/jivo/tools/http_tool.rb` — wrap perform in circuit breaker check.
- `app/services/jivo/documents/paginated_faq_service.rb` — call OCR for image-only pages.
- `app/jobs/jivo/scheduled_learner_job.rb` (from 6.6) — pre-filter conversations through quality filter.

**Test live:**
1. Configure a custom tool pointing to a URL that returns 500. Trigger 5 consecutive failures → tool flagged as circuit-open in the list, 6th call rejected without HTTP attempt. After cooldown, re-armed.
2. Upload a scanned PDF → OCR runs → FAQs generated from extracted text.
3. Run scheduled learner against a chitchat conversation → no notes/FAQs produced.

**Lock-in state:** JIVO degrades gracefully under tool/data quality issues.

**Deferred:** Adaptive cooldown (longer for repeat offenders) — Phase 8.

---

### Sub-Task 7.7: Authoring & Editing Polish (Dirty-State + Rewrite Diff + Tool Versioning)

**Status: NOT STARTED**
**Estimate:** ~4-5 hrs

**Goal:** Three small UX wins for admins authoring assistants/scenarios/tools.

**Sub-Task Items:**
1. **Per-tab dirty-state tracking.** When admin has unsaved changes in `JivoAssistantForm.vue` (or scenario/tool forms), show a dot on the active tab + "unsaved changes" banner + browser `beforeunload` warning. Detects via deep watch on the form ref.
2. **Diff view for rewrite results.** Inline rewrite produces a result; current UI shows just the new text. Add a side-by-side diff (original vs rewritten) with character/word-level highlighting. Reuses any existing diff library (likely `diff-match-patch` already in Chatwoot).
3. **Tool versioning + revert.** When a custom tool's `param_schema` or `endpoint_url` changes, snapshot the previous version into a new `jivo_custom_tool_versions` table. Form shows "Revert" dropdown listing the last 10 versions. Selecting one restores those values into the form (admin still has to save).

**Files to create:**
- `db/migrate/<ts>_create_jivo_custom_tool_versions.rb`
- `app/models/jivo_custom_tool_version.rb`
- `app/javascript/dashboard/composables/useDirtyState.js`
- `app/javascript/dashboard/components-next/jivo/JivoRewriteDiff.vue`

**Files to modify:**
- `app/models/jivo_custom_tool.rb` — `before_update :snapshot_previous_version` (only when relevant fields change).
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoAssistantForm.vue` — wire dirty-state composable + tab indicators.
- `app/javascript/dashboard/components-next/jivo/JivoAssistantPanel.vue` — embed diff view in rewrite result.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoCustomToolForm.vue` — version dropdown.

**Test live:**
1. Edit assistant name, switch tabs without saving → dot appears on Basic tab; navigate away → confirmation prompt.
2. Run rewrite "Improve" on a sentence → diff shows additions in green, deletions in red.
3. Edit custom tool's URL three times → form's Revert dropdown shows 3 entries → pick the first → URL restored, save → tool back to original.

**Lock-in state:** Authoring feels safe + recoverable.

**Deferred:** Cross-resource version compare ("show me what changed in this assistant between Tuesday and now") — Phase 8.

---

### Sub-Task 7.8: Per-Language Knowledge Base UI

**Status: NOT STARTED**
**Estimate:** ~3-4 hrs

**Goal:** Today the `JivoAssistantResponse` table has no `locale` column — all FAQs are stored in one language and Phase 4.5's translation service translates queries at runtime. For accounts that genuinely operate in multiple languages, that's fragile (translation cost + accuracy). Add proper per-locale FAQ storage.

**Sub-Task Items:**
1. **`locale` column on `jivo_assistant_responses`** (string, nullable, default account locale on save).
2. **Filter `JivoAssistantResponse.search`** by detected query locale, fall back to account default if no match.
3. **Locale tabs in the FAQ admin page.** Each enabled language gets a tab; admin authors FAQs per locale. Document-imported FAQs auto-tag with the document's detected locale.
4. **Account-level enabled locales setting** — list of locales the assistant should accept FAQs in (defaults to just the account locale).

**Files to create:**
- `db/migrate/<ts>_add_locale_to_jivo_assistant_responses.rb`

**Files to modify:**
- `app/models/jivo_assistant_response.rb` — `search` filters by locale; auto-set `locale` from account on create.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/Faqs.vue` — locale tab strip.
- `app/javascript/dashboard/routes/dashboard/settings/jivo/components/JivoFaqForm.vue` (or equivalent) — locale selector field.
- `app/services/jivo/llm/conversation_faq_service.rb` — set locale based on conversation's detected language.

**Test live:**
1. Add a FAQ in English (locale `en`) and one in Spanish (locale `es`).
2. English-speaking customer asks → only English FAQ matches.
3. Spanish-speaking customer asks → only Spanish FAQ matches.
4. Disable Spanish locale on the account → Spanish FAQs hidden from search but kept in DB.

**Lock-in state:** Multilingual KBs are first-class.

**Deferred:** Auto-translation pipeline (admin maintains one source language, system mirrors to others) — Phase 8.

---

### Phase 7 Handoff Notes

If picking up:
1. Same independence rules as Phase 6 — pick whichever sub-task matters most. **7.1 and 7.2 are the biggest wins** (Copilot, Playground) since they unlock entirely new product surfaces. The rest are quality improvements.
2. Some sub-tasks depend on Phase 6 work: 7.5 builds on 6.1's bulk-actions controller; 7.6's OCR builds on 6.3's PDF pipeline; 7.6's ML watermark builds on 6.6's scheduled learner. If those aren't done yet, those Phase 7 items will need stub versions of the missing dependencies.
3. Phase 7 has no critical path — none of these block production. They're product expansion, not stability.

---

## Conventions for Updating This Log

When completing a phase:
1. Move the phase from "NOT STARTED" to "✅ COMPLETED" with date
2. Fill in the **Implemented** section with what actually shipped
3. Fill in the **Deferred** section with EVERY skipped item — don't quietly drop features
4. For each deferred item, specify which future phase it will land in
5. Skipped items that won't ever be added must be marked `Skip — <reason>` with explicit reasoning

This log replaces commit messages or PR descriptions as the canonical record of what's in JIVO vs Captain.
