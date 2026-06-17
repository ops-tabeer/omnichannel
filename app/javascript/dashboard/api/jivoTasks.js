/* global axios */
import ApiClient from './ApiClient';

class JivoTasksAPI extends ApiClient {
  constructor() {
    super('jivo/tasks', { accountScoped: true });
  }

  rewrite({ content, operation, conversationDisplayId } = {}) {
    return axios.post(`${this.url}/rewrite`, {
      content,
      operation,
      conversation_display_id: conversationDisplayId,
    });
  }

  summarize({ conversationDisplayId } = {}) {
    return axios.post(`${this.url}/summarize`, {
      conversation_display_id: conversationDisplayId,
    });
  }

  replySuggestion({ conversationDisplayId } = {}) {
    return axios.post(`${this.url}/reply_suggestion`, {
      conversation_display_id: conversationDisplayId,
    });
  }

  labelSuggestion({ conversationDisplayId } = {}) {
    return axios.post(`${this.url}/label_suggestion`, {
      conversation_display_id: conversationDisplayId,
    });
  }

  followUp({ followUpContext, message, signal } = {}) {
    return axios.post(
      `${this.url}/follow_up`,
      {
        follow_up_context: followUpContext,
        message,
      },
      { signal }
    );
  }

  learnFromConversation({ conversationDisplayId } = {}) {
    return axios.post(`${this.url}/learn_from_conversation`, {
      conversation_display_id: conversationDisplayId,
    });
  }
}

export default new JivoTasksAPI();
