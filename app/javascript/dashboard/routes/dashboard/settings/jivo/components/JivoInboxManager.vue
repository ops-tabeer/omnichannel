<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistant: { type: Object, required: true },
});

const emit = defineEmits(['close']);
const { t } = useI18n();

const store = useStore();
const allInboxes = useMapGetter('inboxes/getInboxes');
const isSubmitting = ref(false);

const connectedInboxIds = computed(() =>
  (props.assistant.inboxes || []).map(i => i.id)
);

const isConnected = inboxId => connectedInboxIds.value.includes(inboxId);

const toggleInbox = async inbox => {
  isSubmitting.value = true;
  try {
    if (isConnected(inbox.id)) {
      await store.dispatch('jivoAssistants/disconnectInbox', {
        assistantId: props.assistant.id,
        inboxId: inbox.id,
      });
      useAlert(`Disconnected from ${inbox.name}`);
    } else {
      await store.dispatch('jivoAssistants/connectInbox', {
        assistantId: props.assistant.id,
        inboxId: inbox.id,
      });
      useAlert(`Connected to ${inbox.name}`);
    }
  } catch (error) {
    useAlert(error.message || 'Failed to update inbox');
  } finally {
    isSubmitting.value = false;
  }
};

onMounted(() => {
  if (!allInboxes.value.length) {
    store.dispatch('inboxes/get');
  }
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('close')"
  >
    <div
      class="bg-n-solid-1 rounded-lg shadow-xl w-full max-w-lg max-h-[90vh] overflow-y-auto"
    >
      <div class="p-6 border-b border-n-weak">
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{
            t('JIVO.ASSISTANTS.INBOX_MANAGER.TITLE', {
              name: assistant.name,
            })
          }}
        </h2>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('JIVO.ASSISTANTS.INBOX_MANAGER.DESCRIPTION') }}
        </p>
      </div>

      <div class="p-6 space-y-2">
        <div
          v-for="inbox in allInboxes"
          :key="inbox.id"
          class="flex items-center justify-between p-3 border border-n-weak rounded-md"
        >
          <div>
            <div class="text-sm font-medium text-n-slate-12">
              {{ inbox.name }}
            </div>
            <div class="text-xs text-n-slate-11">
              {{ inbox.channel_type }}
            </div>
          </div>
          <Button
            :label="
              isConnected(inbox.id)
                ? t('JIVO.ASSISTANTS.INBOX_MANAGER.DISCONNECT')
                : t('JIVO.ASSISTANTS.INBOX_MANAGER.CONNECT')
            "
            :ruby="isConnected(inbox.id)"
            xs
            faded
            :is-loading="isSubmitting"
            @click="toggleInbox(inbox)"
          />
        </div>
      </div>

      <div class="p-6 border-t border-n-weak flex justify-end">
        <Button
          :label="t('JIVO.ASSISTANTS.INBOX_MANAGER.CLOSE')"
          slate
          faded
          @click="emit('close')"
        />
      </div>
    </div>
  </div>
</template>
