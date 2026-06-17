import { ref, computed } from 'vue';
import { useMapGetter, useFunctionGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useTrack } from 'dashboard/composables';
import JivoTasksAPI from 'dashboard/api/jivoTasks';
import { CAPTAIN_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import {
  CAPTAIN_ERROR_TYPES,
  CAPTAIN_GENERATION_FAILURE_REASONS,
} from 'dashboard/composables/captain/constants';

// Actions that map to REWRITE events (with operation attribute)
const REWRITE_ACTIONS = [
  'improve',
  'fix_spelling_grammar',
  'casual',
  'professional',
  'friendly',
  'confident',
  'straightforward',
];

/**
 * Gets the event key suffix based on action type.
 * @param {string} action - The action type
 * @returns {string} The event key prefix (REWRITE, SUMMARIZE, or REPLY_SUGGESTION)
 */
function getEventPrefix(action) {
  if (action === 'summarize') return 'SUMMARIZE';
  if (action === 'reply_suggestion') return 'REPLY_SUGGESTION';
  return 'REWRITE';
}

/**
 * Builds the analytics payload based on action type.
 * @param {string} action - The action type
 * @param {number} conversationId - The conversation ID
 * @param {number} [followUpCount] - Optional follow-up count
 * @returns {Object} The payload object
 */
function buildPayload(action, conversationId, followUpCount = undefined) {
  const payload = { conversationId };

  if (REWRITE_ACTIONS.includes(action)) {
    payload.operation = action;
  }

  if (followUpCount !== undefined) {
    payload.followUpCount = followUpCount;
  }

  return payload;
}

function trackGenerationFailure({
  action,
  conversationId,
  followUpCount = undefined,
  stage,
  reason,
}) {
  useTrack(CAPTAIN_EVENTS.GENERATION_FAILED, {
    ...buildPayload(action, conversationId, followUpCount),
    stage,
    reason,
  });
}

/**
 * Composable for managing Jivo Copilot reply generation state and actions.
 * Mirror of Captain's useCopilotReply but using JivoTasksAPI.
 *
 * @returns {Object} Jivo Copilot reply state and methods
 */
export function useJivoCopilotReply() {
  const { updateUISettings } = useUISettings();

  const showEditor = ref(false);
  const isGenerating = ref(false);
  const isContentReady = ref(false);
  const generatedContent = ref('');
  const followUpContext = ref(null);
  const abortController = ref(null);

  // Tracking state
  const currentAction = ref(null);
  const followUpCount = ref(0);
  const trackedConversationId = ref(null);

  const currentChat = useMapGetter('getSelectedChat');
  const conversationId = computed(() => currentChat.value?.id);

  const replyMode = useMapGetter('draftMessages/getReplyEditorMode');
  const draftKey = computed(
    () => `draft-${conversationId.value}-${replyMode.value}`
  );
  const draftMessage = useFunctionGetter('draftMessages/get', draftKey);

  const isActive = computed(() => showEditor.value || isGenerating.value);
  const isButtonDisabled = computed(
    () => isGenerating.value || !isContentReady.value
  );
  const editorTransitionKey = computed(() =>
    isActive.value ? 'jivo-copilot' : 'rich'
  );

  /**
   * Resets all copilot editor state and cancels any ongoing generation.
   * @param {boolean} [trackDismiss=true] - Whether to track dismiss event
   */
  function reset(trackDismiss = true) {
    if (trackDismiss && generatedContent.value && currentAction.value) {
      const eventKey = `${getEventPrefix(currentAction.value)}_DISMISSED`;
      useTrack(
        CAPTAIN_EVENTS[eventKey],
        buildPayload(
          currentAction.value,
          trackedConversationId.value,
          followUpCount.value
        )
      );
    }

    if (abortController.value) {
      abortController.value.abort();
      abortController.value = null;
    }
    showEditor.value = false;
    isGenerating.value = false;
    isContentReady.value = false;
    generatedContent.value = '';
    followUpContext.value = null;
    currentAction.value = null;
    followUpCount.value = 0;
    trackedConversationId.value = null;
  }

  /**
   * Toggles the copilot editor visibility.
   */
  function toggleEditor() {
    showEditor.value = !showEditor.value;
  }

  /**
   * Marks content as ready (called after transition completes).
   */
  function setContentReady() {
    isContentReady.value = true;
  }

  /**
   * Executes a jivo copilot action.
   * @param {string} action - The action type
   * @param {string} data - The content to process (for rewrite)
   */
  async function execute(action, data) {
    if (action === 'ask_copilot') {
      // On enterprise instances, open the copilot sidebar panel.
      // On non-enterprise, fall back to generating a reply suggestion inline.
      const config = window.chatwootConfig || {};
      const isEnterprise = config.isEnterprise === 'true';
      if (isEnterprise) {
        updateUISettings({
          is_contact_sidebar_open: false,
          is_copilot_panel_open: true,
        });
        return;
      }
      // eslint-disable-next-line no-param-reassign
      action = 'reply_suggestion';
    }

    if (action === 'learn_from_conversation') {
      try {
        await JivoTasksAPI.learnFromConversation({
          conversationDisplayId: conversationId.value,
        });
      } catch {
        // silently fail
      }
      return;
    }

    reset(false);
    const requestController = new AbortController();
    abortController.value = requestController;
    isGenerating.value = true;
    isContentReady.value = false;
    currentAction.value = action;
    followUpCount.value = 0;
    trackedConversationId.value = conversationId.value;

    try {
      let apiCall;
      if (action === 'summarize') {
        apiCall = JivoTasksAPI.summarize({
          conversationDisplayId: conversationId.value,
        });
      } else if (action === 'reply_suggestion') {
        apiCall = JivoTasksAPI.replySuggestion({
          conversationDisplayId: conversationId.value,
        });
      } else {
        apiCall = JivoTasksAPI.rewrite({
          content: data || draftMessage.value,
          operation: action,
          conversationDisplayId: conversationId.value,
        });
      }

      const { data: response } = await apiCall;

      if (requestController.signal.aborted) return;

      if (response.success) {
        generatedContent.value = response.message;
        followUpContext.value = response.follow_up_context;
        showEditor.value = true;
        const eventKey = `${getEventPrefix(action)}_USED`;
        useTrack(
          CAPTAIN_EVENTS[eventKey],
          buildPayload(action, trackedConversationId.value)
        );
      } else {
        trackGenerationFailure({
          action,
          conversationId: trackedConversationId.value,
          stage: 'initial',
          reason:
            response.error || CAPTAIN_GENERATION_FAILURE_REASONS.EMPTY_RESPONSE,
        });
      }
      isGenerating.value = false;
    } catch (error) {
      if (
        requestController.signal.aborted ||
        error?.name === CAPTAIN_ERROR_TYPES.ABORT_ERROR ||
        error?.name === CAPTAIN_ERROR_TYPES.CANCELED_ERROR
      ) {
        return;
      }
      trackGenerationFailure({
        action,
        conversationId: trackedConversationId.value,
        stage: 'initial',
        reason: error?.name || CAPTAIN_GENERATION_FAILURE_REASONS.EXCEPTION,
      });
      isGenerating.value = false;
    } finally {
      if (abortController.value === requestController) {
        abortController.value = null;
      }
    }
  }

  /**
   * Sends a follow-up message to refine the current generated content.
   * @param {string} message - The follow-up message from the user
   */
  async function sendFollowUp(message) {
    if (!message.trim()) return;
    if (!followUpContext.value) {
      // console.error('Jivo Copilot: Cannot refine without follow-up context');
      return;
    }

    const requestController = new AbortController();
    abortController.value = requestController;
    isGenerating.value = true;
    isContentReady.value = false;

    useTrack(CAPTAIN_EVENTS.FOLLOW_UP_SENT, {
      conversationId: trackedConversationId.value,
    });
    followUpCount.value += 1;

    try {
      const { data: response } = await JivoTasksAPI.followUp({
        followUpContext: followUpContext.value,
        message,
        signal: requestController.signal,
      });

      if (requestController.signal.aborted) return;

      if (response.success) {
        generatedContent.value = response.message;
        followUpContext.value = response.follow_up_context;
        showEditor.value = true;
      } else {
        trackGenerationFailure({
          action: currentAction.value,
          conversationId: trackedConversationId.value,
          followUpCount: followUpCount.value,
          stage: 'follow_up',
          reason:
            response.error || CAPTAIN_GENERATION_FAILURE_REASONS.EMPTY_RESPONSE,
        });
      }
      isGenerating.value = false;
    } catch (error) {
      if (
        requestController.signal.aborted ||
        error?.name === CAPTAIN_ERROR_TYPES.ABORT_ERROR ||
        error?.name === CAPTAIN_ERROR_TYPES.CANCELED_ERROR
      ) {
        return;
      }
      trackGenerationFailure({
        action: currentAction.value,
        conversationId: trackedConversationId.value,
        followUpCount: followUpCount.value,
        stage: 'follow_up',
        reason: error?.name || CAPTAIN_GENERATION_FAILURE_REASONS.EXCEPTION,
      });
      isGenerating.value = false;
    } finally {
      if (abortController.value === requestController) {
        abortController.value = null;
      }
    }
  }

  /**
   * Accepts the generated content and returns it.
   * @returns {string} The content ready for the editor
   */
  function accept() {
    const content = generatedContent.value;

    if (currentAction.value) {
      const eventKey = `${getEventPrefix(currentAction.value)}_APPLIED`;
      useTrack(
        CAPTAIN_EVENTS[eventKey],
        buildPayload(
          currentAction.value,
          trackedConversationId.value,
          followUpCount.value
        )
      );
    }

    reset(false);
    return content;
  }

  return {
    showEditor,
    isGenerating,
    isContentReady,
    generatedContent,
    followUpContext,
    isActive,
    isButtonDisabled,
    editorTransitionKey,
    reset,
    toggleEditor,
    setContentReady,
    execute,
    sendFollowUp,
    accept,
  };
}
