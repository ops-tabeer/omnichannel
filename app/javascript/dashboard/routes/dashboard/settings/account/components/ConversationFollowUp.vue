<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import TextArea from 'next/textarea/TextArea.vue';
import Switch from 'next/switch/Switch.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import DurationInput from 'next/input/DurationInput.vue';
import { DURATION_UNITS } from 'dashboard/components-next/input/constants';

const { t } = useI18n();
const duration = ref(0);
const unit = ref(DURATION_UNITS.MINUTES);
const message = ref('');
const maxCount = ref(1);
const afterBot = ref(true);
const afterAgent = ref(false);
const isEnabled = ref(false);
const isSubmitting = ref(false);

const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    const {
      conversation_follow_up_wait_time,
      conversation_follow_up_message,
      conversation_follow_up_max_count,
      conversation_follow_up_after_bot,
      conversation_follow_up_after_agent,
    } = currentAccount.value?.settings || {};

    duration.value = conversation_follow_up_wait_time;
    message.value = conversation_follow_up_message;
    maxCount.value = conversation_follow_up_max_count || 1;
    afterBot.value = conversation_follow_up_after_bot ?? true;
    afterAgent.value = conversation_follow_up_after_agent ?? false;

    if (duration.value) {
      if (duration.value % (24 * 60) === 0) {
        unit.value = DURATION_UNITS.DAYS;
      } else if (duration.value % 60 === 0) {
        unit.value = DURATION_UNITS.HOURS;
      } else {
        unit.value = DURATION_UNITS.MINUTES;
      }
    }

    if (duration.value) {
      isEnabled.value = true;
    }
  },
  { deep: true, immediate: true }
);

const updateAccountSettings = async settings => {
  try {
    isSubmitting.value = true;
    await updateAccount(settings, { silent: true });
    useAlert(t('GENERAL_SETTINGS.FORM.FOLLOW_UP.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.FOLLOW_UP.API.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};

const handleSubmit = async () => {
  if (duration.value < 5) {
    useAlert(t('GENERAL_SETTINGS.FORM.FOLLOW_UP.DURATION.ERROR'));
    return Promise.resolve();
  }

  return updateAccountSettings({
    conversation_follow_up_wait_time: duration.value,
    conversation_follow_up_message: message.value,
    conversation_follow_up_max_count: maxCount.value,
    conversation_follow_up_after_bot: afterBot.value,
    conversation_follow_up_after_agent: afterAgent.value,
  });
};

const handleDisable = async () => {
  duration.value = null;
  message.value = '';
  maxCount.value = 1;
  afterBot.value = true;
  afterAgent.value = false;

  return updateAccountSettings({
    conversation_follow_up_wait_time: null,
    conversation_follow_up_message: '',
    conversation_follow_up_max_count: null,
    conversation_follow_up_after_bot: null,
    conversation_follow_up_after_agent: null,
  });
};

const toggleFollowUp = async () => {
  if (!isEnabled.value) handleDisable();
};
</script>

<template>
  <div
    class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
  >
    <div class="flex flex-col gap-2 items-start px-5 py-4">
      <div class="flex justify-between items-center w-full">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('GENERAL_SETTINGS.FORM.FOLLOW_UP.TITLE') }}
        </h3>
        <div class="flex justify-end">
          <Switch v-model="isEnabled" @change="toggleFollowUp" />
        </div>
      </div>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('GENERAL_SETTINGS.FORM.FOLLOW_UP.NOTE') }}
      </p>
    </div>

    <div v-if="isEnabled" class="px-5 py-4">
      <form class="grid gap-5" @submit.prevent="handleSubmit">
        <WithLabel
          :label="t('GENERAL_SETTINGS.FORM.FOLLOW_UP.DURATION.LABEL')"
          :help-message="t('GENERAL_SETTINGS.FORM.FOLLOW_UP.DURATION.HELP')"
        >
          <div class="gap-2 w-full grid grid-cols-[3fr_1fr]">
            <DurationInput
              v-model="duration"
              v-model:unit="unit"
              min="0"
              max="10080"
              class="w-full"
            />
          </div>
        </WithLabel>
        <WithLabel
          :label="t('GENERAL_SETTINGS.FORM.FOLLOW_UP.MESSAGE.LABEL')"
          :help-message="t('GENERAL_SETTINGS.FORM.FOLLOW_UP.MESSAGE.HELP')"
        >
          <TextArea
            v-model="message"
            class="w-full"
            :placeholder="
              t('GENERAL_SETTINGS.FORM.FOLLOW_UP.MESSAGE.PLACEHOLDER')
            "
          />
        </WithLabel>
        <WithLabel
          :label="t('GENERAL_SETTINGS.FORM.FOLLOW_UP.MAX_COUNT.LABEL')"
          :help-message="t('GENERAL_SETTINGS.FORM.FOLLOW_UP.MAX_COUNT.HELP')"
        >
          <input
            v-model.number="maxCount"
            type="number"
            min="1"
            max="10"
            class="w-24 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
          />
        </WithLabel>
        <WithLabel :label="t('GENERAL_SETTINGS.FORM.FOLLOW_UP.TRIGGER.LABEL')">
          <div
            class="rounded-xl border border-n-weak bg-n-solid-1 w-full text-sm text-n-slate-12 divide-y divide-n-weak"
          >
            <div class="p-3 h-12 flex items-center justify-between">
              <span>
                {{ t('GENERAL_SETTINGS.FORM.FOLLOW_UP.TRIGGER.AFTER_BOT') }}
              </span>
              <Switch v-model="afterBot" />
            </div>
            <div class="p-3 h-12 flex items-center justify-between">
              <span>
                {{ t('GENERAL_SETTINGS.FORM.FOLLOW_UP.TRIGGER.AFTER_AGENT') }}
              </span>
              <Switch v-model="afterAgent" />
            </div>
          </div>
        </WithLabel>
        <div class="flex gap-2">
          <NextButton
            blue
            type="submit"
            :is-loading="isSubmitting"
            :label="t('GENERAL_SETTINGS.FORM.FOLLOW_UP.UPDATE_BUTTON')"
          />
        </div>
      </form>
    </div>
  </div>
</template>
