import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import JivoAssistantsAPI from '../../api/jivoAssistants';
import { throwErrorMessage } from '../utils/api';

const types = {
  SET_UI_FLAG: 'SET_JIVO_ASSISTANTS_UI_FLAG',
  SET_RECORDS: 'SET_JIVO_ASSISTANTS',
  ADD_RECORD: 'ADD_JIVO_ASSISTANT',
  EDIT_RECORD: 'EDIT_JIVO_ASSISTANT',
  DELETE_RECORD: 'DELETE_JIVO_ASSISTANT',
};

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getAssistants: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
  getAssistant: $state => id => {
    return $state.records.find(record => record.id === Number(id)) || {};
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_UI_FLAG, { isFetching: true });
    try {
      const response = await JivoAssistantsAPI.get();
      commit(types.SET_RECORDS, response.data);
    } catch (error) {
      // ignore
    } finally {
      commit(types.SET_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit(types.SET_UI_FLAG, { isCreating: true });
    try {
      const response = await JivoAssistantsAPI.create(data);
      commit(types.ADD_RECORD, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isCreating: false });
    }
    return null;
  },

  update: async ({ commit }, { id, ...data }) => {
    commit(types.SET_UI_FLAG, { isUpdating: true });
    try {
      const response = await JivoAssistantsAPI.update(id, data);
      commit(types.EDIT_RECORD, response.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_UI_FLAG, { isDeleting: true });
    try {
      await JivoAssistantsAPI.delete(id);
      commit(types.DELETE_RECORD, id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isDeleting: false });
    }
  },

  uploadAvatar: async ({ commit }, { id, file }) => {
    try {
      const response = await JivoAssistantsAPI.uploadAvatar(id, file);
      commit(types.EDIT_RECORD, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
    }
    return null;
  },

  removeAvatar: async ({ commit }, id) => {
    try {
      const response = await JivoAssistantsAPI.removeAvatar(id);
      commit(types.EDIT_RECORD, response.data);
    } catch (error) {
      throwErrorMessage(error);
    }
  },

  connectInbox: async ({ dispatch }, { assistantId, inboxId }) => {
    try {
      await JivoAssistantsAPI.connectInbox(assistantId, inboxId);
      await dispatch('get');
    } catch (error) {
      throwErrorMessage(error);
    }
  },

  disconnectInbox: async ({ dispatch }, { assistantId, inboxId }) => {
    try {
      await JivoAssistantsAPI.disconnectInbox(assistantId, inboxId);
      await dispatch('get');
    } catch (error) {
      throwErrorMessage(error);
    }
  },
};

export const mutations = {
  [types.SET_UI_FLAG]($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  [types.SET_RECORDS]: MutationHelpers.set,
  [types.ADD_RECORD]: MutationHelpers.create,
  [types.EDIT_RECORD]: MutationHelpers.update,
  [types.DELETE_RECORD]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
