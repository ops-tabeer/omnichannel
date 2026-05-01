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

const responses = useMapGetter('jivoResponses/getResponses');
const uiFlags = useMapGetter('jivoResponses/getUIFlags');
const assistant = computed(() =>
  store.getters['jivoAssistants/getAssistant'](assistantId.value)
);

const showForm = ref(false);
const formMode = ref('create');
const formData = ref({ id: null, question: '', answer: '' });
const deleteDialogRef = ref(null);
const selectedFaq = ref({});

const openCreateForm = () => {
  formMode.value = 'create';
  formData.value = { id: null, question: '', answer: '' };
  showForm.value = true;
};

const openEditForm = faq => {
  formMode.value = 'edit';
  formData.value = { id: faq.id, question: faq.question, answer: faq.answer };
  showForm.value = true;
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
    showForm.value = false;
  } catch (error) {
    useAlert(error.message || t('JIVO.FAQS.SAVE_FAILED'));
  }
};

const openDeleteDialog = faq => {
  selectedFaq.value = faq;
  deleteDialogRef.value.open();
};

const confirmDelete = async () => {
  try {
    await store.dispatch('jivoResponses/delete', {
      assistantId: assistantId.value,
      id: selectedFaq.value.id,
    });
    useAlert(t('JIVO.FAQS.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JIVO.FAQS.DELETE_FAILED'));
  }
};

const goBack = () => router.push({ name: 'jivo_assistants' });

const refresh = async () => {
  try {
    await store.dispatch('jivoResponses/get', {
      assistantId: assistantId.value,
    });
  } catch (error) {
    useAlert(error.message || t('JIVO.FAQS.LOAD_FAILED'));
  }
};

onMounted(async () => {
  await store.dispatch('jivoAssistants/get');
  await refresh();
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('JIVO.FAQS.LOADING')"
    :no-records-found="!responses.length && !showForm"
    :no-records-message="t('JIVO.FAQS.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('JIVO.FAQS.TITLE', { name: assistant.name || '' })"
        :description="t('JIVO.FAQS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            icon="i-lucide-arrow-left"
            :label="t('JIVO.FAQS.BACK')"
            slate
            faded
            @click="goBack"
          />
          <Button icon="i-lucide-refresh-cw" slate faded @click="refresh" />
          <Button
            icon="i-lucide-circle-plus"
            :label="t('JIVO.FAQS.ADD')"
            @click="openCreateForm"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="space-y-3">
        <div
          v-if="showForm"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg space-y-3"
        >
          <h4 class="text-sm font-medium text-n-slate-12">
            {{
              formMode === 'create'
                ? t('JIVO.FAQS.FORM.CREATE_TITLE')
                : t('JIVO.FAQS.FORM.EDIT_TITLE')
            }}
          </h4>
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
          <div class="flex justify-end gap-2">
            <Button
              :label="t('JIVO.FAQS.FORM.CANCEL')"
              slate
              faded
              @click="showForm = false"
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
        </div>

        <div
          v-for="faq in responses"
          :key="faq.id"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg"
        >
          <div class="flex justify-between items-start gap-4">
            <div class="flex-1 min-w-0">
              <h3 class="text-base font-medium text-n-slate-12">
                {{ faq.question }}
              </h3>
              <p class="text-sm text-n-slate-11 mt-2 whitespace-pre-line">
                {{ faq.answer }}
              </p>
              <div class="flex flex-wrap gap-2 mt-2">
                <span
                  class="text-xs px-2 py-1 rounded"
                  :class="
                    faq.status === 'approved'
                      ? 'bg-n-teal-3 text-n-teal-text'
                      : 'bg-n-amber-3 text-n-amber-text'
                  "
                >
                  {{ faq.status }}
                </span>
                <span
                  v-if="faq.documentable_type"
                  class="text-xs text-n-slate-11"
                >
                  {{ t('JIVO.FAQS.AUTO_GENERATED') }}
                </span>
              </div>
            </div>
            <div class="flex gap-2 shrink-0">
              <Button
                icon="i-lucide-pen"
                slate
                xs
                faded
                @click="openEditForm(faq)"
              />
              <Button
                icon="i-lucide-trash-2"
                ruby
                xs
                faded
                @click="openDeleteDialog(faq)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('JIVO.FAQS.DELETE.TITLE')"
      :description="t('JIVO.FAQS.DELETE.DESCRIPTION')"
      :is-loading="uiFlags.isDeleting"
      :confirm-button-label="t('JIVO.FAQS.DELETE.CONFIRM')"
      :cancel-button-label="t('JIVO.FAQS.DELETE.CANCEL')"
      @confirm="confirmDelete"
    />
  </SettingsLayout>
</template>
