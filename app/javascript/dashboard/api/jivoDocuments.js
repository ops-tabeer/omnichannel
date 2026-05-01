/* global axios */
import ApiClient from './ApiClient';

class JivoDocumentsAPI extends ApiClient {
  constructor() {
    super('jivo/assistants', { accountScoped: true });
  }

  list(assistantId) {
    return axios.get(`${this.url}/${assistantId}/documents`);
  }

  create(assistantId, data) {
    return axios.post(`${this.url}/${assistantId}/documents`, {
      document: data,
    });
  }

  delete(assistantId, documentId) {
    return axios.delete(`${this.url}/${assistantId}/documents/${documentId}`);
  }
}

export default new JivoDocumentsAPI();
