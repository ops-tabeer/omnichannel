<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  faq: {
    type: Object,
    required: true,
  },
  selected: {
    type: Boolean,
    default: false,
  },
  selectionActive: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'approve',
  'delete',
  'edit',
  'reject',
  'toggleSelection',
]);

const { t } = useI18n();
const isHovered = ref(false);

const statusLabel = computed(() =>
  props.faq.status === 'approved'
    ? t('JIVO.FAQS.STATUS.APPROVED')
    : t('JIVO.FAQS.STATUS.PENDING')
);

const showCheckbox = computed(
  () => props.selected || props.selectionActive || isHovered.value
);

const showActions = computed(() => !props.selected);

const onCheckboxChange = () => emit('toggleSelection', props.faq.id);
</script>

<template>
  <div
    class="group p-4 bg-n-solid-1 border rounded-xl transition-colors"
    :class="
      selected
        ? 'border-n-brand bg-n-brand/5'
        : 'border-n-weak hover:border-n-slate-6'
    "
    @mouseenter="isHovered = true"
    @mouseleave="isHovered = false"
  >
    <div class="flex items-start gap-3">
      <div class="pt-1 w-5 shrink-0">
        <input
          v-if="showCheckbox"
          type="checkbox"
          :checked="selected"
          :disabled="disabled"
          :aria-label="t('JIVO.FAQS.SELECT_ROW')"
          @change="onCheckboxChange"
        />
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <h3 class="text-base font-medium text-n-slate-12 break-words">
            {{ faq.question }}
          </h3>
          <span
            class="text-xs font-medium px-2 py-0.5 rounded-full"
            :class="
              faq.status === 'approved'
                ? 'bg-n-teal-3 text-n-teal-text'
                : 'bg-n-amber-3 text-n-amber-text'
            "
          >
            {{ statusLabel }}
          </span>
          <span
            v-if="faq.documentable_type"
            class="text-xs text-n-slate-11 italic"
          >
            {{ t('JIVO.FAQS.AUTO_GENERATED') }}
          </span>
        </div>
        <p class="text-sm text-n-slate-11 mt-2 whitespace-pre-line break-words">
          {{ faq.answer }}
        </p>
      </div>

      <div
        v-if="showActions"
        class="flex gap-1 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity"
      >
        <Button
          v-if="faq.status === 'pending'"
          icon="i-lucide-check"
          teal
          xs
          faded
          :title="t('JIVO.FAQS.APPROVE')"
          @click="emit('approve', faq)"
        />
        <Button
          v-if="faq.status === 'pending'"
          icon="i-lucide-x"
          ruby
          xs
          faded
          :title="t('JIVO.FAQS.REJECT')"
          @click="emit('reject', faq)"
        />
        <Button
          icon="i-lucide-pen"
          slate
          xs
          faded
          :title="t('JIVO.FAQS.EDIT')"
          @click="emit('edit', faq)"
        />
        <Button
          icon="i-lucide-trash-2"
          ruby
          xs
          faded
          :title="t('JIVO.FAQS.DELETE_ACTION')"
          @click="emit('delete', faq)"
        />
      </div>
    </div>
  </div>
</template>
