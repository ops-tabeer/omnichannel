/* global axios */
import ApiClient from './ApiClient';

class JivoResponsesAPI extends ApiClient {
  constructor() {
    super('jivo/assistants', { accountScoped: true });
  }

  list(assistantId, { status, query, page = 1 } = {}) {
    const params = {
      page,
      ...(status ? { status } : {}),
      ...(query ? { query } : {}),
    };
    return axios.get(`${this.url}/${assistantId}/assistant_responses`, {
      params,
    });
  }

  create(assistantId, data) {
    return axios.post(`${this.url}/${assistantId}/assistant_responses`, {
      assistant_response: data,
    });
  }

  update(assistantId, responseId, data) {
    return axios.patch(
      `${this.url}/${assistantId}/assistant_responses/${responseId}`,
      { assistant_response: data }
    );
  }

  delete(assistantId, responseId) {
    return axios.delete(
      `${this.url}/${assistantId}/assistant_responses/${responseId}`
    );
  }

  bulkAction(assistantId, ids, status) {
    return axios.post(`${this.url}/${assistantId}/bulk_actions`, {
      ids,
      fields: { status },
    });
  }

  bulkApprove(assistantId, ids) {
    return this.bulkAction(assistantId, ids, 'approve');
  }

  bulkReject(assistantId, ids) {
    return this.bulkAction(assistantId, ids, 'reject');
  }

  bulkDelete(assistantId, ids) {
    return this.bulkAction(assistantId, ids, 'delete');
  }
}

export default new JivoResponsesAPI();
