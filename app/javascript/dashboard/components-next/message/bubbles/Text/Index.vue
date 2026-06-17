<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import { MESSAGE_TYPES } from '../../constants';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const { t } = useI18n();
const { content, attachments, contentAttributes, messageType } =
  useMessageContext();

const jivoScenarioLabel = computed(
  () => contentAttributes.value?.jivoScenario || ''
);

const jivoCitations = computed(() => {
  const raw = contentAttributes.value?.citations;
  if (!Array.isArray(raw)) return [];
  const seen = new Set();
  return raw
    .filter(c => c && (c.externalLink || c.documentName))
    .filter(c => {
      const key = `${c.documentId || ''}:${c.externalLink || c.documentName}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
});

const citationLabel = c => c.documentName || c.externalLink || c.question;

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const renderOriginal = ref(false);

const renderContent = computed(() => {
  if (renderOriginal.value) {
    return content.value;
  }

  if (hasTranslations.value) {
    return translationContent.value;
  }

  return content.value;
});

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="text">
    <div class="gap-3 flex flex-col">
      <span
        v-if="jivoScenarioLabel"
        class="inline-flex items-center gap-1 text-[10px] font-medium uppercase tracking-wide text-n-slate-11"
      >
        <span class="i-lucide-sparkles size-3" />
        {{ t('JIVO.MESSAGE.AGENT_BADGE', { name: jivoScenarioLabel }) }}
      </span>
      <span v-if="isEmpty" class="text-n-slate-11">
        {{ $t('CONVERSATION.NO_CONTENT') }}
      </span>
      <FormattedContent v-if="renderContent" :content="renderContent" />
      <TranslationToggle
        v-if="hasTranslations"
        class="-mt-3"
        :showing-original="renderOriginal"
        @toggle="handleSeeOriginal"
      />
      <div v-if="jivoCitations.length" class="flex flex-wrap gap-1.5 -mt-1">
        <template v-for="(citation, idx) in jivoCitations" :key="idx">
          <a
            v-if="citation.externalLink"
            :href="citation.externalLink"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 hover:underline max-w-full"
          >
            <span class="i-lucide-external-link size-3 shrink-0" />
            <span class="truncate">
              {{
                t('JIVO.MESSAGE.CITATIONS.SOURCE', {
                  title: citationLabel(citation),
                })
              }}
            </span>
          </a>
          <span
            v-else
            class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-medium rounded-full bg-n-alpha-2 text-n-slate-11 max-w-full"
          >
            <span class="i-lucide-file-text size-3 shrink-0" />
            <span class="truncate">
              {{
                t('JIVO.MESSAGE.CITATIONS.SOURCE', {
                  title: citationLabel(citation),
                })
              }}
            </span>
          </span>
        </template>
      </div>
      <AttachmentChips :attachments="attachments" class="gap-2" />
      <template v-if="isTemplate">
        <div
          v-if="contentAttributes.submittedEmail"
          class="px-2 py-1 rounded-lg bg-n-alpha-3"
        >
          {{ contentAttributes.submittedEmail }}
        </div>
      </template>
    </div>
  </BaseBubble>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
