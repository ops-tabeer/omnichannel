/* global axios */
import ApiClient from './ApiClient';

class JivoScenariosAPI extends ApiClient {
  constructor() {
    super('jivo/assistants', { accountScoped: true });
  }

  list(assistantId) {
    return axios.get(`${this.url}/${assistantId}/scenarios`);
  }

  show(assistantId, id) {
    return axios.get(`${this.url}/${assistantId}/scenarios/${id}`);
  }

  create(assistantId, data) {
    return axios.post(`${this.url}/${assistantId}/scenarios`, {
      scenario: data,
    });
  }

  update(assistantId, id, data) {
    return axios.patch(`${this.url}/${assistantId}/scenarios/${id}`, {
      scenario: data,
    });
  }

  delete(assistantId, id) {
    return axios.delete(`${this.url}/${assistantId}/scenarios/${id}`);
  }
}

export default new JivoScenariosAPI();
