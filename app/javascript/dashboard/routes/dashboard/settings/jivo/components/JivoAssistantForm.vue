<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import JivoAvatarUploader from './JivoAvatarUploader.vue';

const props = defineProps({
  mode: { type: String, default: 'create' },
  assistant: { type: Object, default: () => ({}) },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'close']);
const { t } = useI18n();
const { currentAccount } = useAccount();

const byoKeyAllowed = computed(
  () => currentAccount.value?.custom_attributes?.jivo_byo_key_allowed === true
);
const openAIKeyConfigured = computed(
  () => props.assistant.config?.openai_api_key_configured === true
);

const linesToArray = text =>
  text
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);

const arrayToLines = arr => (Array.isArray(arr) ? arr.join('\n') : '');

const form = ref({
  name: props.assistant.name || '',
  description: props.assistant.description || '',
  response_guidelines_text: arrayToLines(props.assistant.response_guidelines),
  guardrails_text: arrayToLines(props.assistant.guardrails),
  config: {
    openai_api_key: props.assistant.config?.openai_api_key || '',
    openai_model: props.assistant.config?.openai_model || 'gpt-4.1-mini',
    product_name: props.assistant.config?.product_name || '',
    handoff_message: props.assistant.config?.handoff_message || '',
    temperature: props.assistant.config?.temperature || 0.7,
    system_prompt: props.assistant.config?.system_prompt || '',
    feature_memory: props.assistant.config?.feature_memory || false,
    feature_faq: props.assistant.config?.feature_faq || false,
    feature_citation: props.assistant.config?.feature_citation || false,
    feature_v2_agent: props.assistant.config?.feature_v2_agent || false,
    feature_idle_action: props.assistant.config?.feature_idle_action || false,
    idle_timeout_minutes: props.assistant.config?.idle_timeout_minutes || 60,
    idle_action: props.assistant.config?.idle_action || 'handoff',
    idle_message: props.assistant.config?.idle_message || '',
    idle_reminder_limit: props.assistant.config?.idle_reminder_limit || 3,
  },
});

const isValid = computed(() => {
  return form.value.name.trim() && form.value.description.trim();
});

const NON_VISION_MODEL_PATTERNS = [
  /^gpt-3\.5/i,
  /^text-/i,
  /^o1-mini/i,
  /^gpt-4-0314/i,
  /^gpt-4-0613/i,
  /-instruct$/i,
  /-nano\b/i,
];

const isVisionCapable = computed(() => {
  const model = (form.value.config.openai_model || '').trim();
  if (!model) return true;
  return !NON_VISION_MODEL_PATTERNS.some(pattern => pattern.test(model));
});

const tabs = [
  { id: 'basic', key: 'JIVO.ASSISTANTS.FORM.TABS.BASIC' },
  { id: 'ai', key: 'JIVO.ASSISTANTS.FORM.TABS.AI' },
  { id: 'behavior', key: 'JIVO.ASSISTANTS.FORM.TABS.BEHAVIOR' },
  { id: 'advanced', key: 'JIVO.ASSISTANTS.FORM.TABS.ADVANCED' },
];
const currentTab = ref('basic');

const submit = () => {
  if (!isValid.value) return;
  const { response_guidelines_text, guardrails_text, ...rest } = form.value;
  emit('save', {
    ...rest,
    response_guidelines: linesToArray(response_guidelines_text),
    guardrails: linesToArray(guardrails_text),
  });
};
</script>

<template>
  <div class="bg-n-solid-1 rounded-lg border border-n-weak overflow-hidden">
    <div class="px-6 pt-4 border-b border-n-weak">
      <div class="flex gap-2">
        <button
          v-for="tab in tabs"
          :key="tab.id"
          type="button"
          class="px-3 py-2 text-sm font-medium border-b-2 transition-colors"
          :class="
            currentTab === tab.id
              ? 'border-n-brand text-n-slate-12'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="currentTab = tab.id"
        >
          {{ t(tab.key) }}
        </button>
      </div>
    </div>

    <div class="p-6 space-y-4">
      <div v-show="currentTab === 'basic'" class="space-y-4">
        <JivoAvatarUploader :assistant="assistant" />

        <Input
          v-model="form.name"
          :label="t('JIVO.ASSISTANTS.FORM.NAME.LABEL')"
          :placeholder="t('JIVO.ASSISTANTS.FORM.NAME.PLACEHOLDER')"
        />

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ t('JIVO.ASSISTANTS.FORM.DESCRIPTION.LABEL') }}
          </label>
          <textarea
            v-model="form.description"
            rows="2"
            :placeholder="t('JIVO.ASSISTANTS.FORM.DESCRIPTION.PLACEHOLDER')"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>

        <Input
          v-model="form.config.product_name"
          :label="t('JIVO.ASSISTANTS.FORM.PRODUCT_NAME.LABEL')"
          :placeholder="t('JIVO.ASSISTANTS.FORM.PRODUCT_NAME.PLACEHOLDER')"
        />

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ t('JIVO.ASSISTANTS.FORM.HANDOFF_MESSAGE.LABEL') }}
          </label>
          <textarea
            v-model="form.config.handoff_message"
            rows="2"
            :placeholder="t('JIVO.ASSISTANTS.FORM.HANDOFF_MESSAGE.PLACEHOLDER')"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>
      </div>

      <div v-show="currentTab === 'ai'" class="space-y-4">
        <template v-if="byoKeyAllowed">
          <Input
            v-model="form.config.openai_api_key"
            :label="t('JIVO.ASSISTANTS.FORM.OPENAI_API_KEY.LABEL')"
            type="password"
            :placeholder="
              openAIKeyConfigured
                ? t(
                    'JIVO.ASSISTANTS.FORM.OPENAI_API_KEY.CONFIGURED_PLACEHOLDER'
                  )
                : t('JIVO.ASSISTANTS.FORM.OPENAI_API_KEY.PLACEHOLDER')
            "
          />
          <p v-if="openAIKeyConfigured" class="text-xs text-n-slate-11">
            {{ t('JIVO.ASSISTANTS.FORM.OPENAI_API_KEY.CONFIGURED_NOTICE') }}
          </p>
        </template>
        <p
          v-else
          class="text-xs text-n-slate-11 bg-n-alpha-black2 border border-n-weak rounded-md px-3 py-2"
        >
          {{ t('JIVO.ASSISTANTS.FORM.OPENAI_API_KEY.PLATFORM_KEY_NOTICE') }}
        </p>

        <Input
          v-model="form.config.openai_model"
          :label="t('JIVO.ASSISTANTS.FORM.OPENAI_MODEL.LABEL')"
          :placeholder="t('JIVO.ASSISTANTS.FORM.OPENAI_MODEL.PLACEHOLDER')"
        />

        <p
          v-if="!isVisionCapable"
          class="text-xs text-n-amber-text bg-n-amber-3 border border-n-amber-7 rounded-md px-2 py-1.5"
        >
          {{ t('JIVO.ASSISTANTS.FORM.OPENAI_MODEL.VISION_WARNING') }}
        </p>

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{
              t('JIVO.ASSISTANTS.FORM.TEMPERATURE', {
                value: form.config.temperature,
              })
            }}
          </label>
          <input
            v-model.number="form.config.temperature"
            type="range"
            min="0"
            max="2"
            step="0.1"
            class="w-full"
          />
        </div>
      </div>

      <div v-show="currentTab === 'behavior'" class="space-y-4">
        <div class="space-y-3">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('JIVO.ASSISTANTS.FORM.GROUPS.LEARNING') }}
          </h3>
          <div class="flex items-center justify-between gap-4">
            <label class="text-sm text-n-slate-12">
              {{ t('JIVO.ASSISTANTS.FORM.FEATURE_MEMORY.LABEL') }}
            </label>
            <ToggleSwitch v-model="form.config.feature_memory" />
          </div>

          <div class="flex items-center justify-between gap-4">
            <label class="text-sm text-n-slate-12">
              {{ t('JIVO.ASSISTANTS.FORM.FEATURE_FAQ.LABEL') }}
            </label>
            <ToggleSwitch v-model="form.config.feature_faq" />
          </div>

          <div class="flex items-center justify-between gap-4">
            <div>
              <label class="text-sm text-n-slate-12">
                {{ t('JIVO.ASSISTANTS.FORM.FEATURE_CITATION.LABEL') }}
              </label>
              <p class="text-xs text-n-slate-11 mt-0.5">
                {{ t('JIVO.ASSISTANTS.FORM.FEATURE_CITATION.HELP') }}
              </p>
            </div>
            <ToggleSwitch v-model="form.config.feature_citation" />
          </div>
        </div>

        <div class="space-y-3 pt-3 border-t border-n-weak">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('JIVO.ASSISTANTS.FORM.GROUPS.RUNNER') }}
          </h3>
          <div class="flex items-center justify-between gap-4">
            <div>
              <label class="text-sm text-n-slate-12">
                {{ t('JIVO.ASSISTANTS.FORM.FEATURE_V2_AGENT.LABEL') }}
              </label>
              <p class="text-xs text-n-slate-11 mt-0.5">
                {{ t('JIVO.ASSISTANTS.FORM.FEATURE_V2_AGENT.HELP') }}
              </p>
            </div>
            <ToggleSwitch v-model="form.config.feature_v2_agent" />
          </div>
        </div>

        <!--
          Temporarily hidden — idle reassignment is handled at the inbox
          level (Settings → Inbox → Collaborators). Re-enable when the
          per-assistant idle action UI is ready for prod.
        <div class="space-y-3 pt-3 border-t border-n-weak">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('JIVO.ASSISTANTS.FORM.GROUPS.IDLE') }}
          </h3>
          <div class="flex items-center justify-between gap-4">
            <label class="text-sm text-n-slate-12">
              {{ t('JIVO.ASSISTANTS.FORM.FEATURE_IDLE_ACTION.LABEL') }}
            </label>
            <ToggleSwitch v-model="form.config.feature_idle_action" />
          </div>

          <div
            v-if="form.config.feature_idle_action"
            class="space-y-4 pl-3 border-l-2 border-n-weak"
          >
            <Input
              v-model="form.config.idle_timeout_minutes"
              :label="t('JIVO.ASSISTANTS.FORM.IDLE_TIMEOUT.LABEL')"
              type="number"
              min="1"
              :placeholder="t('JIVO.ASSISTANTS.FORM.IDLE_TIMEOUT.PLACEHOLDER')"
            />

            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JIVO.ASSISTANTS.FORM.IDLE_ACTION.LABEL') }}
              </label>
              <select
                v-model="form.config.idle_action"
                class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              >
                <option value="handoff">
                  {{ t('JIVO.ASSISTANTS.FORM.IDLE_ACTION.OPTIONS.HANDOFF') }}
                </option>
                <option value="resolve">
                  {{ t('JIVO.ASSISTANTS.FORM.IDLE_ACTION.OPTIONS.RESOLVE') }}
                </option>
                <option value="reminder">
                  {{ t('JIVO.ASSISTANTS.FORM.IDLE_ACTION.OPTIONS.REMINDER') }}
                </option>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium text-n-slate-12 mb-1">
                {{ t('JIVO.ASSISTANTS.FORM.IDLE_MESSAGE.LABEL') }}
              </label>
              <textarea
                v-model="form.config.idle_message"
                rows="2"
                :placeholder="
                  t('JIVO.ASSISTANTS.FORM.IDLE_MESSAGE.PLACEHOLDER')
                "
                class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              />
            </div>

            <Input
              v-if="form.config.idle_action === 'reminder'"
              v-model="form.config.idle_reminder_limit"
              :label="t('JIVO.ASSISTANTS.FORM.IDLE_REMINDER_LIMIT.LABEL')"
              type="number"
              min="1"
              :placeholder="
                t('JIVO.ASSISTANTS.FORM.IDLE_REMINDER_LIMIT.PLACEHOLDER')
              "
              :help-text="
                t('JIVO.ASSISTANTS.FORM.IDLE_REMINDER_LIMIT.HELP_TEXT')
              "
            />
          </div>
        </div>
        -->
      </div>

      <div v-show="currentTab === 'advanced'" class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ t('JIVO.ASSISTANTS.FORM.SYSTEM_PROMPT.LABEL') }}
          </label>
          <textarea
            v-model="form.config.system_prompt"
            rows="4"
            :placeholder="t('JIVO.ASSISTANTS.FORM.SYSTEM_PROMPT.PLACEHOLDER')"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ t('JIVO.ASSISTANTS.FORM.RESPONSE_GUIDELINES.LABEL') }}
          </label>
          <textarea
            v-model="form.response_guidelines_text"
            rows="3"
            :placeholder="
              t('JIVO.ASSISTANTS.FORM.RESPONSE_GUIDELINES.PLACEHOLDER')
            "
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand font-mono text-xs"
          />
          <p class="text-xs text-n-slate-11 mt-1">
            {{ t('JIVO.ASSISTANTS.FORM.RESPONSE_GUIDELINES.HELP') }}
          </p>
        </div>

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ t('JIVO.ASSISTANTS.FORM.GUARDRAILS.LABEL') }}
          </label>
          <textarea
            v-model="form.guardrails_text"
            rows="3"
            :placeholder="t('JIVO.ASSISTANTS.FORM.GUARDRAILS.PLACEHOLDER')"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand font-mono text-xs"
          />
          <p class="text-xs text-n-slate-11 mt-1">
            {{ t('JIVO.ASSISTANTS.FORM.GUARDRAILS.HELP') }}
          </p>
        </div>
      </div>
    </div>

    <div class="p-6 border-t border-n-weak flex justify-end gap-2">
      <Button
        :label="t('JIVO.ASSISTANTS.FORM.CANCEL')"
        slate
        faded
        @click="emit('close')"
      />
      <Button
        :label="
          mode === 'create'
            ? t('JIVO.ASSISTANTS.FORM.CREATE')
            : t('JIVO.ASSISTANTS.FORM.SAVE')
        "
        :is-loading="isLoading"
        :disabled="!isValid"
        @click="submit"
      />
    </div>
  </div>
</template>
