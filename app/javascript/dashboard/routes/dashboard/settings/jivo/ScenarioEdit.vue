<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import JivoScenarioForm from './components/JivoScenarioForm.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const uiFlags = useMapGetter('jivoScenarios/getUIFlags');

const assistantId = computed(() => Number(route.params.assistantId));
const scenarioId = computed(() =>
  route.params.scenarioId ? Number(route.params.scenarioId) : null
);
const mode = computed(() => (scenarioId.value ? 'edit' : 'create'));

const scenario = computed(() => {
  if (!scenarioId.value) return {};
  return store.getters['jivoScenarios/getScenario'](scenarioId.value) || {};
});

const isReady = ref(false);

const headerTitle = computed(() =>
  mode.value === 'create'
    ? t('JIVO.SCENARIOS.FORM.CREATE_TITLE')
    : t('JIVO.SCENARIOS.FORM.EDIT_TITLE')
);

const goBack = () =>
  router.push({
    name: 'jivo_scenarios',
    params: { assistantId: assistantId.value },
  });

const handleSave = async data => {
  try {
    if (mode.value === 'create') {
      await store.dispatch('jivoScenarios/create', {
        assistantId: assistantId.value,
        ...data,
      });
      useAlert(t('JIVO.SCENARIOS.CREATED'));
    } else {
      await store.dispatch('jivoScenarios/update', {
        assistantId: assistantId.value,
        id: scenarioId.value,
        ...data,
      });
      useAlert(t('JIVO.SCENARIOS.UPDATED'));
    }
    goBack();
  } catch (error) {
    useAlert(error.message || t('JIVO.SCENARIOS.SAVE_FAILED'));
  }
};

onMounted(async () => {
  await store.dispatch('jivoAssistants/get');
  if (mode.value === 'edit') {
    await store.dispatch('jivoScenarios/get', assistantId.value);
  }
  isReady.value = true;
});
</script>

<template>
  <SettingsLayout
    :is-loading="!isReady"
    :loading-message="t('JIVO.SCENARIOS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="headerTitle"
        :description="t('JIVO.SCENARIOS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            icon="i-lucide-arrow-left"
            :label="t('JIVO.SCENARIOS.BACK')"
            slate
            faded
            @click="goBack"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <JivoScenarioForm
        v-if="isReady"
        :mode="mode"
        :scenario="scenario"
        :assistant-id="assistantId"
        :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
        @save="handleSave"
        @close="goBack"
      />
    </template>
  </SettingsLayout>
</template>
