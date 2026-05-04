<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import JivoTasksAPI from 'dashboard/api/jivoTasks';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  conversationDisplayId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['close', 'applyReply']);

const { t } = useI18n();
const { isAdmin } = useAdmin();

const activeTask = ref(null);
const isLoading = ref(false);
const result = ref('');
const followUpContext = ref(null);
const followUpInput = ref('');
const isLearning = ref(false);

const rewriteText = ref('');
const rewriteOperation = ref('improve');

const rewriteOperations = computed(() => [
  {
    value: 'fix_spelling_grammar',
    label: t('JIVO.TASKS.REWRITE.OPERATIONS.FIX_SPELLING_GRAMMAR'),
  },
  { value: 'improve', label: t('JIVO.TASKS.REWRITE.OPERATIONS.IMPROVE') },
  { value: 'casual', label: t('JIVO.TASKS.REWRITE.OPERATIONS.CASUAL') },
  {
    value: 'professional',
    label: t('JIVO.TASKS.REWRITE.OPERATIONS.PROFESSIONAL'),
  },
  { value: 'friendly', label: t('JIVO.TASKS.REWRITE.OPERATIONS.FRIENDLY') },
  { value: 'confident', label: t('JIVO.TASKS.REWRITE.OPERATIONS.CONFIDENT') },
  {
    value: 'straightforward',
    label: t('JIVO.TASKS.REWRITE.OPERATIONS.STRAIGHTFORWARD'),
  },
]);

const resetState = () => {
  result.value = '';
  followUpContext.value = null;
  followUpInput.value = '';
};

const setActive = task => {
  activeTask.value = task;
  resetState();
};

const handleResponse = (response, eventName) => {
  if (response.success) {
    result.value = response.message;
    followUpContext.value = response.follow_up_context || {
      event_name: eventName,
      original_context: null,
      last_response: response.message,
      conversation_history: [],
    };
  } else {
    useAlert(response.error || t('JIVO.TASKS.ERROR'));
  }
};

const runSummarize = async () => {
  isLoading.value = true;
  resetState();
  try {
    const { data } = await JivoTasksAPI.summarize({
      conversationDisplayId: props.conversationDisplayId,
    });
    handleResponse(data, 'summarize');
  } catch (error) {
    useAlert(error.message || t('JIVO.TASKS.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const runReplySuggestion = async () => {
  isLoading.value = true;
  resetState();
  try {
    const { data } = await JivoTasksAPI.replySuggestion({
      conversationDisplayId: props.conversationDisplayId,
    });
    handleResponse(data, 'reply_suggestion');
  } catch (error) {
    useAlert(error.message || t('JIVO.TASKS.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const runLabelSuggestion = async () => {
  isLoading.value = true;
  resetState();
  try {
    const { data } = await JivoTasksAPI.labelSuggestion({
      conversationDisplayId: props.conversationDisplayId,
    });
    handleResponse(data, 'label_suggestion');
  } catch (error) {
    useAlert(error.message || t('JIVO.TASKS.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const runRewrite = async () => {
  if (!rewriteText.value.trim()) return;
  isLoading.value = true;
  resetState();
  try {
    const { data } = await JivoTasksAPI.rewrite({
      content: rewriteText.value,
      operation: rewriteOperation.value,
      conversationDisplayId: props.conversationDisplayId,
    });
    handleResponse(data, rewriteOperation.value);
  } catch (error) {
    useAlert(error.message || t('JIVO.TASKS.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const runFollowUp = async () => {
  if (!followUpInput.value.trim() || !followUpContext.value) return;
  isLoading.value = true;
  try {
    const { data } = await JivoTasksAPI.followUp({
      followUpContext: followUpContext.value,
      message: followUpInput.value,
    });
    if (data.success) {
      result.value = data.message;
      followUpContext.value = data.follow_up_context;
      followUpInput.value = '';
    } else {
      useAlert(data.error || t('JIVO.TASKS.ERROR'));
    }
  } catch (error) {
    useAlert(error.message || t('JIVO.TASKS.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const runLearnFromConversation = async () => {
  if (isLearning.value) return;
  isLearning.value = true;
  try {
    const { data } = await JivoTasksAPI.learnFromConversation({
      conversationDisplayId: props.conversationDisplayId,
    });
    if (data.success) {
      useAlert(data.message || t('JIVO.TASKS.LEARN.QUEUED'));
    } else {
      useAlert(data.error || t('JIVO.TASKS.ERROR'));
    }
  } catch (error) {
    useAlert(error.message || t('JIVO.TASKS.ERROR'));
  } finally {
    isLearning.value = false;
  }
};

const copyResult = async () => {
  if (!result.value) return;
  try {
    await navigator.clipboard.writeText(result.value);
    useAlert(t('JIVO.TASKS.COPIED'));
  } catch (error) {
    useAlert(t('JIVO.TASKS.COPY_FAILED'));
  }
};

const useAsReply = () => {
  if (!result.value) return;
  emit('applyReply', result.value);
  emit('close');
};

const canApplyToReply = computed(
  () =>
    activeTask.value === 'reply_suggestion' ||
    (activeTask.value === 'rewrite' && result.value)
);
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('close')"
  >
    <div
      class="bg-n-solid-1 rounded-lg shadow-xl w-full max-w-2xl max-h-[90vh] flex flex-col"
    >
      <div class="p-4 border-b border-n-weak flex items-center justify-between">
        <h2
          class="text-lg font-semibold text-n-slate-12 flex items-center gap-2"
        >
          <span class="i-lucide-sparkles" />
          {{ t('JIVO.TASKS.PANEL_TITLE') }}
        </h2>
        <Button icon="i-lucide-x" slate xs faded @click="emit('close')" />
      </div>

      <div v-if="!activeTask" class="p-6 grid grid-cols-2 gap-3">
        <button
          class="p-4 border border-n-weak rounded-lg text-left hover:bg-n-alpha-black2 transition"
          @click="setActive('summarize')"
        >
          <div class="flex items-center gap-2 text-n-slate-12">
            <span class="i-lucide-file-text" />
            <span class="font-medium">{{
              t('JIVO.TASKS.SUMMARIZE.TITLE')
            }}</span>
          </div>
          <p class="text-xs text-n-slate-11 mt-1">
            {{ t('JIVO.TASKS.SUMMARIZE.DESCRIPTION') }}
          </p>
        </button>

        <button
          class="p-4 border border-n-weak rounded-lg text-left hover:bg-n-alpha-black2 transition"
          @click="setActive('reply_suggestion')"
        >
          <div class="flex items-center gap-2 text-n-slate-12">
            <span class="i-lucide-message-square-reply" />
            <span class="font-medium">{{ t('JIVO.TASKS.REPLY.TITLE') }}</span>
          </div>
          <p class="text-xs text-n-slate-11 mt-1">
            {{ t('JIVO.TASKS.REPLY.DESCRIPTION') }}
          </p>
        </button>

        <button
          class="p-4 border border-n-weak rounded-lg text-left hover:bg-n-alpha-black2 transition"
          @click="setActive('rewrite')"
        >
          <div class="flex items-center gap-2 text-n-slate-12">
            <span class="i-lucide-pen-line" />
            <span class="font-medium">{{ t('JIVO.TASKS.REWRITE.TITLE') }}</span>
          </div>
          <p class="text-xs text-n-slate-11 mt-1">
            {{ t('JIVO.TASKS.REWRITE.DESCRIPTION') }}
          </p>
        </button>

        <button
          class="p-4 border border-n-weak rounded-lg text-left hover:bg-n-alpha-black2 transition"
          @click="setActive('label_suggestion')"
        >
          <div class="flex items-center gap-2 text-n-slate-12">
            <span class="i-lucide-tags" />
            <span class="font-medium">{{ t('JIVO.TASKS.LABEL.TITLE') }}</span>
          </div>
          <p class="text-xs text-n-slate-11 mt-1">
            {{ t('JIVO.TASKS.LABEL.DESCRIPTION') }}
          </p>
        </button>

        <button
          v-if="isAdmin"
          class="p-4 border border-n-weak rounded-lg text-left hover:bg-n-alpha-black2 transition disabled:opacity-50 disabled:cursor-not-allowed col-span-2"
          :disabled="isLearning"
          @click="runLearnFromConversation"
        >
          <div class="flex items-center gap-2 text-n-slate-12">
            <span
              :class="
                isLearning ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-brain'
              "
            />
            <span class="font-medium">{{ t('JIVO.TASKS.LEARN.TITLE') }}</span>
          </div>
          <p class="text-xs text-n-slate-11 mt-1">
            {{ t('JIVO.TASKS.LEARN.DESCRIPTION') }}
          </p>
        </button>
      </div>

      <div v-else class="p-6 overflow-y-auto flex-1 space-y-4">
        <button
          class="text-sm text-n-blue-text hover:underline flex items-center gap-1"
          @click="setActive(null)"
        >
          <span class="i-lucide-arrow-left" />
          {{ t('JIVO.TASKS.BACK') }}
        </button>

        <div v-if="activeTask === 'rewrite'" class="space-y-3">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JIVO.TASKS.REWRITE.TITLE') }}
          </h3>
          <textarea
            v-model="rewriteText"
            rows="4"
            :placeholder="t('JIVO.TASKS.REWRITE.PLACEHOLDER')"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          />
          <select
            v-model="rewriteOperation"
            class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12"
          >
            <option
              v-for="op in rewriteOperations"
              :key="op.value"
              :value="op.value"
            >
              {{ op.label }}
            </option>
          </select>
          <Button
            :label="t('JIVO.TASKS.RUN')"
            :is-loading="isLoading"
            :disabled="!rewriteText.trim()"
            @click="runRewrite"
          />
        </div>

        <div v-else-if="activeTask === 'summarize'" class="space-y-3">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JIVO.TASKS.SUMMARIZE.TITLE') }}
          </h3>
          <Button
            v-if="!result"
            :label="t('JIVO.TASKS.SUMMARIZE.RUN')"
            :is-loading="isLoading"
            @click="runSummarize"
          />
        </div>

        <div v-else-if="activeTask === 'reply_suggestion'" class="space-y-3">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JIVO.TASKS.REPLY.TITLE') }}
          </h3>
          <Button
            v-if="!result"
            :label="t('JIVO.TASKS.REPLY.RUN')"
            :is-loading="isLoading"
            @click="runReplySuggestion"
          />
        </div>

        <div v-else-if="activeTask === 'label_suggestion'" class="space-y-3">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JIVO.TASKS.LABEL.TITLE') }}
          </h3>
          <Button
            v-if="!result"
            :label="t('JIVO.TASKS.LABEL.RUN')"
            :is-loading="isLoading"
            @click="runLabelSuggestion"
          />
        </div>

        <div v-if="result" class="space-y-3">
          <div class="p-4 bg-n-alpha-black2 border border-n-weak rounded-md">
            <p class="text-sm text-n-slate-12 whitespace-pre-line">
              {{ result }}
            </p>
          </div>

          <div class="flex gap-2 flex-wrap">
            <Button
              :label="t('JIVO.TASKS.COPY')"
              icon="i-lucide-copy"
              slate
              xs
              faded
              @click="copyResult"
            />
            <Button
              v-if="canApplyToReply"
              :label="t('JIVO.TASKS.APPLY_REPLY')"
              icon="i-lucide-arrow-right"
              xs
              @click="useAsReply"
            />
          </div>

          <div class="pt-3 border-t border-n-weak">
            <label class="block text-sm font-medium text-n-slate-12 mb-1">
              {{ t('JIVO.TASKS.FOLLOW_UP_LABEL') }}
            </label>
            <div class="flex gap-2">
              <input
                v-model="followUpInput"
                type="text"
                :placeholder="t('JIVO.TASKS.FOLLOW_UP_PLACEHOLDER')"
                class="flex-1 px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                @keyup.enter="runFollowUp"
              />
              <Button
                :label="t('JIVO.TASKS.REFINE')"
                :is-loading="isLoading"
                :disabled="!followUpInput.trim()"
                @click="runFollowUp"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
