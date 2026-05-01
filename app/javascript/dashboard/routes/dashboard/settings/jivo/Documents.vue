<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const assistantId = computed(() => Number(route.params.assistantId));

const documents = useMapGetter('jivoDocuments/getDocuments');
const uiFlags = useMapGetter('jivoDocuments/getUIFlags');
const assistant = computed(() =>
  store.getters['jivoAssistants/getAssistant'](assistantId.value)
);

const showAddForm = ref(false);
const newDocLink = ref('');
const newDocName = ref('');
const deleteDialogRef = ref(null);
const selectedDoc = ref({});

const openAddForm = () => {
  newDocLink.value = '';
  newDocName.value = '';
  showAddForm.value = true;
};

const submitAdd = async () => {
  if (!newDocLink.value.trim()) return;
  try {
    await store.dispatch('jivoDocuments/create', {
      assistantId: assistantId.value,
      external_link: newDocLink.value.trim(),
      name: newDocName.value.trim(),
    });
    useAlert(t('JIVO.DOCUMENTS.ADDED'));
    showAddForm.value = false;
  } catch (error) {
    useAlert(error.message || t('JIVO.DOCUMENTS.ADD_FAILED'));
  }
};

const openDeleteDialog = doc => {
  selectedDoc.value = doc;
  deleteDialogRef.value.open();
};

const confirmDelete = async () => {
  try {
    await store.dispatch('jivoDocuments/delete', {
      assistantId: assistantId.value,
      id: selectedDoc.value.id,
    });
    useAlert(t('JIVO.DOCUMENTS.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JIVO.DOCUMENTS.DELETE_FAILED'));
  }
};

const goBack = () => router.push({ name: 'jivo_assistants' });

const refresh = () => store.dispatch('jivoDocuments/get', assistantId.value);

onMounted(async () => {
  await store.dispatch('jivoAssistants/get');
  await refresh();
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('JIVO.DOCUMENTS.LOADING')"
    :no-records-found="!documents.length && !showAddForm"
    :no-records-message="t('JIVO.DOCUMENTS.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('JIVO.DOCUMENTS.TITLE', { name: assistant.name || '' })"
        :description="t('JIVO.DOCUMENTS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            icon="i-lucide-arrow-left"
            :label="t('JIVO.DOCUMENTS.BACK')"
            slate
            faded
            @click="goBack"
          />
          <Button icon="i-lucide-refresh-cw" slate faded @click="refresh" />
          <Button
            icon="i-lucide-circle-plus"
            :label="t('JIVO.DOCUMENTS.ADD')"
            @click="openAddForm"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="space-y-3">
        <div
          v-if="showAddForm"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg space-y-3"
        >
          <Input
            v-model="newDocLink"
            :label="t('JIVO.DOCUMENTS.FORM.URL_LABEL')"
            :placeholder="t('JIVO.DOCUMENTS.FORM.URL_PLACEHOLDER')"
          />
          <Input
            v-model="newDocName"
            :label="t('JIVO.DOCUMENTS.FORM.NAME_LABEL')"
            :placeholder="t('JIVO.DOCUMENTS.FORM.NAME_PLACEHOLDER')"
          />
          <div class="flex justify-end gap-2">
            <Button
              :label="t('JIVO.DOCUMENTS.FORM.CANCEL')"
              slate
              faded
              @click="showAddForm = false"
            />
            <Button
              :label="t('JIVO.DOCUMENTS.FORM.SUBMIT')"
              :is-loading="uiFlags.isCreating"
              :disabled="!newDocLink.trim()"
              @click="submitAdd"
            />
          </div>
        </div>

        <div
          v-for="doc in documents"
          :key="doc.id"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg"
        >
          <div class="flex justify-between items-start gap-4">
            <div class="flex-1 min-w-0">
              <h3 class="text-base font-medium text-n-slate-12 truncate">
                {{ doc.name || doc.external_link }}
              </h3>
              <a
                :href="doc.external_link"
                target="_blank"
                rel="noopener noreferrer"
                class="text-sm text-n-blue-text hover:underline break-all"
              >
                {{ doc.external_link }}
              </a>
              <div class="flex flex-wrap gap-2 mt-2">
                <span
                  class="text-xs px-2 py-1 rounded"
                  :class="
                    doc.status === 'available'
                      ? 'bg-n-teal-3 text-n-teal-text'
                      : 'bg-n-amber-3 text-n-amber-text'
                  "
                >
                  {{ doc.status }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{
                    t('JIVO.DOCUMENTS.RESPONSES_COUNT', {
                      count: doc.responses_count,
                    })
                  }}
                </span>
              </div>
            </div>
            <div class="flex gap-2 shrink-0">
              <Button
                icon="i-lucide-trash-2"
                ruby
                xs
                faded
                @click="openDeleteDialog(doc)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('JIVO.DOCUMENTS.DELETE.TITLE')"
      :description="t('JIVO.DOCUMENTS.DELETE.DESCRIPTION')"
      :is-loading="uiFlags.isDeleting"
      :confirm-button-label="t('JIVO.DOCUMENTS.DELETE.CONFIRM')"
      :cancel-button-label="t('JIVO.DOCUMENTS.DELETE.CANCEL')"
      @confirm="confirmDelete"
    />
  </SettingsLayout>
</template>
