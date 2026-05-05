<script setup>
import { ref, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import JivoCustomToolForm from './components/JivoCustomToolForm.vue';

const store = useStore();
const { t } = useI18n();

const customTools = useMapGetter('jivoCustomTools/getCustomTools');
const uiFlags = useMapGetter('jivoCustomTools/getUIFlags');

const formMode = ref('create');
const selectedTool = ref({});
const showForm = ref(false);
const deleteDialogRef = ref(null);

const openCreate = () => {
  formMode.value = 'create';
  selectedTool.value = {};
  showForm.value = true;
};

const openEdit = tool => {
  formMode.value = 'edit';
  selectedTool.value = tool;
  showForm.value = true;
};

const openDelete = tool => {
  selectedTool.value = tool;
  deleteDialogRef.value.open();
};

const handleSave = async data => {
  try {
    if (formMode.value === 'create') {
      await store.dispatch('jivoCustomTools/create', data);
      useAlert(t('JIVO.CUSTOM_TOOLS.CREATED'));
    } else {
      await store.dispatch('jivoCustomTools/update', {
        id: selectedTool.value.id,
        ...data,
      });
      useAlert(t('JIVO.CUSTOM_TOOLS.UPDATED'));
    }
    showForm.value = false;
  } catch (error) {
    useAlert(error.message || t('JIVO.CUSTOM_TOOLS.SAVE_FAILED'));
  }
};

const confirmDelete = async () => {
  try {
    await store.dispatch('jivoCustomTools/delete', selectedTool.value.id);
    useAlert(t('JIVO.CUSTOM_TOOLS.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JIVO.CUSTOM_TOOLS.DELETE_FAILED'));
  }
};

const refresh = () => store.dispatch('jivoCustomTools/get');

onMounted(refresh);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('JIVO.CUSTOM_TOOLS.LOADING')"
    :no-records-found="!customTools.length"
    :no-records-message="t('JIVO.CUSTOM_TOOLS.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('JIVO.CUSTOM_TOOLS.TITLE')"
        :description="t('JIVO.CUSTOM_TOOLS.DESCRIPTION')"
      >
        <template #actions>
          <Button icon="i-lucide-refresh-cw" slate faded @click="refresh" />
          <Button
            icon="i-lucide-circle-plus"
            :label="t('JIVO.CUSTOM_TOOLS.NEW')"
            @click="openCreate"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="space-y-3">
        <div
          v-for="tool in customTools"
          :key="tool.id"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg"
        >
          <div class="flex justify-between items-start gap-4">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <h3 class="text-base font-medium text-n-slate-12">
                  {{ tool.title }}
                </h3>
                <span
                  class="text-xs bg-n-alpha-black2 text-n-slate-11 px-2 py-0.5 rounded font-mono"
                >
                  {{ tool.slug }}
                </span>
                <span
                  v-if="!tool.enabled"
                  class="text-xs px-2 py-0.5 rounded bg-n-amber-3 text-n-amber-text"
                >
                  {{ t('JIVO.CUSTOM_TOOLS.DISABLED') }}
                </span>
              </div>
              <p class="text-sm text-n-slate-11 mt-1">
                {{ tool.description }}
              </p>
              <div class="flex flex-wrap gap-2 mt-2 text-xs text-n-slate-11">
                <span class="font-mono">{{ tool.http_method }}</span>
                <span class="break-all">{{ tool.endpoint_url }}</span>
                <span class="font-mono">
                  {{ t('JIVO.CUSTOM_TOOLS.AUTH_LABEL') }} {{ tool.auth_type }}
                </span>
              </div>
            </div>
            <div class="flex gap-2 shrink-0">
              <Button
                icon="i-lucide-pen"
                slate
                xs
                faded
                @click="openEdit(tool)"
              />
              <Button
                icon="i-lucide-trash-2"
                ruby
                xs
                faded
                @click="openDelete(tool)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>

    <JivoCustomToolForm
      v-if="showForm"
      :mode="formMode"
      :custom-tool="selectedTool"
      :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
      @save="handleSave"
      @close="showForm = false"
    />

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('JIVO.CUSTOM_TOOLS.DELETE.TITLE')"
      :description="
        t('JIVO.CUSTOM_TOOLS.DELETE.DESCRIPTION', {
          title: selectedTool.title || '',
        })
      "
      :is-loading="uiFlags.isDeleting"
      :confirm-button-label="t('JIVO.CUSTOM_TOOLS.DELETE.CONFIRM')"
      :cancel-button-label="t('JIVO.CUSTOM_TOOLS.DELETE.CANCEL')"
      @confirm="confirmDelete"
    />
  </SettingsLayout>
</template>
