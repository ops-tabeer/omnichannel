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
    if (data.file) {
      const formData = new FormData();
      formData.append('document[file]', data.file);
      if (data.name) formData.append('document[name]', data.name);
      return axios.post(`${this.url}/${assistantId}/documents`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
    }
    return axios.post(`${this.url}/${assistantId}/documents`, {
      document: data,
    });
  }

  delete(assistantId, documentId) {
    return axios.delete(`${this.url}/${assistantId}/documents/${documentId}`);
  }

  recrawl(assistantId, documentId) {
    return axios.post(
      `${this.url}/${assistantId}/documents/${documentId}/recrawl`
    );
  }
}

export default new JivoDocumentsAPI();
