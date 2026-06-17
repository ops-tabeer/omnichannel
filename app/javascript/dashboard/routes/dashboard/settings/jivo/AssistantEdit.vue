<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import JivoPageLayout from 'dashboard/components-next/jivo/layout/JivoPageLayout.vue';
import JivoAssistantForm from './components/JivoAssistantForm.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const uiFlags = useMapGetter('jivoAssistants/getUIFlags');

const mode = computed(() => (route.params.assistantId ? 'edit' : 'create'));

const assistantId = computed(() =>
  route.params.assistantId ? Number(route.params.assistantId) : null
);

const assistant = computed(() => {
  if (!assistantId.value) return {};
  return store.getters['jivoAssistants/getAssistant'](assistantId.value) || {};
});

const isReady = ref(false);

const headerTitle = computed(() =>
  mode.value === 'create'
    ? t('JIVO.ASSISTANTS.FORM.CREATE_TITLE')
    : t('JIVO.ASSISTANTS.FORM.EDIT_TITLE')
);

const backRoute = computed(() => ({ name: 'jivo_assistants' }));

const goBack = () => router.push(backRoute.value);

const handleSave = async data => {
  try {
    if (mode.value === 'create') {
      await store.dispatch('jivoAssistants/create', data);
      useAlert(t('JIVO.ASSISTANTS.CREATED', 'JIVO Assistant created'));
    } else {
      await store.dispatch('jivoAssistants/update', {
        id: assistantId.value,
        ...data,
      });
      useAlert(t('JIVO.ASSISTANTS.UPDATED', 'JIVO Assistant updated'));
    }
    goBack();
  } catch (error) {
    useAlert(error.message || t('JIVO.ASSISTANTS.SAVE_FAILED', 'Save failed'));
  }
};

onMounted(async () => {
  if (mode.value === 'edit') {
    await store.dispatch('jivoAssistants/get');
  }
  isReady.value = true;
});
</script>

<template>
  <JivoPageLayout
    :header-title="headerTitle"
    :show-assistant-switcher="false"
    :back-url="backRoute"
    :is-fetching="!isReady"
  >
    <template #body>
      <JivoAssistantForm
        v-if="isReady"
        :mode="mode"
        :assistant="assistant"
        :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
        @save="handleSave"
        @close="goBack"
      />
    </template>
  </JivoPageLayout>
</template>
