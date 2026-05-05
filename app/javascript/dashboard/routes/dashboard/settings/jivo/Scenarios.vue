<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import JivoScenarioForm from './components/JivoScenarioForm.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const assistantId = computed(() => Number(route.params.assistantId));
const scenarios = useMapGetter('jivoScenarios/getScenarios');
const uiFlags = useMapGetter('jivoScenarios/getUIFlags');
const assistant = computed(() =>
  store.getters['jivoAssistants/getAssistant'](assistantId.value)
);

const formMode = ref('create');
const selectedScenario = ref({});
const showForm = ref(false);
const deleteDialogRef = ref(null);

const openCreate = () => {
  formMode.value = 'create';
  selectedScenario.value = {};
  showForm.value = true;
};

const openEdit = scenario => {
  formMode.value = 'edit';
  selectedScenario.value = scenario;
  showForm.value = true;
};

const openDelete = scenario => {
  selectedScenario.value = scenario;
  deleteDialogRef.value.open();
};

const handleSave = async data => {
  try {
    if (formMode.value === 'create') {
      await store.dispatch('jivoScenarios/create', {
        assistantId: assistantId.value,
        ...data,
      });
      useAlert(t('JIVO.SCENARIOS.CREATED'));
    } else {
      await store.dispatch('jivoScenarios/update', {
        assistantId: assistantId.value,
        id: selectedScenario.value.id,
        ...data,
      });
      useAlert(t('JIVO.SCENARIOS.UPDATED'));
    }
    showForm.value = false;
  } catch (error) {
    useAlert(error.message || t('JIVO.SCENARIOS.SAVE_FAILED'));
  }
};

const confirmDelete = async () => {
  try {
    await store.dispatch('jivoScenarios/delete', {
      assistantId: assistantId.value,
      id: selectedScenario.value.id,
    });
    useAlert(t('JIVO.SCENARIOS.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JIVO.SCENARIOS.DELETE_FAILED'));
  }
};

const goBack = () => router.push({ name: 'jivo_assistants' });

const refresh = () => store.dispatch('jivoScenarios/get', assistantId.value);

onMounted(async () => {
  await store.dispatch('jivoAssistants/get');
  await refresh();
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('JIVO.SCENARIOS.LOADING')"
    :no-records-found="!scenarios.length"
    :no-records-message="t('JIVO.SCENARIOS.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('JIVO.SCENARIOS.TITLE', { name: assistant.name || '' })"
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
          <Button icon="i-lucide-refresh-cw" slate faded @click="refresh" />
          <Button
            icon="i-lucide-circle-plus"
            :label="t('JIVO.SCENARIOS.NEW')"
            @click="openCreate"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="space-y-3">
        <div
          v-for="scenario in scenarios"
          :key="scenario.id"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg"
        >
          <div class="flex justify-between items-start gap-4">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <h3 class="text-base font-medium text-n-slate-12">
                  {{ scenario.title }}
                </h3>
                <span
                  v-if="!scenario.enabled"
                  class="text-xs px-2 py-0.5 rounded bg-n-amber-3 text-n-amber-text"
                >
                  {{ t('JIVO.SCENARIOS.DISABLED') }}
                </span>
              </div>
              <p class="text-sm text-n-slate-11 mt-1">
                {{ scenario.description }}
              </p>
              <div
                v-if="scenario.tools && scenario.tools.length"
                class="flex flex-wrap gap-1 mt-2"
              >
                <span
                  v-for="tool in scenario.tools"
                  :key="tool"
                  class="text-xs bg-n-blue-3 text-n-blue-text px-2 py-0.5 rounded font-mono"
                >
                  {{ tool }}
                </span>
              </div>
            </div>
            <div class="flex gap-2 shrink-0">
              <Button
                icon="i-lucide-pen"
                slate
                xs
                faded
                @click="openEdit(scenario)"
              />
              <Button
                icon="i-lucide-trash-2"
                ruby
                xs
                faded
                @click="openDelete(scenario)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>

    <JivoScenarioForm
      v-if="showForm"
      :mode="formMode"
      :scenario="selectedScenario"
      :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
      @save="handleSave"
      @close="showForm = false"
    />

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('JIVO.SCENARIOS.DELETE.TITLE')"
      :description="
        t('JIVO.SCENARIOS.DELETE.DESCRIPTION', {
          title: selectedScenario.title || '',
        })
      "
      :is-loading="uiFlags.isDeleting"
      :confirm-button-label="t('JIVO.SCENARIOS.DELETE.CONFIRM')"
      :cancel-button-label="t('JIVO.SCENARIOS.DELETE.CANCEL')"
      @confirm="confirmDelete"
    />
  </SettingsLayout>
</template>
