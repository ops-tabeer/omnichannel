<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  mode: { type: String, default: 'create' },
  assistant: { type: Object, default: () => ({}) },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'close']);
const { t } = useI18n();

const form = ref({
  name: props.assistant.name || '',
  description: props.assistant.description || '',
  config: {
    openai_api_key: props.assistant.config?.openai_api_key || '',
    openai_model: props.assistant.config?.openai_model || 'gpt-4.1-mini',
    product_name: props.assistant.config?.product_name || '',
    handoff_message: props.assistant.config?.handoff_message || '',
    temperature: props.assistant.config?.temperature || 0.7,
    system_prompt: props.assistant.config?.system_prompt || '',
    feature_memory: props.assistant.config?.feature_memory || false,
    feature_faq: props.assistant.config?.feature_faq || false,
    feature_idle_action: props.assistant.config?.feature_idle_action || false,
    idle_timeout_minutes: props.assistant.config?.idle_timeout_minutes || 60,
    idle_action: props.assistant.config?.idle_action || 'handoff',
    idle_message: props.assistant.config?.idle_message || '',
  },
});

const title = computed(() =>
  props.mode === 'create'
    ? t('JIVO.ASSISTANTS.FORM.CREATE_TITLE')
    : t('JIVO.ASSISTANTS.FORM.EDIT_TITLE')
);

const isValid = computed(() => {
  return form.value.name.trim() && form.value.description.trim();
});

const submit = () => {
  if (!isValid.value) return;
  emit('save', form.value);
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('close')"
  >
    <div
      class="bg-n-solid-1 rounded-lg shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto"
    >
      <div class="p-6 border-b border-n-weak">
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{ title }}
        </h2>
      </div>

      <div class="p-6 space-y-4">
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

        <Input
          v-model="form.config.openai_api_key"
          :label="t('JIVO.ASSISTANTS.FORM.OPENAI_API_KEY.LABEL')"
          type="password"
          :placeholder="t('JIVO.ASSISTANTS.FORM.OPENAI_API_KEY.PLACEHOLDER')"
        />

        <Input
          v-model="form.config.openai_model"
          :label="t('JIVO.ASSISTANTS.FORM.OPENAI_MODEL.LABEL')"
          :placeholder="t('JIVO.ASSISTANTS.FORM.OPENAI_MODEL.PLACEHOLDER')"
        />

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

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ t('JIVO.ASSISTANTS.FORM.SYSTEM_PROMPT.LABEL') }}
          </label>
          <textarea
            v-model="form.config.system_prompt"
            rows="3"
            :placeholder="t('JIVO.ASSISTANTS.FORM.SYSTEM_PROMPT.PLACEHOLDER')"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>

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

        <div class="pt-4 mt-2 space-y-4 border-t border-n-weak">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('JIVO.ASSISTANTS.FORM.ADVANCED_FEATURES.TITLE') }}
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
            <label class="text-sm text-n-slate-12">
              {{ t('JIVO.ASSISTANTS.FORM.FEATURE_IDLE_ACTION.LABEL') }}
            </label>
            <ToggleSwitch v-model="form.config.feature_idle_action" />
          </div>

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
              :placeholder="t('JIVO.ASSISTANTS.FORM.IDLE_MESSAGE.PLACEHOLDER')"
              class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            />
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
  </div>
</template>
