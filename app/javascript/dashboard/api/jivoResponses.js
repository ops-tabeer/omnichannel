/* global axios */
import ApiClient from './ApiClient';

class JivoResponsesAPI extends ApiClient {
  constructor() {
    super('jivo/assistants', { accountScoped: true });
  }

  list(assistantId, { status } = {}) {
    const params = status ? { status } : {};
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
}

export default new JivoResponsesAPI();
