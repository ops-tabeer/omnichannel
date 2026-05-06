<script setup>
import { computed, nextTick, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const VALID_NAVIGATION_PATHS = [
  'jivo_documents',
  'jivo_faqs',
  'jivo_inboxes',
  'jivo_playground',
  'jivo_scenarios',
];

const store = useStore();
const router = useRouter();
const route = useRoute();
const { uiSettings } = useUISettings();

const assistants = computed(
  () => store.getters['jivoAssistants/getAssistants']
);

const isAssistantPresent = assistantId =>
  !!assistants.value.find(a => a.id === Number(assistantId));

const resolveAssistantId = () => {
  const lastActive = uiSettings.value?.last_active_jivo_assistant_id;
  if (isAssistantPresent(lastActive)) return lastActive;
  return assistants.value[0]?.id || null;
};

const dispatchRoute = () => {
  const assistantId = resolveAssistantId();
  if (!assistantId) {
    router.replace({
      name: 'jivo_assistants',
      params: { accountId: route.params.accountId },
    });
    return;
  }

  const requested = route.params.navigationPath;
  const navigateTo = VALID_NAVIGATION_PATHS.includes(requested)
    ? requested
    : 'jivo_documents';

  router.replace({
    name: navigateTo,
    params: { accountId: route.params.accountId, assistantId },
  });
};

onMounted(async () => {
  await store.dispatch('jivoAssistants/get');
  nextTick(dispatchRoute);
});
</script>

<template>
  <div
    class="flex items-center justify-center w-full h-full bg-n-surface-1 text-n-slate-11"
  >
    <Spinner />
  </div>
</template>
