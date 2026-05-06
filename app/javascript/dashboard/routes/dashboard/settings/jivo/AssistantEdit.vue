<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
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

const goBack = () => router.push({ name: 'jivo_assistants' });

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
  <SettingsLayout
    :is-loading="!isReady"
    :loading-message="t('JIVO.ASSISTANTS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="headerTitle"
        :description="t('JIVO.ASSISTANTS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            icon="i-lucide-arrow-left"
            :label="t('JIVO.DOCUMENTS.BACK')"
            slate
            faded
            @click="goBack"
          />
        </template>
      </BaseSettingsHeader>
    </template>

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
  </SettingsLayout>
</template>
