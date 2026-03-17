<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required, helpers } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import EvolutionChannel from 'dashboard/api/channel/evolutionChannel';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

const { t } = useI18n();
const router = useRouter();
const instanceName = ref('');
const phoneNumber = ref('');
const rejectGroups = ref(true);
const isCreating = ref(false);
const qrCodeBase64 = ref('');
const showQrCode = ref(false);
const connectionState = ref('waiting');

const noSpaces = helpers.withMessage(
  'Instance name must not contain spaces. Use hyphens or underscores instead.',
  value => !/\s/.test(value)
);

const rules = {
  instanceName: { required, noSpaces },
  phoneNumber: { required },
};
const v$ = useVuelidate(rules, { instanceName, phoneNumber });

async function createInstance() {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  isCreating.value = true;
  try {
    const response = await EvolutionChannel.createInstance({
      instance_name: instanceName.value.trim(),
      phone_number: phoneNumber.value.trim(),
      groups_ignore: rejectGroups.value,
    });
    qrCodeBase64.value = response.data.qrcode;
    showQrCode.value = true;
    connectionState.value = 'waiting';
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.CREATE_ERROR')
    );
  } finally {
    isCreating.value = false;
  }
}

async function completeSetup() {
  connectionState.value = 'connected';
  try {
    const response = await EvolutionChannel.completeSetup({
      instance_name: instanceName.value.trim(),
      phone_number: phoneNumber.value.trim(),
      inbox_name: `WhatsApp - ${phoneNumber.value.trim()}`,
    });
    router.replace({
      name: 'settings_inboxes_add_agents',
      params: {
        page: 'new',
        inbox_id: response.data.id,
      },
    });
  } catch (error) {
    useAlert(
      parseAPIErrorResponse(error) ||
        t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.SETUP_ERROR')
    );
  }
}

function onEvolutionConnected(data) {
  if (data.instance_name === instanceName.value.trim()) {
    completeSetup();
  }
}

async function refreshQrCode() {
  try {
    const response = await EvolutionChannel.refreshQr(
      instanceName.value.trim()
    );
    qrCodeBase64.value = response.data.qrcode;
  } catch (error) {
    useAlert(t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.QR_REFRESH_ERROR'));
  }
}

onMounted(() => {
  emitter.on(BUS_EVENTS.EVOLUTION_CONNECTED, onEvolutionConnected);
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.EVOLUTION_CONNECTED, onEvolutionConnected);
});
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.DESC')"
    />

    <!-- Test deployment banner -->
    <div
      class="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6"
      data-test="deployment-test-banner"
    >
      <p class="text-blue-800 text-sm font-medium">
        {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.DEPLOYMENT_TEST') }}
      </p>
    </div>

    <form
      v-if="!showQrCode"
      class="flex flex-wrap flex-col mx-0"
      @submit.prevent="createInstance"
    >
      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.instanceName.$error }">
          {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.INSTANCE_NAME.LABEL') }}
          <input
            v-model="instanceName"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.INSTANCE_NAME.PLACEHOLDER')
            "
            @blur="v$.instanceName.$touch"
          />
          <span v-if="v$.instanceName.$error" class="message">
            {{
              v$.instanceName.$errors[0]?.$message ||
              $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.INSTANCE_NAME.ERROR')
            }}
          </span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.phoneNumber.$error }">
          {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.PHONE_NUMBER.LABEL') }}
          <input
            v-model="phoneNumber"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.PHONE_NUMBER.PLACEHOLDER')
            "
            @blur="v$.phoneNumber.$touch"
          />
          <span v-if="v$.phoneNumber.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.PHONE_NUMBER.ERROR') }}
          </span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 mt-4">
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            v-model="rejectGroups"
            type="checkbox"
            class="size-4 rounded border-n-slate-7 text-p-600 focus:ring-p-500"
          />
          <span class="text-sm text-n-slate-12">
            {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.REJECT_GROUPS.LABEL') }}
          </span>
        </label>
        <p class="text-xs text-n-slate-10 mt-1 ml-6">
          {{ $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.REJECT_GROUPS.HELP') }}
        </p>
      </div>

      <div class="w-full mt-4">
        <NextButton
          :is-loading="isCreating"
          :disabled="isCreating"
          type="submit"
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.SUBMIT_BUTTON')"
        />
      </div>
    </form>

    <div v-else class="flex flex-col items-center gap-6 mt-6">
      <p class="text-sm text-n-slate-11">
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

      <NextButton
        outline
        slate
        :label="$t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.REFRESH_QR')"
        @click="refreshQrCode"
      />
    </div>
  </div>
</template>
