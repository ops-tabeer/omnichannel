/* global axios */
import ApiClient from '../ApiClient';

class EvolutionChannel extends ApiClient {
  constructor() {
    super('evolution', { accountScoped: true });
  }

  createInstance(params) {
    return axios.post(`${this.baseUrl()}/evolution/create_instance`, params);
  }

  refreshQr(instanceName) {
    return axios.get(`${this.baseUrl()}/evolution/refresh_qr`, {
      params: { instance_name: instanceName },
    });
  }

  connectionStatus(instanceName) {
    return axios.get(`${this.baseUrl()}/evolution/connection_status`, {
      params: { instance_name: instanceName },
    });
  }

  completeSetup(params) {
    return axios.post(`${this.baseUrl()}/evolution/complete_setup`, params);
  }
}

export default new EvolutionChannel();
