/* global axios */
import ApiClient from './ApiClient';

class JivoCustomToolsAPI extends ApiClient {
  constructor() {
    super('jivo/custom_tools', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { custom_tool: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { custom_tool: data });
  }
}

export default new JivoCustomToolsAPI();
