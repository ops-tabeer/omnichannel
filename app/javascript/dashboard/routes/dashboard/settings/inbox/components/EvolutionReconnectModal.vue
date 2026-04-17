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

const closeModal = () => {
  emit('update:show', false);
};

const initReconnect = async () => {
  isLoading.value = true;
  connectionState.value = 'waiting';
  try {
    const response = await EvolutionChannel.reconnect(props.inbox.id);
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
      initReconnect();
    } else {
      qrCodeBase64.value = '';
      instanceName.value = '';
      connectionState.value = 'waiting';
    }
  }
);

onMounted(() => {
  emitter.on(BUS_EVENTS.EVOLUTION_CONNECTED, onEvolutionConnected);
  if (props.show) {
    initReconnect();
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

      <div class="flex flex-col items-center gap-6 p-6">
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
