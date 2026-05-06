<script setup>
import { ref, computed, nextTick, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import JivoPageLayout from 'dashboard/components-next/jivo/layout/JivoPageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import JivoToolIcon from 'dashboard/components-next/jivo/JivoToolIcon.vue';

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

const selectedScenario = ref({});
const deleteDialogRef = ref(null);

const openCreate = () => {
  router.push({
    name: 'jivo_scenario_new',
    params: { assistantId: assistantId.value },
  });
};

const openEdit = scenario => {
  router.push({
    name: 'jivo_scenario_edit',
    params: { assistantId: assistantId.value, scenarioId: scenario.id },
  });
};

const openDelete = scenario => {
  selectedScenario.value = scenario;
  nextTick(() => deleteDialogRef.value?.open());
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
  } finally {
    deleteDialogRef.value?.close();
  }
};

const toolMetaById = computed(() => {
  const tools = assistant.value?.available_tools || [];
  return tools.reduce((acc, tool) => {
    acc[tool.id] = tool;
    return acc;
  }, {});
});

const lookupTool = id => toolMetaById.value[id] || null;

const refresh = () => store.dispatch('jivoScenarios/get', assistantId.value);

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
    :header-title="t('JIVO.SCENARIOS.HEADER')"
    :button-label="t('JIVO.SCENARIOS.ADD_NEW')"
    :is-fetching="uiFlags.isFetching"
    :is-empty="!scenarios.length"
    @click="openCreate"
  >
    <template #emptyState>
      <div
        class="flex flex-col items-center justify-center py-20 text-n-slate-11"
      >
        <span class="i-lucide-route text-3xl mb-2" />
        <p class="text-sm">{{ t('JIVO.SCENARIOS.EMPTY') }}</p>
      </div>
    </template>

    <template #body>
      <div class="flex flex-col gap-3">
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
                  class="text-xs bg-n-blue-3 text-n-blue-text px-2 py-0.5 rounded inline-flex items-center gap-1"
                >
                  <JivoToolIcon
                    :icon="lookupTool(tool)?.icon"
                    :custom="!!lookupTool(tool)?.custom"
                  />
                  <span class="font-mono">{{
                    lookupTool(tool)?.title || tool
                  }}</span>
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
    </template>
  </JivoPageLayout>
</template>
