<script setup>
import { computed } from 'vue';

const props = defineProps({
  icon: { type: String, default: '' },
  custom: { type: Boolean, default: false },
});

const iconMap = {
  'note-add': 'i-lucide-notebook-pen',
  'eye-off': 'i-lucide-eye-off',
  'exclamation-triangle': 'i-lucide-triangle-alert',
  tag: 'i-lucide-tag',
  search: 'i-lucide-search',
  'user-switch': 'i-lucide-user-round-cog',
};

const iconClass = computed(() => {
  if (props.custom) return 'i-lucide-wrench';
  return iconMap[props.icon] || 'i-lucide-circle-dot';
});
</script>

<template>
  <span :class="iconClass" class="size-3.5 shrink-0" />
</template>
