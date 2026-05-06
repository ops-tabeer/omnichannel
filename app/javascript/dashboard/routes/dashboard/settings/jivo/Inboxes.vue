<script setup>
import { ref, computed, nextTick, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import JivoPageLayout from 'dashboard/components-next/jivo/layout/JivoPageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const assistantId = computed(() => Number(route.params.assistantId));

const allInboxes = useMapGetter('inboxes/getInboxes');
const assistantsUiFlags = useMapGetter('jivoAssistants/getUIFlags');
const assistant = computed(
  () => store.getters['jivoAssistants/getAssistant'](assistantId.value) || {}
);

const connectDialogRef = ref(null);
const disconnectDialogRef = ref(null);
const selectedInbox = ref(null);
const togglingInboxId = ref(null);

const connectedInboxes = computed(() => assistant.value?.inboxes || []);
const connectedInboxIds = computed(() => connectedInboxes.value.map(i => i.id));

const availableInboxes = computed(() =>
  (allInboxes.value || []).filter(i => !connectedInboxIds.value.includes(i.id))
);

const isFetching = computed(() => assistantsUiFlags.value?.isFetching);

const openConnectDialog = () => {
  nextTick(() => connectDialogRef.value?.open());
};

const connectInbox = async inbox => {
  togglingInboxId.value = inbox.id;
  try {
    await store.dispatch('jivoAssistants/connectInbox', {
      assistantId: assistantId.value,
      inboxId: inbox.id,
    });
    useAlert(t('JIVO.INBOXES.CONNECTED', { name: inbox.name }));
  } catch (error) {
    useAlert(error.message || t('JIVO.INBOXES.CONNECT_FAILED'));
  } finally {
    togglingInboxId.value = null;
  }
};

const openDisconnectDialog = inbox => {
  selectedInbox.value = inbox;
  nextTick(() => disconnectDialogRef.value?.open());
};

const confirmDisconnect = async () => {
  if (!selectedInbox.value) return;
  try {
    await store.dispatch('jivoAssistants/disconnectInbox', {
      assistantId: assistantId.value,
      inboxId: selectedInbox.value.id,
    });
    useAlert(
      t('JIVO.INBOXES.DISCONNECTED', { name: selectedInbox.value.name })
    );
  } catch (error) {
    useAlert(error.message || t('JIVO.INBOXES.DISCONNECT_FAILED'));
  } finally {
    disconnectDialogRef.value?.close();
    selectedInbox.value = null;
  }
};

watch(assistantId, id => {
  if (id) store.dispatch('jivoAssistants/get');
});

onMounted(() => {
  store.dispatch('jivoAssistants/get');
  if (!allInboxes.value?.length) store.dispatch('inboxes/get');
});
</script>

<template>
  <JivoPageLayout
    :header-title="t('JIVO.INBOXES.HEADER')"
    :button-label="t('JIVO.INBOXES.ADD_NEW')"
    :is-fetching="isFetching"
    :is-empty="!connectedInboxes.length"
    @click="openConnectDialog"
  >
    <template #emptyState>
      <div
        class="flex flex-col items-center justify-center py-20 text-n-slate-11"
      >
        <span class="i-lucide-inbox text-3xl mb-2" />
        <p class="text-sm mb-3">{{ t('JIVO.INBOXES.EMPTY') }}</p>
        <Button
          icon="i-lucide-plus"
          :label="t('JIVO.INBOXES.ADD_NEW')"
          @click="openConnectDialog"
        />
      </div>
    </template>

    <template #body>
      <div class="flex flex-col gap-3">
        <div
          v-for="inbox in connectedInboxes"
          :key="inbox.id"
          class="p-4 bg-n-solid-1 border border-n-weak rounded-lg flex items-center justify-between gap-4"
        >
          <div class="flex-1 min-w-0">
            <h3 class="text-base font-medium text-n-slate-12 truncate">
              {{ inbox.name }}
            </h3>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{ inbox.channel_type }}
            </p>
          </div>
          <Button
            icon="i-lucide-unplug"
            :label="t('JIVO.INBOXES.DISCONNECT')"
            ruby
            xs
            faded
            @click="openDisconnectDialog(inbox)"
          />
        </div>
      </div>

      <Dialog
        ref="connectDialogRef"
        :title="t('JIVO.INBOXES.CONNECT_DIALOG.TITLE')"
        :description="t('JIVO.INBOXES.CONNECT_DIALOG.DESCRIPTION')"
        :show-cancel-button="false"
        :show-confirm-button="false"
      >
        <div v-if="!availableInboxes.length" class="py-6 text-center">
          <p class="text-sm text-n-slate-11">
            {{ t('JIVO.INBOXES.CONNECT_DIALOG.EMPTY') }}
          </p>
        </div>
        <div v-else class="space-y-2 max-h-96 overflow-y-auto">
          <div
            v-for="inbox in availableInboxes"
            :key="inbox.id"
            class="flex items-center justify-between p-3 border border-n-weak rounded-md"
          >
            <div class="min-w-0">
              <div class="text-sm font-medium text-n-slate-12 truncate">
                {{ inbox.name }}
              </div>
              <div class="text-xs text-n-slate-11">
                {{ inbox.channel_type }}
              </div>
            </div>
            <Button
              icon="i-lucide-plug"
              :label="t('JIVO.INBOXES.CONNECT')"
              xs
              :is-loading="togglingInboxId === inbox.id"
              @click="connectInbox(inbox)"
            />
          </div>
        </div>
        <template #footer>
          <div class="flex justify-end">
            <Button
              :label="t('JIVO.INBOXES.CONNECT_DIALOG.CLOSE')"
              slate
              faded
              @click="connectDialogRef?.close()"
            />
          </div>
        </template>
      </Dialog>

      <Dialog
        ref="disconnectDialogRef"
        type="alert"
        :title="t('JIVO.INBOXES.DISCONNECT_DIALOG.TITLE')"
        :description="
          t('JIVO.INBOXES.DISCONNECT_DIALOG.DESCRIPTION', {
            name: selectedInbox?.name || '',
          })
        "
        :confirm-button-label="t('JIVO.INBOXES.DISCONNECT_DIALOG.CONFIRM')"
        :cancel-button-label="t('JIVO.INBOXES.DISCONNECT_DIALOG.CANCEL')"
        @confirm="confirmDisconnect"
      />
    </template>
  </JivoPageLayout>
</template>
