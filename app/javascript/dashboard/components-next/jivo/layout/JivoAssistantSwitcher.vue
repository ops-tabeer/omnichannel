<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store.js';

import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const emit = defineEmits(['close']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const assistants = useMapGetter('jivoAssistants/getAssistants');

const currentAssistantId = computed(() => route.params.assistantId);

const isAssistantActive = assistant =>
  assistant.id === Number(currentAssistantId.value);

const handleAssistantChange = async assistant => {
  if (isAssistantActive(assistant)) return;

  await router.push({
    name: route.name,
    params: {
      accountId: route.params.accountId,
      assistantId: assistant.id,
    },
  });

  emit('close');
};
</script>

<template>
  <div
    class="pt-5 pb-3 bg-n-alpha-3 backdrop-blur-[100px] outline outline-n-container outline-1 z-50 absolute w-[27.5rem] rounded-xl shadow-md flex flex-col gap-4"
  >
    <div
      class="flex items-center justify-between gap-4 px-6 pb-3 border-b border-n-alpha-2"
    >
      <div class="flex flex-col gap-1">
        <h2 class="text-base font-medium text-n-slate-12 w-fit">
          {{ t('JIVO.ASSISTANTS.TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('JIVO.PLAYGROUND.SWITCH_ASSISTANT') }}
        </p>
      </div>
    </div>
    <div v-if="assistants.length > 0" class="flex flex-col gap-2 px-4">
      <Button
        v-for="assistant in assistants"
        :key="assistant.id"
        :label="assistant.name"
        variant="ghost"
        color="slate"
        trailing-icon
        :icon="isAssistantActive(assistant) ? 'i-lucide-check' : ''"
        class="!justify-end !px-2 !py-2 hover:!bg-n-alpha-2 [&>.i-lucide-check]:text-n-teal-10 h-9"
        size="sm"
        @click="handleAssistantChange(assistant)"
      >
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ assistant.name || '' }}
        </span>
        <Avatar
          v-if="assistant"
          :name="assistant.name"
          :size="20"
          icon-name="i-lucide-bot"
          rounded-full
        />
      </Button>
    </div>
    <div v-else class="flex flex-col items-center gap-2 px-4 py-3">
      <p class="text-sm text-n-slate-11">
        {{ t('JIVO.PLAYGROUND.EMPTY_ASSISTANTS') }}
      </p>
    </div>
  </div>
</template>
