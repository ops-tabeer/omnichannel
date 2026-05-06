<script setup>
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';

import { frontendURL } from '../../../../helper/URLHelper';
import JivoPageLayout from 'dashboard/components-next/jivo/playground/JivoPageLayout.vue';
import JivoAssistantPlayground from 'dashboard/components-next/jivo/playground/JivoAssistantPlayground.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const assistantId = computed(() => Number(route.params.assistantId));

const backUrl = computed(() =>
  frontendURL(`accounts/${route.params.accountId}/settings/jivo`)
);

onMounted(() => {
  store.dispatch('jivoAssistants/get');
});
</script>

<template>
  <JivoPageLayout
    :header-title="t('JIVO.PLAYGROUND.HEADER')"
    :back-url="backUrl"
  >
    <template #body>
      <div class="flex flex-col h-full">
        <JivoAssistantPlayground
          :assistant-id="assistantId"
          class="bg-n-solid-1"
        />
      </div>
    </template>
  </JivoPageLayout>
</template>
