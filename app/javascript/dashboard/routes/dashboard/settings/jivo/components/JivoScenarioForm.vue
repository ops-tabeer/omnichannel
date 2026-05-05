<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  mode: { type: String, default: 'create' },
  scenario: { type: Object, default: () => ({}) },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'close']);
const { t } = useI18n();

const form = ref({
  title: props.scenario.title || '',
  description: props.scenario.description || '',
  instruction: props.scenario.instruction || '',
  enabled: props.scenario.enabled === undefined ? true : props.scenario.enabled,
});

const title = computed(() =>
  props.mode === 'create'
    ? t('JIVO.SCENARIOS.FORM.CREATE_TITLE')
    : t('JIVO.SCENARIOS.FORM.EDIT_TITLE')
);

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
  </div>
</template>
