/* global axios */
import ApiClient from './ApiClient';

class JivoAssistantsAPI extends ApiClient {
  constructor() {
    super('jivo/assistants', { accountScoped: true });
  }

  getInboxes(assistantId) {
    return axios.get(`${this.url}/${assistantId}/inboxes`);
  }

  connectInbox(assistantId, inboxId) {
    return axios.post(`${this.url}/${assistantId}/inboxes`, {
      inbox_id: inboxId,
    });
  }

  disconnectInbox(assistantId, inboxId) {
    return axios.delete(`${this.url}/${assistantId}/inboxes/${inboxId}`);
  }

  uploadAvatar(assistantId, file) {
    const formData = new FormData();
    formData.append('avatar', file);
    return axios.post(`${this.url}/${assistantId}/avatar`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  removeAvatar(assistantId) {
    return axios.delete(`${this.url}/${assistantId}/avatar`);
  }
}

export default new JivoAssistantsAPI();
