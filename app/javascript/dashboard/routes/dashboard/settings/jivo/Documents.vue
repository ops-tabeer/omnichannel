<script setup>
import { ref, computed, nextTick, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import JivoPageLayout from 'dashboard/components-next/jivo/layout/JivoPageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const assistantId = computed(() => Number(route.params.assistantId));

const documents = useMapGetter('jivoDocuments/getDocuments');
const uiFlags = useMapGetter('jivoDocuments/getUIFlags');

const PDF_MAX_BYTES = 10 * 1024 * 1024;

const addDialogRef = ref(null);
const deleteDialogRef = ref(null);
const addMode = ref('url');
const newDocLink = ref('');
const newDocName = ref('');
const newDocFile = ref(null);
const selectedDoc = ref({});
const recrawlingDocId = ref(null);

const resetAddForm = () => {
  newDocLink.value = '';
  newDocName.value = '';
  newDocFile.value = null;
  addMode.value = 'url';
};

const openAddDialog = () => {
  resetAddForm();
  nextTick(() => addDialogRef.value?.open());
};

const handleFileChange = event => {
  const [file] = event.target.files || [];
  newDocFile.value = file || null;
};

const isAddValid = computed(() => {
  if (addMode.value === 'pdf') {
    return (
      !!newDocFile.value &&
      newDocFile.value.size <= PDF_MAX_BYTES &&
      newDocFile.value.type === 'application/pdf'
    );
  }
  return !!newDocLink.value.trim();
});

const submitAdd = async () => {
  if (!isAddValid.value) return;
  try {
    const payload = {
      assistantId: assistantId.value,
      name: newDocName.value.trim(),
    };
    if (addMode.value === 'pdf') {
      payload.file = newDocFile.value;
    } else {
      payload.external_link = newDocLink.value.trim();
    }
    await store.dispatch('jivoDocuments/create', payload);
    useAlert(t('JIVO.DOCUMENTS.ADDED'));
    addDialogRef.value?.close();
  } catch (error) {
    useAlert(error.message || t('JIVO.DOCUMENTS.ADD_FAILED'));
  }
};

const openDeleteDialog = doc => {
  selectedDoc.value = doc;
  nextTick(() => deleteDialogRef.value?.open());
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
  } finally {
    deleteDialogRef.value?.close();
  }
};

const recrawl = async doc => {
  recrawlingDocId.value = doc.id;
  try {
    await store.dispatch('jivoDocuments/recrawl', {
      assistantId: assistantId.value,
      id: doc.id,
    });
    useAlert(t('JIVO.DOCUMENTS.RECRAWL_QUEUED'));
  } catch (error) {
    useAlert(error.message || t('JIVO.DOCUMENTS.RECRAWL_FAILED'));
  } finally {
    recrawlingDocId.value = null;
  }
};

const refresh = () => store.dispatch('jivoDocuments/get', assistantId.value);

watch(assistantId, id => {
  if (id) refresh();
});

onMounted(async () => {
  await store.dispatch('jivoAssistants/get');
  if (assistantId.value) await refresh();
});
</script>

<template>
  <JivoPageLayout
    :header-title="t('JIVO.DOCUMENTS.HEADER')"
    :button-label="t('JIVO.DOCUMENTS.ADD_NEW')"
    :is-fetching="uiFlags.isFetching"
    :is-empty="!documents.length"
    @click="openAddDialog"
  >
    <template #emptyState>
      <div
        class="flex flex-col items-center justify-center py-20 text-n-slate-11"
      >
        <span class="i-lucide-file-text text-3xl mb-2" />
        <p class="text-sm">{{ t('JIVO.DOCUMENTS.EMPTY') }}</p>
      </div>
    </template>

    <template #body>
      <div class="flex flex-col gap-4">
        <div
          v-for="doc in documents"
          :key="doc.id"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg"
        >
          <div class="flex justify-between items-start gap-4">
            <div class="flex-1 min-w-0">
              <h3 class="text-base font-medium text-n-slate-12 truncate">
                {{ doc.name || doc.external_link || doc.file_name }}
              </h3>
              <a
                v-if="doc.external_link"
                :href="doc.external_link"
                target="_blank"
                rel="noopener noreferrer"
                class="text-sm text-n-blue-text hover:underline break-all"
              >
                {{ doc.external_link }}
              </a>
              <span
                v-else-if="doc.file_attached"
                class="text-sm text-n-slate-11 inline-flex items-center gap-1"
              >
                <span class="i-lucide-file-text" />
                {{ doc.file_name }}
              </span>
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
                v-if="doc.external_link"
                icon="i-lucide-refresh-cw"
                slate
                xs
                faded
                :is-loading="recrawlingDocId === doc.id"
                :disabled="
                  doc.status === 'in_progress' || recrawlingDocId === doc.id
                "
                :title="t('JIVO.DOCUMENTS.RECRAWL')"
                @click="recrawl(doc)"
              />
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

      <Dialog
        ref="addDialogRef"
        :title="t('JIVO.DOCUMENTS.FORM.CREATE_TITLE')"
        :show-cancel-button="false"
        :show-confirm-button="false"
      >
        <div class="space-y-3">
          <div class="flex gap-2">
            <Button
              :label="t('JIVO.DOCUMENTS.FORM.MODE_URL')"
              :slate="addMode !== 'url'"
              :faded="addMode !== 'url'"
              xs
              @click="addMode = 'url'"
            />
            <Button
              :label="t('JIVO.DOCUMENTS.FORM.MODE_PDF')"
              :slate="addMode !== 'pdf'"
              :faded="addMode !== 'pdf'"
              xs
              @click="addMode = 'pdf'"
            />
          </div>
          <Input
            v-if="addMode === 'url'"
            v-model="newDocLink"
            :label="t('JIVO.DOCUMENTS.FORM.URL_LABEL')"
            :placeholder="t('JIVO.DOCUMENTS.FORM.URL_PLACEHOLDER')"
          />
          <div v-else>
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ t('JIVO.DOCUMENTS.FORM.PDF_LABEL') }}
            </label>
            <input
              type="file"
              accept="application/pdf"
              class="block w-full text-sm text-n-slate-12 file:mr-3 file:py-2 file:px-3 file:rounded file:border-0 file:bg-n-blue-3 file:text-n-blue-text"
              @change="handleFileChange"
            />
            <p class="text-xs text-n-slate-11 mt-1">
              {{ t('JIVO.DOCUMENTS.FORM.PDF_HELP') }}
            </p>
            <p
              v-if="newDocFile && newDocFile.type !== 'application/pdf'"
              class="text-xs text-n-ruby-text mt-1"
            >
              {{ t('JIVO.DOCUMENTS.FORM.PDF_INVALID') }}
            </p>
            <p
              v-else-if="newDocFile && newDocFile.size > PDF_MAX_BYTES"
              class="text-xs text-n-ruby-text mt-1"
            >
              {{ t('JIVO.DOCUMENTS.FORM.PDF_TOO_LARGE') }}
            </p>
          </div>
          <Input
            v-model="newDocName"
            :label="t('JIVO.DOCUMENTS.FORM.NAME_LABEL')"
            :placeholder="t('JIVO.DOCUMENTS.FORM.NAME_PLACEHOLDER')"
          />
        </div>
        <template #footer>
          <div class="flex justify-end gap-2">
            <Button
              :label="t('JIVO.DOCUMENTS.FORM.CANCEL')"
              slate
              faded
              @click="addDialogRef?.close()"
            />
            <Button
              :label="t('JIVO.DOCUMENTS.FORM.SUBMIT')"
              :is-loading="uiFlags.isCreating"
              :disabled="!isAddValid"
              @click="submitAdd"
            />
          </div>
        </template>
      </Dialog>

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
    </template>
  </JivoPageLayout>
</template>
