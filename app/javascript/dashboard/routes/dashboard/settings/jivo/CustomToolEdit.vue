<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import JivoPageLayout from 'dashboard/components-next/jivo/layout/JivoPageLayout.vue';
import JivoCustomToolForm from './components/JivoCustomToolForm.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const uiFlags = useMapGetter('jivoCustomTools/getUIFlags');

const toolId = computed(() =>
  route.params.id ? Number(route.params.id) : null
);
const mode = computed(() => (toolId.value ? 'edit' : 'create'));

const customTool = computed(() => {
  if (!toolId.value) return {};
  return store.getters['jivoCustomTools/getCustomTool'](toolId.value) || {};
});

const isReady = ref(false);

const headerTitle = computed(() =>
  mode.value === 'create'
    ? t('JIVO.CUSTOM_TOOLS.FORM.CREATE_TITLE')
    : t('JIVO.CUSTOM_TOOLS.FORM.EDIT_TITLE')
);

const backRoute = computed(() => ({ name: 'jivo_custom_tools' }));

const goBack = () => router.push(backRoute.value);

const handleSave = async data => {
  try {
    if (mode.value === 'create') {
      await store.dispatch('jivoCustomTools/create', data);
      useAlert(t('JIVO.CUSTOM_TOOLS.CREATED'));
    } else {
      await store.dispatch('jivoCustomTools/update', {
        id: toolId.value,
        ...data,
      });
      useAlert(t('JIVO.CUSTOM_TOOLS.UPDATED'));
    }
    goBack();
  } catch (error) {
    useAlert(error.message || t('JIVO.CUSTOM_TOOLS.SAVE_FAILED'));
  }
};

onMounted(async () => {
  if (mode.value === 'edit') {
    await store.dispatch('jivoCustomTools/get');
  }
  isReady.value = true;
});
</script>

<template>
  <JivoPageLayout
    :header-title="headerTitle"
    :show-assistant-switcher="false"
    :back-url="backRoute"
    :is-fetching="!isReady"
  >
    <template #body>
      <JivoCustomToolForm
        v-if="isReady"
        :mode="mode"
        :custom-tool="customTool"
        :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
        @save="handleSave"
        @close="goBack"
      />
    </template>
  </JivoPageLayout>
</template>
