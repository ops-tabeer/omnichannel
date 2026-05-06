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
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import JivoInboxManager from './components/JivoInboxManager.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const assistants = useMapGetter('jivoAssistants/getAssistants');
const uiFlags = useMapGetter('jivoAssistants/getUIFlags');
const currentAccountId = useMapGetter('getCurrentAccountId');
const accountsGetter = useMapGetter('accounts/getAccount');
const currentAccount = computed(() =>
  accountsGetter.value(currentAccountId.value)
);
const updateAccountV2Override = async value => {
  try {
    await store.dispatch('accounts/update', { jivo_v2_agent: value });
    useAlert(
      value
        ? t('JIVO.ASSISTANTS.ACCOUNT_V2_OVERRIDE.ENABLED')
        : t('JIVO.ASSISTANTS.ACCOUNT_V2_OVERRIDE.DISABLED')
    );
  } catch (error) {
    useAlert(error.message || t('JIVO.ASSISTANTS.ACCOUNT_V2_OVERRIDE.ERROR'));
  }
};

const accountV2Override = computed({
  get: () => Boolean(currentAccount.value?.settings?.jivo_v2_agent),
  set: value => updateAccountV2Override(value),
});

const selectedAssistant = ref({});
const showInboxManager = ref(false);
const deleteDialogRef = ref(null);

const isLoading = computed(() => uiFlags.value.isFetching);

const openCreateForm = () => {
  router.push({ name: 'jivo_assistant_new' });
};

const openEditForm = assistant => {
  router.push({
    name: 'jivo_assistant_edit',
    params: { assistantId: assistant.id },
  });
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

const goToScenarios = assistant => {
  router.push({
    name: 'jivo_scenarios',
    params: { assistantId: assistant.id },
  });
};

const goToPlayground = assistant => {
  router.push({
    name: 'jivo_playground',
    params: { assistantId: assistant.id },
  });
};

const goToCustomTools = () => {
  router.push({ name: 'jivo_custom_tools' });
};

const confirmDelete = async () => {
  try {
    await store.dispatch('jivoAssistants/delete', selectedAssistant.value.id);
    useAlert('JIVO Assistant deleted');
  } catch (error) {
    useAlert(error.message || 'Failed to delete assistant');
  } finally {
    deleteDialogRef.value?.close();
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
            icon="i-lucide-wrench"
            :label="t('JIVO.ASSISTANTS.CUSTOM_TOOLS')"
            slate
            faded
            @click="goToCustomTools"
          />
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
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg flex items-center justify-between gap-4"
        >
          <div>
            <h4 class="text-sm font-medium text-n-slate-12">
              {{ t('JIVO.ASSISTANTS.ACCOUNT_V2_OVERRIDE.LABEL') }}
            </h4>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{ t('JIVO.ASSISTANTS.ACCOUNT_V2_OVERRIDE.HELP') }}
            </p>
          </div>
          <ToggleSwitch v-model="accountV2Override" />
        </div>
        <div
          v-for="assistant in assistants"
          :key="assistant.id"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg"
        >
          <div class="flex justify-between items-start gap-4">
            <div
              class="w-10 h-10 rounded-full bg-n-alpha-black2 border border-n-weak overflow-hidden flex items-center justify-center shrink-0"
            >
              <img
                v-if="assistant.avatar_url"
                :src="assistant.avatar_url"
                :alt="assistant.name"
                class="w-full h-full object-cover"
              />
              <span
                v-else
                class="i-lucide-sparkles text-base text-n-slate-11"
              />
            </div>
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
                :label="t('JIVO.ASSISTANTS.SCENARIOS')"
                icon="i-lucide-route"
                slate
                xs
                faded
                @click="goToScenarios(assistant)"
              />
              <Button
                :label="t('JIVO.ASSISTANTS.PLAYGROUND')"
                icon="i-lucide-message-square-text"
                slate
                xs
                faded
                @click="goToPlayground(assistant)"
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
