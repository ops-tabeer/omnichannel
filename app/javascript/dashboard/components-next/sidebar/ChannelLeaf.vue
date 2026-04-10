<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  // eslint-disable-next-line vue/no-unused-properties
  active: {
    type: Boolean,
    default: false,
  },
  inbox: {
    type: Object,
    required: true,
  },
});

const reauthorizationRequired = computed(() => {
  return props.inbox.reauthorization_required;
});

const evolutionConnectionStatus = computed(() => {
  if (
    props.inbox.channel_type !== 'Channel::Api' ||
    !props.inbox.additional_attributes?.evolution_api
  )
    return null;
  return props.inbox.additional_attributes?.evolution_connection_status || null;
});
</script>

<template>
  <span class="size-5 grid place-content-center rounded-full bg-n-alpha-2">
    <ChannelIcon :inbox="inbox" class="size-3" />
  </span>
  <div class="flex-1 truncate min-w-0">{{ label }}</div>
  <div
    v-if="reauthorizationRequired"
    v-tooltip.top-end="$t('SIDEBAR.REAUTHORIZE')"
    class="grid place-content-center size-5 bg-n-ruby-5/60 rounded-full"
  >
    <Icon icon="i-woot-alert" class="size-3 text-n-ruby-9" />
  </div>
  <span
    v-else-if="evolutionConnectionStatus"
    v-tooltip.top-end="
      evolutionConnectionStatus === 'connected'
        ? $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.STATUS_CONNECTED')
        : $t('INBOX_MGMT.ADD.EVOLUTION_WHATSAPP.STATUS_DISCONNECTED')
    "
    class="size-2 rounded-full flex-shrink-0"
    :class="{
      'bg-n-teal-10': evolutionConnectionStatus === 'connected',
      'bg-n-ruby-9': evolutionConnectionStatus === 'disconnected',
    }"
  />
</template>
