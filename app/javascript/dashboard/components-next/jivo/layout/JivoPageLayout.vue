<script setup>
import { ref, computed, watch } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useUISettings } from 'dashboard/composables/useUISettings';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import JivoAssistantSwitcher from './JivoAssistantSwitcher.vue';

defineProps({
  headerTitle: {
    type: String,
    default: '',
  },
  backUrl: {
    type: [String, Object],
    default: '',
  },
  showAssistantSwitcher: {
    type: Boolean,
    default: true,
  },
  buttonLabel: {
    type: String,
    default: '',
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
  isEmpty: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['click']);

const route = useRoute();
const { uiSettings, updateUISettings } = useUISettings();

const showSwitcherDropdown = ref(false);

const assistants = useMapGetter('jivoAssistants/getAssistants');
const uiFlags = useMapGetter('jivoAssistants/getUIFlags');

const currentAssistantId = computed(() => route.params.assistantId);
const isFetchingAssistants = computed(() => uiFlags.value?.isFetching);

const activeAssistantName = computed(
  () =>
    assistants.value?.find(
      assistant => assistant.id === Number(currentAssistantId.value)
    )?.name || ''
);

const toggleSwitcher = () => {
  showSwitcherDropdown.value = !showSwitcherDropdown.value;
};

watch(
  currentAssistantId,
  newAssistantId => {
    if (
      newAssistantId &&
      newAssistantId !==
        String(uiSettings.value?.last_active_jivo_assistant_id || '')
    ) {
      updateUISettings({
        last_active_jivo_assistant_id: Number(newAssistantId),
      });
    }
  },
  { immediate: true }
);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6">
      <div class="w-full max-w-[60rem] mx-auto">
        <div
          class="flex items-start lg:items-center justify-between w-full py-6 lg:py-0 lg:h-20 gap-4 lg:gap-2 flex-col lg:flex-row"
        >
          <div class="flex gap-3 items-center">
            <BackButton v-if="backUrl" :back-url="backUrl" />
            <div v-if="showAssistantSwitcher" class="flex items-center gap-2">
              <span
                v-if="!isFetchingAssistants"
                class="text-xl font-medium truncate text-n-slate-12"
              >
                {{ activeAssistantName }}
              </span>
              <div class="relative group">
                <OnClickOutside @trigger="showSwitcherDropdown = false">
                  <Button
                    icon="i-lucide-chevron-down"
                    variant="ghost"
                    color="slate"
                    size="xs"
                    :disabled="isFetchingAssistants"
                    :is-loading="isFetchingAssistants"
                    class="rounded-md group-hover:bg-n-slate-3 hover:bg-n-slate-3 [&>span]:size-4"
                    @click="toggleSwitcher"
                  />
                  <JivoAssistantSwitcher
                    v-if="showSwitcherDropdown"
                    class="absolute ltr:left-0 rtl:right-0 top-9"
                    @close="showSwitcherDropdown = false"
                  />
                </OnClickOutside>
              </div>
            </div>
            <div v-if="headerTitle" class="flex items-center gap-4">
              <div
                v-if="showAssistantSwitcher"
                class="w-0.5 h-4 rounded-2xl bg-n-weak"
              />
              <span class="text-xl font-medium text-n-slate-12">
                {{ headerTitle }}
              </span>
            </div>
          </div>
          <div class="flex gap-2 items-center">
            <slot name="search" />
            <slot name="actions" />
            <Button
              v-if="buttonLabel"
              :label="buttonLabel"
              icon="i-lucide-plus"
              size="sm"
              @click="$emit('click')"
            />
          </div>
        </div>
        <slot name="subHeader" />
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-[60rem] h-full mx-auto py-4">
        <div
          v-if="isFetching"
          class="flex items-center justify-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>
        <div v-else-if="isEmpty">
          <slot name="emptyState" />
        </div>
        <slot v-else name="body" />
        <!--
          Default slot is mounted regardless of fetching/empty state. Use it
          for elements that must always exist in the DOM (e.g. <Dialog> refs
          that the page opens via a button in the header before any data is
          loaded).
        -->
        <slot />
      </div>
    </main>
  </section>
</template>
