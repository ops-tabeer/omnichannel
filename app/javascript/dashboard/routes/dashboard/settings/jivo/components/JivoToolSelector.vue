<script setup>
import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import JivoToolIcon from 'dashboard/components-next/jivo/JivoToolIcon.vue';

const props = defineProps({
  assistantId: { type: [Number, String], required: true },
  modelValue: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
const store = useStore();
const { t } = useI18n();

const assistant = computed(
  () =>
    store.getters['jivoAssistants/getAssistant'](Number(props.assistantId)) ||
    {}
);

const tools = computed(() => assistant.value.available_tools || []);

const builtInTools = computed(() => tools.value.filter(tool => !tool.custom));
const customTools = computed(() => tools.value.filter(tool => tool.custom));

const isSelected = id => props.modelValue.includes(id);

const toggle = id => {
  const next = isSelected(id)
    ? props.modelValue.filter(t2 => t2 !== id)
    : [...props.modelValue, id];
  emit('update:modelValue', next);
};
</script>

<template>
  <div>
    <label class="block text-sm font-medium text-n-slate-12 mb-1">
      {{ t('JIVO.SCENARIOS.FORM.TOOLS.LABEL') }}
    </label>
    <p class="text-xs text-n-slate-11 mb-2">
      {{ t('JIVO.SCENARIOS.FORM.TOOLS.HELP') }}
    </p>
    <div
      v-if="!tools.length"
      class="text-sm text-n-slate-11 italic p-3 border border-n-weak rounded-md"
    >
      {{ t('JIVO.SCENARIOS.FORM.TOOLS.EMPTY') }}
    </div>
    <div v-else class="space-y-3 p-3 border border-n-weak rounded-md">
      <div v-if="builtInTools.length">
        <h5 class="text-xs font-semibold text-n-slate-11 uppercase mb-2">
          {{ t('JIVO.SCENARIOS.FORM.TOOLS.BUILT_IN') }}
        </h5>
        <div class="space-y-2">
          <label
            v-for="tool in builtInTools"
            :key="tool.id"
            class="flex items-start gap-2 cursor-pointer"
          >
            <input
              type="checkbox"
              :checked="isSelected(tool.id)"
              class="mt-0.5"
              @change="toggle(tool.id)"
            />
            <div class="flex-1 min-w-0">
              <div class="text-sm text-n-slate-12 flex items-center gap-1.5">
                <JivoToolIcon :icon="tool.icon" />
                {{ tool.title }}
              </div>
              <div class="text-xs text-n-slate-11">
                {{ tool.description }}
              </div>
            </div>
          </label>
        </div>
      </div>

      <div v-if="customTools.length" class="pt-3 border-t border-n-weak">
        <h5 class="text-xs font-semibold text-n-slate-11 uppercase mb-2">
          {{ t('JIVO.SCENARIOS.FORM.TOOLS.CUSTOM') }}
        </h5>
        <div class="space-y-2">
          <label
            v-for="tool in customTools"
            :key="tool.id"
            class="flex items-start gap-2 cursor-pointer"
          >
            <input
              type="checkbox"
              :checked="isSelected(tool.id)"
              class="mt-0.5"
              @change="toggle(tool.id)"
            />
            <div class="flex-1 min-w-0">
              <div class="text-sm text-n-slate-12 flex items-center gap-1.5">
                <JivoToolIcon custom />
                {{ tool.title }}
              </div>
              <div class="text-xs text-n-slate-11">
                {{ tool.description }}
              </div>
            </div>
          </label>
        </div>
      </div>
    </div>
  </div>
</template>
