<script setup>
import { ref, nextTick, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import JivoPageLayout from 'dashboard/components-next/jivo/layout/JivoPageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const customTools = useMapGetter('jivoCustomTools/getCustomTools');
const uiFlags = useMapGetter('jivoCustomTools/getUIFlags');

const selectedTool = ref({});
const deleteDialogRef = ref(null);

const openCreate = () => {
  router.push({ name: 'jivo_custom_tool_new' });
};

const openEdit = tool => {
  router.push({
    name: 'jivo_custom_tool_edit',
    params: { id: tool.id },
  });
};

const openDelete = tool => {
  selectedTool.value = tool;
  nextTick(() => deleteDialogRef.value?.open());
};

const confirmDelete = async () => {
  try {
    await store.dispatch('jivoCustomTools/delete', selectedTool.value.id);
    useAlert(t('JIVO.CUSTOM_TOOLS.DELETED'));
  } catch (error) {
    useAlert(error.message || t('JIVO.CUSTOM_TOOLS.DELETE_FAILED'));
  } finally {
    deleteDialogRef.value?.close();
  }
};

onMounted(() => store.dispatch('jivoCustomTools/get'));
</script>

<template>
  <JivoPageLayout
    :header-title="t('JIVO.CUSTOM_TOOLS.HEADER')"
    :show-assistant-switcher="false"
    :button-label="t('JIVO.CUSTOM_TOOLS.ADD_NEW')"
    :is-fetching="uiFlags.isFetching"
    :is-empty="!customTools.length"
    @click="openCreate"
  >
    <template #emptyState>
      <div
        class="flex flex-col items-center justify-center py-20 text-n-slate-11"
      >
        <span class="i-lucide-wrench text-3xl mb-2" />
        <p class="text-sm">{{ t('JIVO.CUSTOM_TOOLS.EMPTY') }}</p>
      </div>
    </template>

    <template #body>
      <div class="flex flex-col gap-3">
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
  </JivoPageLayout>
</template>
