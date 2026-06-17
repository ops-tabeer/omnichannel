<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import JivoPlaygroundMessageList from './JivoPlaygroundMessageList.vue';
import JivoAssistants from 'dashboard/api/jivoAssistants';

const props = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();
const messages = ref([]);
const newMessage = ref('');
const isLoading = ref(false);

const formatMessagesForApi = () =>
  messages.value.map(message => ({
    role: message.sender,
    content: message.content,
  }));

const resetConversation = () => {
  messages.value = [];
  newMessage.value = '';
};

watch(
  () => props.assistantId,
  (newId, oldId) => {
    if (oldId && newId !== oldId) {
      resetConversation();
    }
  }
);

const sendMessage = async () => {
  if (!newMessage.value.trim() || isLoading.value) return;

  const userMessage = {
    content: newMessage.value,
    sender: 'user',
    timestamp: new Date().toISOString(),
  };
  messages.value.push(userMessage);
  const currentMessage = newMessage.value;
  newMessage.value = '';

  try {
    isLoading.value = true;
    const { data } = await JivoAssistants.playground({
      assistantId: props.assistantId,
      messageContent: currentMessage,
      messageHistory: formatMessagesForApi().slice(0, -1),
    });

    messages.value.push({
      content: data.response,
      sender: 'assistant',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    messages.value.push({
      content: t('JIVO.PLAYGROUND.ERROR'),
      sender: 'assistant',
      timestamp: new Date().toISOString(),
    });
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col h-full rounded-xl border py-6 border-n-weak text-n-slate-11"
  >
    <div class="mb-8 px-6">
      <div class="flex justify-between items-center mb-1">
        <h3 class="text-lg font-medium">
          {{ t('JIVO.PLAYGROUND.HEADER') }}
        </h3>
        <NextButton
          ghost
          sm
          slate
          icon="i-lucide-rotate-ccw"
          @click="resetConversation"
        />
      </div>
      <p class="text-sm text-n-slate-11">
        {{ t('JIVO.PLAYGROUND.DESCRIPTION') }}
      </p>
    </div>

    <JivoPlaygroundMessageList :messages="messages" :is-loading="isLoading" />

    <div
      class="flex items-center mx-6 bg-n-background outline outline-1 outline-n-weak rounded-xl p-3"
    >
      <input
        v-model="newMessage"
        class="flex-1 bg-transparent border-none focus:outline-none text-sm mb-0 text-n-slate-12 placeholder:text-n-slate-10"
        :placeholder="t('JIVO.PLAYGROUND.MESSAGE_PLACEHOLDER')"
        @keyup.enter="sendMessage"
      />
      <NextButton
        ghost
        sm
        :disabled="!newMessage.trim()"
        icon="i-lucide-send"
        @click="sendMessage"
      />
    </div>

    <p class="text-xs text-n-slate-11 pt-2 text-center">
      {{ t('JIVO.PLAYGROUND.CREDIT_NOTE') }}
    </p>
  </div>
</template>
