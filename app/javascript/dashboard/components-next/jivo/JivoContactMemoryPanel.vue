<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  contactId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const store = useStore();

const expanded = ref(false);
const allNotesGetter = useMapGetter('contactNotes/getAllNotesByContactId');
const uiFlags = useMapGetter('contactNotes/getUIFlags');

const notes = computed(() =>
  props.contactId ? allNotesGetter.value(props.contactId) : []
);

const fetchNotes = id => {
  if (!id) return;
  store.dispatch('contactNotes/get', { contactId: Number(id) });
};

onMounted(() => fetchNotes(props.contactId));
watch(
  () => props.contactId,
  newId => fetchNotes(newId)
);

const toggle = () => {
  expanded.value = !expanded.value;
};
</script>

<template>
  <div class="border border-n-weak rounded-md">
    <button
      class="w-full px-3 py-2 flex items-center justify-between text-left hover:bg-n-alpha-black2 transition"
      @click="toggle"
    >
      <span class="flex items-center gap-2 text-sm font-medium text-n-slate-12">
        <span class="i-lucide-notebook-text size-4" />
        {{ t('JIVO.TASKS.CONTACT_MEMORY.TITLE') }}
        <span v-if="notes.length" class="text-xs text-n-slate-11 font-normal">
          ({{ notes.length }})
        </span>
      </span>
      <span
        :class="expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        class="size-4 text-n-slate-11"
      />
    </button>

    <div v-if="expanded" class="px-3 pb-3 space-y-2">
      <p class="text-xs text-n-slate-11">
        {{ t('JIVO.TASKS.CONTACT_MEMORY.HELP') }}
      </p>
      <div
        v-if="uiFlags.isFetching && !notes.length"
        class="text-xs text-n-slate-11 italic"
      >
        {{ t('JIVO.TASKS.CONTACT_MEMORY.LOADING') }}
      </div>
      <div v-else-if="!notes.length" class="text-xs text-n-slate-11 italic">
        {{ t('JIVO.TASKS.CONTACT_MEMORY.EMPTY') }}
      </div>
      <ul v-else class="space-y-1.5">
        <li
          v-for="note in notes"
          :key="note.id"
          class="text-xs text-n-slate-12 bg-n-alpha-black2 border border-n-weak rounded-md px-2 py-1.5 whitespace-pre-line"
        >
          {{ note.content }}
        </li>
      </ul>
    </div>
  </div>
</template>
