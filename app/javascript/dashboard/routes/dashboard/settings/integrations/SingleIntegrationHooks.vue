<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useBranding } from 'shared/composables/useBranding';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  integrationId: {
    type: String,
    required: true,
  },
});

defineEmits(['add', 'delete']);

const store = useStore();
const { t } = useI18n();
const { integration, hasConnectedHooks } = useIntegrationHook(
  props.integrationId
);

const { replaceInstallationName } = useBranding();

const inboxesList = useMapGetter('inboxes/getInboxes');
const uiFlags = useMapGetter('integrations/getUIFlags');

const isOdoo = computed(() => props.integrationId === 'odoo');
const hook = computed(() => integration.value.hooks?.[0]);
const connectedUser = computed(() => hook.value?.settings?.connected_user);

const selectedInboxIds = ref([]);
const fallbackUserLogin = ref('');
watch(
  () => hook.value?.settings,
  settings => {
    selectedInboxIds.value = [...(settings?.enabled_inbox_ids || [])];
    fallbackUserLogin.value = settings?.fallback_user_login || '';
  },
  { immediate: true }
);

onMounted(() => {
  if (isOdoo.value && !inboxesList.value.length) {
    store.dispatch('inboxes/get');
  }
});

const saveSettings = async () => {
  await store.dispatch('integrations/updateHook', {
    hookId: hook.value.id,
    hookData: {
      hook: {
        settings: {
          ...hook.value.settings,
          enabled_inbox_ids: selectedInboxIds.value,
          fallback_user_login: fallbackUserLogin.value,
        },
      },
    },
  });
  useAlert(t('INTEGRATION_APPS.INBOX_SYNC.SAVED'));
};
</script>

<template>
  <div
    class="outline outline-n-container outline-1 bg-n-card rounded-xl flex-grow overflow-auto p-4"
  >
    <div class="flex items-center justify-center">
      <div class="flex h-16 w-16 items-center justify-center">
        <img
          :src="`/dashboard/images/integrations/${integrationId}.png`"
          class="max-w-full rounded-md border border-n-weak shadow-sm block dark:hidden bg-n-alpha-3 dark:bg-n-alpha-2"
        />
        <img
          :src="`/dashboard/images/integrations/${integrationId}-dark.png`"
          class="max-w-full rounded-md border border-n-weak shadow-sm hidden dark:block bg-n-alpha-3 dark:bg-n-alpha-2"
        />
      </div>
      <div class="flex flex-col justify-center m-0 mx-4 flex-1">
        <h3 class="mb-1 text-heading-1 text-n-slate-12">
          {{ integration.name }}
        </h3>
        <p class="text-n-slate-11 text-body-main">
          {{ replaceInstallationName(integration.description) }}
        </p>
        <p v-if="connectedUser" class="text-n-teal-11 text-sm font-medium mt-1">
          {{ $t('INTEGRATION_APPS.CONNECTED_AS', { user: connectedUser }) }}
        </p>
      </div>
      <div class="flex justify-center items-center mb-0 w-[15%]">
        <div v-if="hasConnectedHooks">
          <div @click="$emit('delete', integration.hooks[0])">
            <Button
              ruby
              faded
              :label="$t('INTEGRATION_APPS.DISCONNECT.BUTTON_TEXT')"
            />
          </div>
        </div>
        <div v-else>
          <Button
            blue
            faded
            :label="$t('INTEGRATION_APPS.CONNECT.BUTTON_TEXT')"
            @click="$emit('add')"
          />
        </div>
      </div>
    </div>
    <div
      v-if="isOdoo && hasConnectedHooks"
      class="mt-4 border-t border-n-weak pt-4"
    >
      <h4 class="text-sm font-medium text-n-slate-12 mb-1">
        {{ $t('INTEGRATION_APPS.ADD.FORM.ENABLED_INBOXES.LABEL') }}
      </h4>
      <p class="text-n-slate-11 text-xs mb-3">
        {{ $t('INTEGRATION_APPS.ADD.FORM.ENABLED_INBOXES.HELP') }}
      </p>
      <div class="flex flex-col gap-2 mb-3">
        <label
          v-for="inbox in inboxesList"
          :key="inbox.id"
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <input v-model="selectedInboxIds" type="checkbox" :value="inbox.id" />
          {{ inbox.name }}
        </label>
      </div>
      <h4 class="text-sm font-medium text-n-slate-12 mb-1">
        {{ $t('INTEGRATION_APPS.FALLBACK_USER.LABEL') }}
      </h4>
      <p class="text-n-slate-11 text-xs mb-2">
        {{ $t('INTEGRATION_APPS.FALLBACK_USER.HELP') }}
      </p>
      <input
        v-model="fallbackUserLogin"
        type="text"
        class="w-full mb-3 bg-n-alpha-2 text-n-slate-12 text-sm rounded-md border border-n-weak px-3 py-2"
        :placeholder="$t('INTEGRATION_APPS.FALLBACK_USER.PLACEHOLDER')"
      />
      <Button
        blue
        sm
        :label="$t('INTEGRATION_APPS.INBOX_SYNC.SAVE')"
        :is-loading="uiFlags.isUpdating"
        @click="saveSettings"
      />
    </div>
  </div>
</template>
