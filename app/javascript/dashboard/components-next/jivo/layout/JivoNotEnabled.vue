<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const { t } = useI18n();
</script>

<template>
  <div
    class="w-full max-w-[60rem] mx-auto h-full max-h-[448px] grid place-content-center"
  >
    <div
      class="flex flex-col max-w-md px-6 py-6 border shadow bg-n-solid-1 rounded-xl border-n-weak"
    >
      <div class="flex items-center w-full gap-2 mb-4">
        <span
          class="flex items-center justify-center w-6 h-6 rounded-full bg-n-solid-blue"
        >
          <Icon
            class="flex-shrink-0 text-n-brand size-[14px]"
            icon="i-lucide-lock-keyhole"
          />
        </span>
        <span class="text-base font-medium text-n-slate-12">
          {{ t('JIVO.NOT_ENABLED.TITLE') }}
        </span>
      </div>
      <p class="text-sm font-normal text-n-slate-11 mb-2">
        {{ t('JIVO.NOT_ENABLED.DESCRIPTION') }}
      </p>
      <p class="text-sm font-normal text-n-slate-11">
        {{ t('JIVO.NOT_ENABLED.ASK_ADMIN') }}
      </p>
    </div>
  </div>
</template>
