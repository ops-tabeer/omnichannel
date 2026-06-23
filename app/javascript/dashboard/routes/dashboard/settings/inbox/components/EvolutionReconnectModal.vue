<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import Modal from 'dashboard/components/Modal.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import EvolutionChannel from 'dashboard/api/channel/evolutionChannel';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

const props = defineProps({
  show: { type: Boolean, required: true },
  inbox: { type: Object, required: true },
});

const emit = defineEmits(['update:show', 'reconnected']);

const { t } = useI18n();

const qrCodeBase64 = ref('');
const instanceName = ref('');
const connectionState = ref('waiting');
const isLoading = ref(false);
const step = ref('options');
// History import is built but not finalized — keep the wiring, hide the UI for now.
const SHOW_IMPORT_HISTORY = false;
const importHistory = ref(false);
const historyDays = ref(365);

const closeModal = () => {
  emit('update:show', false);
};

const resetState = () => {
  step.value = 'options';
  qrCodeBase64.value = '';
  instanceName.value = '';
  connectionState.value = 'waiting';
  const attrs = props.inbox.additional_attributes || {};
  importHistory.value = Boolean(attrs.evolution_import_messages);
  historyDays.value = attrs.evolution_days_limit_import_messages || 365;
};

const initReconnect = async () => {
  step.value = 'qr';
  isLoading.value = true;
  connectionState.value = 'waiting';
  try {
    const response = await EvolutionChannel.reconnect(props.inbox.id, {
      import_messages: importHistory.value,
      days_limit_import_messages: importHistory.value
        ? Number(historyDays.value)
        : 0,
    });
    qrCodeBase64.value = response.data.qrcode;
    instanceName.value = response.data.instance_name;
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.RECONNECT.ERROR')
    );
    closeModal();
  } finally {
    isLoading.value = false;
  }
};

const refreshQrCode = async () => {
  if (!instanceName.value) return;
  try {
    const response = await EvolutionChannel.refreshQr(instanceName.value);
    qrCodeBase64.value = response.data.qrcode;
  } catch (error) {
    useAlert(t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.QR_REFRESH_ERROR'));
  }
};

const onEvolutionConnected = data => {
  if (data.instance_name !== instanceName.value) return;
  connectionState.value = 'connected';
  useAlert(t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.RECONNECT.SUCCESS'));
  emit('reconnected');
  closeModal();
};

watch(
  () => props.show,
  newVal => {
    if (newVal) {
      resetState();
    }
  }
);

onMounted(() => {
  emitter.on(BUS_EVENTS.EVOLUTION_CONNECTED, onEvolutionConnected);
  if (props.show) {
    resetState();
  }
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.EVOLUTION_CONNECTED, onEvolutionConnected);
});
</script>

<template>
  <Modal
    :show="show"
    :on-close="closeModal"
    @update:show="$emit('update:show', $event)"
  >
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.RECONNECT.TITLE')"
        :header-content="
          $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.RECONNECT.DESC', {
            inboxName: inbox.name,
          })
        "
      />

      <div v-if="step === 'options'" class="flex flex-col gap-4 p-6">
        <label
          v-if="SHOW_IMPORT_HISTORY"
          class="flex items-center gap-2 cursor-pointer"
        >
          <input
            v-model="importHistory"
            type="checkbox"
            class="size-4 rounded border-n-slate-7 text-p-600 focus:ring-p-500"
          />
          <span class="text-sm text-n-slate-12">
            {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.IMPORT_HISTORY.LABEL') }}
          </span>
        </label>
        <p
          v-if="SHOW_IMPORT_HISTORY"
          class="text-xs text-n-slate-10 -mt-3 ml-6"
        >
          {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.IMPORT_HISTORY.HELP') }}
        </p>

        <label v-if="SHOW_IMPORT_HISTORY && importHistory">
          {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.HISTORY_DAYS.LABEL') }}
          <input v-model="historyDays" type="number" min="1" />
        </label>

        <div class="flex gap-2 justify-end mt-2">
          <NextButton
            faded
            slate
            :label="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.RECONNECT.CLOSE')"
            @click="closeModal"
          />
          <NextButton
            solid
            blue
            :label="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.RECONNECT.BUTTON')"
            @click="initReconnect"
          />
        </div>
      </div>

      <div v-else class="flex flex-col items-center gap-6 p-6">
        <div v-if="isLoading" class="flex items-center justify-center size-64">
          <span class="spinner" />
        </div>

        <template v-else>
          <p class="text-sm text-n-slate-11 text-center">
            {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.QR_INSTRUCTION') }}
          </p>

          <div
            class="rounded-lg shadow outline-1 outline-n-strong outline p-2 bg-white"
          >
            <img
              v-if="qrCodeBase64"
              :src="qrCodeBase64"
              alt="WhatsApp QR Code"
              class="size-64"
            />
          </div>

          <p class="text-sm text-n-slate-9">
            {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.CONNECTION_STATUS') }}
            <span
              class="font-medium"
              :class="{
                'text-g-500': connectionState === 'connected',
                'text-y-600': connectionState === 'waiting',
              }"
            >
              {{ connectionState }}
            </span>
          </p>

          <div class="flex gap-2">
            <NextButton
              outline
              slate
              :label="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.REFRESH_QR')"
              @click="refreshQrCode"
            />
            <NextButton
              faded
              slate
              :label="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.RECONNECT.CLOSE')"
              @click="closeModal"
            />
          </div>
        </template>
      </div>
    </div>
  </Modal>
</template>
