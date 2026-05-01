<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import JivoAssistantForm from './components/JivoAssistantForm.vue';
import JivoInboxManager from './components/JivoInboxManager.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const assistants = useMapGetter('jivoAssistants/getAssistants');
const uiFlags = useMapGetter('jivoAssistants/getUIFlags');

const formMode = ref('create');
const selectedAssistant = ref({});
const showForm = ref(false);
const showInboxManager = ref(false);
const deleteDialogRef = ref(null);

const isLoading = computed(() => uiFlags.value.isFetching);

const openCreateForm = () => {
  formMode.value = 'create';
  selectedAssistant.value = {};
  showForm.value = true;
};

const openEditForm = assistant => {
  formMode.value = 'edit';
  selectedAssistant.value = { ...assistant };
  showForm.value = true;
};

const openInboxManager = assistant => {
  selectedAssistant.value = assistant;
  showInboxManager.value = true;
};

const openDeleteDialog = assistant => {
  selectedAssistant.value = assistant;
  deleteDialogRef.value.open();
};

const goToDocuments = assistant => {
  router.push({
    name: 'jivo_documents',
    params: { assistantId: assistant.id },
  });
};

const goToFaqs = assistant => {
  router.push({ name: 'jivo_faqs', params: { assistantId: assistant.id } });
};

const handleSave = async data => {
  try {
    if (formMode.value === 'create') {
      await store.dispatch('jivoAssistants/create', data);
      useAlert('JIVO Assistant created successfully');
    } else {
      await store.dispatch('jivoAssistants/update', {
        id: selectedAssistant.value.id,
        ...data,
      });
      useAlert('JIVO Assistant updated successfully');
    }
    showForm.value = false;
  } catch (error) {
    useAlert(error.message || 'Failed to save assistant');
  }
};

const confirmDelete = async () => {
  try {
    await store.dispatch('jivoAssistants/delete', selectedAssistant.value.id);
    useAlert('JIVO Assistant deleted');
  } catch (error) {
    useAlert(error.message || 'Failed to delete assistant');
  }
};

onMounted(() => {
  store.dispatch('jivoAssistants/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="t('JIVO.ASSISTANTS.LOADING')"
    :no-records-found="!assistants.length"
    :no-records-message="t('JIVO.ASSISTANTS.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('JIVO.ASSISTANTS.TITLE')"
        :description="t('JIVO.ASSISTANTS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            icon="i-lucide-circle-plus"
            :label="t('JIVO.ASSISTANTS.NEW')"
            @click="openCreateForm"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="space-y-4">
        <div
          v-for="assistant in assistants"
          :key="assistant.id"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg"
        >
          <div class="flex justify-between items-start gap-4">
            <div class="flex-1">
              <h3 class="text-base font-medium text-n-slate-12">
                {{ assistant.name }}
              </h3>
              <p class="text-sm text-n-slate-11 mt-1">
                {{ assistant.description }}
              </p>
              <div class="flex flex-wrap gap-2 mt-3">
                <span
                  v-for="inbox in assistant.inboxes"
                  :key="inbox.id"
                  class="text-xs bg-n-blue-3 text-n-blue-text px-2 py-1 rounded"
                >
                  {{ inbox.name }}
                </span>
                <span
                  v-if="!assistant.inboxes || !assistant.inboxes.length"
                  class="text-xs text-n-slate-11"
                >
                  {{ t('JIVO.ASSISTANTS.NO_INBOXES') }}
                </span>
              </div>
            </div>
            <div class="flex gap-2 shrink-0">
              <Button
                :label="t('JIVO.ASSISTANTS.DOCUMENTS')"
                icon="i-lucide-file-text"
                slate
                xs
                faded
                @click="goToDocuments(assistant)"
              />
              <Button
                :label="t('JIVO.ASSISTANTS.FAQS')"
                icon="i-lucide-message-circle-question"
                slate
                xs
                faded
                @click="goToFaqs(assistant)"
              />
              <Button
                :label="t('JIVO.ASSISTANTS.INBOXES')"
                icon="i-lucide-inbox"
                slate
                xs
                faded
                @click="openInboxManager(assistant)"
              />
              <Button
                icon="i-lucide-pen"
                slate
                xs
                faded
                @click="openEditForm(assistant)"
              />
              <Button
                icon="i-lucide-trash-2"
                ruby
                xs
                faded
                @click="openDeleteDialog(assistant)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>

    <JivoAssistantForm
      v-if="showForm"
      :mode="formMode"
      :assistant="selectedAssistant"
      :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
      @save="handleSave"
      @close="showForm = false"
    />

    <JivoInboxManager
      v-if="showInboxManager"
      :assistant="selectedAssistant"
      @close="showInboxManager = false"
    />

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('JIVO.ASSISTANTS.DELETE.TITLE')"
      :description="
        t('JIVO.ASSISTANTS.DELETE.DESCRIPTION', {
          name: selectedAssistant.name,
        })
      "
      :is-loading="uiFlags.isDeleting"
      :confirm-button-label="t('JIVO.ASSISTANTS.DELETE.CONFIRM')"
      :cancel-button-label="t('JIVO.ASSISTANTS.DELETE.CANCEL')"
      @confirm="confirmDelete"
    />
  </SettingsLayout>
</template>
