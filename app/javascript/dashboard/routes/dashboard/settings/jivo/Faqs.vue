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
import JivoFaqApprovalRow from './components/JivoFaqApprovalRow.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const assistantId = computed(() => Number(route.params.assistantId));

const responses = useMapGetter('jivoResponses/getResponses');
const uiFlags = useMapGetter('jivoResponses/getUIFlags');

const formDialogRef = ref(null);
const confirmDialogRef = ref(null);

const formMode = ref('create');
const formData = ref({ id: null, question: '', answer: '' });
const selectedIds = ref([]);
const statusFilter = ref('pending');
const searchQuery = ref('');
const pendingAction = ref(null);

const statusOptions = computed(() => [
  { value: 'pending', label: t('JIVO.FAQS.FILTERS.PENDING') },
  { value: 'approved', label: t('JIVO.FAQS.FILTERS.APPROVED') },
  { value: 'all', label: t('JIVO.FAQS.FILTERS.ALL') },
]);

const selectedCount = computed(() => selectedIds.value.length);
const selectionActive = computed(() => selectedCount.value > 0);
const visibleIds = computed(() => responses.value.map(faq => faq.id));
const allRowsSelected = computed(
  () =>
    visibleIds.value.length > 0 &&
    visibleIds.value.every(id => selectedIds.value.includes(id))
);

const emptyMessage = computed(() => {
  if (searchQuery.value.trim()) return t('JIVO.FAQS.EMPTY_SEARCH');
  if (statusFilter.value === 'pending') return t('JIVO.FAQS.EMPTY_PENDING');
  return t('JIVO.FAQS.EMPTY');
});

const searchPlaceholder = computed(() =>
  statusFilter.value === 'pending'
    ? t('JIVO.FAQS.SEARCH.PENDING_PLACEHOLDER')
    : t('JIVO.FAQS.SEARCH.PLACEHOLDER')
);

const confirmDialogProps = computed(() => {
  if (!pendingAction.value) {
    return { type: 'alert', title: '', description: '', confirmLabel: '' };
  }
  const { kind, count } = pendingAction.value;
  const ctx = { count };
  const copy = {
    approve: {
      title: t('JIVO.FAQS.CONFIRM.APPROVE.TITLE', ctx),
      description: t('JIVO.FAQS.CONFIRM.APPROVE.DESCRIPTION', ctx),
      confirmLabel: t('JIVO.FAQS.CONFIRM.APPROVE.CONFIRM'),
    },
    reject: {
      title: t('JIVO.FAQS.CONFIRM.REJECT.TITLE', ctx),
      description: t('JIVO.FAQS.CONFIRM.REJECT.DESCRIPTION', ctx),
      confirmLabel: t('JIVO.FAQS.CONFIRM.REJECT.CONFIRM'),
    },
    delete: {
      title: t('JIVO.FAQS.CONFIRM.DELETE.TITLE', ctx),
      description: t('JIVO.FAQS.CONFIRM.DELETE.DESCRIPTION', ctx),
      confirmLabel: t('JIVO.FAQS.CONFIRM.DELETE.CONFIRM'),
    },
  }[kind];

  return {
    type: kind === 'approve' ? 'edit' : 'alert',
    title: copy.title,
    description: copy.description,
    confirmLabel: copy.confirmLabel,
  };
});

const isConfirming = computed(
  () =>
    uiFlags.value.isBulkUpdating ||
    uiFlags.value.isDeleting ||
    uiFlags.value.isUpdating
);

const refresh = async () => {
  try {
    selectedIds.value = [];
    await store.dispatch('jivoResponses/get', {
      assistantId: assistantId.value,
      status: statusFilter.value === 'all' ? undefined : statusFilter.value,
      query: searchQuery.value.trim() || undefined,
    });
  } catch (error) {
    useAlert(error.message || t('JIVO.FAQS.LOAD_FAILED'));
  }
};

const openCreateForm = () => {
  formMode.value = 'create';
  formData.value = { id: null, question: '', answer: '' };
  nextTick(() => formDialogRef.value?.open());
};

const openEditForm = faq => {
  formMode.value = 'edit';
  formData.value = { id: faq.id, question: faq.question, answer: faq.answer };
  nextTick(() => formDialogRef.value?.open());
};

const submit = async () => {
  if (!formData.value.question.trim() || !formData.value.answer.trim()) return;
  try {
    if (formMode.value === 'create') {
      await store.dispatch('jivoResponses/create', {
        assistantId: assistantId.value,
        question: formData.value.question.trim(),
        answer: formData.value.answer.trim(),
      });
      useAlert(t('JIVO.FAQS.CREATED'));
    } else {
      await store.dispatch('jivoResponses/update', {
        assistantId: assistantId.value,
        id: formData.value.id,
        question: formData.value.question.trim(),
        answer: formData.value.answer.trim(),
      });
      useAlert(t('JIVO.FAQS.UPDATED'));
    }
    formDialogRef.value?.close();
  } catch (error) {
    useAlert(error.message || t('JIVO.FAQS.SAVE_FAILED'));
  }
};

const requestConfirm = (kind, ids) => {
  if (!ids.length) return;
  pendingAction.value = { kind, ids, count: ids.length };
  nextTick(() => confirmDialogRef.value?.open());
};

const approveFaq = faq => requestConfirm('approve', [faq.id]);
const rejectFaq = faq => requestConfirm('reject', [faq.id]);
const deleteFaq = faq => requestConfirm('delete', [faq.id]);

const bulkApprove = () => requestConfirm('approve', selectedIds.value);
const bulkReject = () => requestConfirm('reject', selectedIds.value);
const bulkDelete = () => requestConfirm('delete', selectedIds.value);

const handleConfirm = async () => {
  if (!pendingAction.value) return;
  const { kind, ids } = pendingAction.value;
  const actionMap = {
    approve: 'bulkApprove',
    reject: 'bulkReject',
    delete: 'bulkDelete',
  };
  try {
    await store.dispatch(`jivoResponses/${actionMap[kind]}`, {
      assistantId: assistantId.value,
      ids,
    });
    await refresh();
    if (kind === 'approve') useAlert(t('JIVO.FAQS.BULK.APPROVED'));
    else if (kind === 'reject') useAlert(t('JIVO.FAQS.BULK.REJECTED'));
    else useAlert(t('JIVO.FAQS.BULK.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JIVO.FAQS.BULK.FAILED'));
  } finally {
    confirmDialogRef.value?.close();
    pendingAction.value = null;
  }
};

const toggleSelection = id => {
  selectedIds.value = selectedIds.value.includes(id)
    ? selectedIds.value.filter(selectedId => selectedId !== id)
    : [...selectedIds.value, id];
};

const toggleSelectAll = () => {
  selectedIds.value = allRowsSelected.value ? [] : visibleIds.value;
};

const clearSelection = () => {
  selectedIds.value = [];
};

const onStatusFilterChange = () => refresh();

let searchTimer;
const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(refresh, 400);
};

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
    :header-title="t('JIVO.FAQS.HEADER')"
    :button-label="t('JIVO.FAQS.ADD_NEW')"
    :is-fetching="uiFlags.isFetching"
    :is-empty="!responses.length"
    @click="openCreateForm"
  >
    <template #search>
      <Input
        v-model="searchQuery"
        :placeholder="searchPlaceholder"
        class="w-64"
        size="sm"
        type="search"
        @input="onSearchInput"
      />
    </template>

    <template #subHeader>
      <div class="flex flex-wrap items-center justify-between gap-3 pb-3">
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          {{ t('JIVO.FAQS.FILTERS.STATUS_LABEL') }}
          <select
            v-model="statusFilter"
            class="rounded-md border border-n-weak bg-n-alpha-black2 px-3 py-1.5 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="onStatusFilterChange"
          >
            <option
              v-for="option in statusOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </label>

        <label
          v-if="responses.length"
          class="flex items-center gap-2 text-sm text-n-slate-11 cursor-pointer"
        >
          <input
            type="checkbox"
            :checked="allRowsSelected"
            :aria-label="t('JIVO.FAQS.SELECT_ALL')"
            @change="toggleSelectAll"
          />
          {{ t('JIVO.FAQS.SELECT_ALL') }}
        </label>
      </div>

      <Transition
        enter-active-class="transition-all duration-150"
        enter-from-class="opacity-0 -translate-y-1"
        leave-active-class="transition-all duration-100"
        leave-to-class="opacity-0 -translate-y-1"
      >
        <div
          v-if="selectionActive"
          class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 mb-3 bg-n-alpha-3 backdrop-blur-md border border-n-brand/40 rounded-xl shadow-sm"
        >
          <div class="flex items-center gap-2 text-sm text-n-slate-12">
            <span class="i-lucide-check-square text-n-brand" />
            {{ t('JIVO.FAQS.BULK.SELECTED', { count: selectedCount }) }}
          </div>
          <div class="flex flex-wrap gap-2">
            <Button
              icon="i-lucide-check"
              teal
              sm
              :label="t('JIVO.FAQS.BULK.APPROVE')"
              :is-loading="uiFlags.isBulkUpdating"
              @click="bulkApprove"
            />
            <Button
              icon="i-lucide-x"
              ruby
              sm
              faded
              :label="t('JIVO.FAQS.BULK.REJECT')"
              :is-loading="uiFlags.isBulkUpdating"
              @click="bulkReject"
            />
            <Button
              icon="i-lucide-trash-2"
              ruby
              sm
              faded
              :label="t('JIVO.FAQS.BULK.DELETE')"
              :is-loading="uiFlags.isBulkUpdating"
              @click="bulkDelete"
            />
            <Button
              slate
              sm
              faded
              :label="t('JIVO.FAQS.BULK.CLEAR')"
              @click="clearSelection"
            />
          </div>
        </div>
      </Transition>
    </template>

    <template #emptyState>
      <div
        class="flex flex-col items-center justify-center py-20 text-n-slate-11"
      >
        <span class="i-lucide-message-circle-question text-3xl mb-2" />
        <p class="text-sm">{{ emptyMessage }}</p>
      </div>
    </template>

    <template #body>
      <div class="flex flex-col gap-3">
        <JivoFaqApprovalRow
          v-for="faq in responses"
          :key="faq.id"
          :faq="faq"
          :selected="selectedIds.includes(faq.id)"
          :selection-active="selectionActive"
          :disabled="isConfirming"
          @approve="approveFaq"
          @reject="rejectFaq"
          @edit="openEditForm"
          @delete="deleteFaq"
          @toggle-selection="toggleSelection"
        />
      </div>
    </template>

    <Dialog
      ref="formDialogRef"
      :title="
        formMode === 'create'
          ? t('JIVO.FAQS.FORM.CREATE_TITLE')
          : t('JIVO.FAQS.FORM.EDIT_TITLE')
      "
      :show-cancel-button="false"
      :show-confirm-button="false"
    >
      <div class="space-y-3">
        <Input
          v-model="formData.question"
          :label="t('JIVO.FAQS.FORM.QUESTION_LABEL')"
          :placeholder="t('JIVO.FAQS.FORM.QUESTION_PLACEHOLDER')"
        />
        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1">
            {{ t('JIVO.FAQS.FORM.ANSWER_LABEL') }}
          </label>
          <textarea
            v-model="formData.answer"
            rows="4"
            :placeholder="t('JIVO.FAQS.FORM.ANSWER_PLACEHOLDER')"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
        </div>
      </div>
      <template #footer>
        <div class="flex justify-end gap-2">
          <Button
            :label="t('JIVO.FAQS.FORM.CANCEL')"
            slate
            faded
            @click="formDialogRef?.close()"
          />
          <Button
            :label="
              formMode === 'create'
                ? t('JIVO.FAQS.FORM.CREATE')
                : t('JIVO.FAQS.FORM.SAVE')
            "
            :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
            :disabled="!formData.question.trim() || !formData.answer.trim()"
            @click="submit"
          />
        </div>
      </template>
    </Dialog>

    <Dialog
      ref="confirmDialogRef"
      :type="confirmDialogProps.type"
      :title="confirmDialogProps.title"
      :description="confirmDialogProps.description"
      :is-loading="isConfirming"
      :confirm-button-label="confirmDialogProps.confirmLabel"
      :cancel-button-label="t('JIVO.FAQS.CONFIRM.CANCEL')"
      @confirm="handleConfirm"
      @close="pendingAction = null"
    />
  </JivoPageLayout>
</template>
