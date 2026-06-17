<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import JivoToolSelector from './JivoToolSelector.vue';

const props = defineProps({
  mode: { type: String, default: 'create' },
  scenario: { type: Object, default: () => ({}) },
  assistantId: { type: [Number, String], default: null },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'close']);
const { t } = useI18n();

const form = ref({
  title: props.scenario.title || '',
  description: props.scenario.description || '',
  instruction: props.scenario.instruction || '',
  tools: Array.isArray(props.scenario.tools) ? [...props.scenario.tools] : [],
  enabled: props.scenario.enabled === undefined ? true : props.scenario.enabled,
});

const isValid = computed(
  () =>
    form.value.title.trim() &&
    form.value.description.trim() &&
    form.value.instruction.trim()
);

const submit = () => {
  if (!isValid.value) return;
  emit('save', form.value);
};
</script>

<template>
  <div class="bg-n-solid-1 rounded-lg border border-n-weak overflow-hidden">
    <div class="p-6 space-y-4">
      <Input
        v-model="form.title"
        :label="t('JIVO.SCENARIOS.FORM.TITLE.LABEL')"
        :placeholder="t('JIVO.SCENARIOS.FORM.TITLE.PLACEHOLDER')"
      />

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ t('JIVO.SCENARIOS.FORM.DESCRIPTION.LABEL') }}
        </label>
        <textarea
          v-model="form.description"
          rows="2"
          :placeholder="t('JIVO.SCENARIOS.FORM.DESCRIPTION.PLACEHOLDER')"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        />
      </div>

      <JivoToolSelector
        v-if="assistantId"
        v-model="form.tools"
        :assistant-id="assistantId"
      />

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ t('JIVO.SCENARIOS.FORM.INSTRUCTION.LABEL') }}
        </label>
        <textarea
          v-model="form.instruction"
          rows="6"
          :placeholder="t('JIVO.SCENARIOS.FORM.INSTRUCTION.PLACEHOLDER')"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand font-mono text-sm"
        />
        <p class="text-xs text-n-slate-11 mt-1">
          {{ t('JIVO.SCENARIOS.FORM.INSTRUCTION.HELP') }}
        </p>
      </div>

      <div class="flex items-center justify-between gap-4">
        <label class="text-sm text-n-slate-12">
          {{ t('JIVO.SCENARIOS.FORM.ENABLED.LABEL') }}
        </label>
        <ToggleSwitch v-model="form.enabled" />
      </div>
    </div>

    <div class="p-6 border-t border-n-weak flex justify-end gap-2">
      <Button
        :label="t('JIVO.SCENARIOS.FORM.CANCEL')"
        slate
        faded
        @click="emit('close')"
      />
      <Button
        :label="
          mode === 'create'
            ? t('JIVO.SCENARIOS.FORM.CREATE')
            : t('JIVO.SCENARIOS.FORM.SAVE')
        "
        :is-loading="isLoading"
        :disabled="!isValid"
        @click="submit"
      />
    </div>
  </div>
</template>
