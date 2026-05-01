import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import JivoResponsesAPI from '../../api/jivoResponses';
import { throwErrorMessage } from '../utils/api';

const types = {
  SET_UI_FLAG: 'SET_JIVO_RESPONSES_UI_FLAG',
  SET_RECORDS: 'SET_JIVO_RESPONSES',
  ADD_RECORD: 'ADD_JIVO_RESPONSE',
  EDIT_RECORD: 'EDIT_JIVO_RESPONSE',
  DELETE_RECORD: 'DELETE_JIVO_RESPONSE',
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
  getResponses: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit }, { assistantId, status }) => {
    commit(types.SET_UI_FLAG, { isFetching: true });
    try {
      const response = await JivoResponsesAPI.list(assistantId, { status });
      commit(types.SET_RECORDS, response.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, { assistantId, ...data }) => {
    commit(types.SET_UI_FLAG, { isCreating: true });
    try {
      const response = await JivoResponsesAPI.create(assistantId, data);
      commit(types.ADD_RECORD, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isCreating: false });
    }
    return null;
  },

  update: async ({ commit }, { assistantId, id, ...data }) => {
    commit(types.SET_UI_FLAG, { isUpdating: true });
    try {
      const response = await JivoResponsesAPI.update(assistantId, id, data);
      commit(types.EDIT_RECORD, response.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, { assistantId, id }) => {
    commit(types.SET_UI_FLAG, { isDeleting: true });
    try {
      await JivoResponsesAPI.delete(assistantId, id);
      commit(types.DELETE_RECORD, id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isDeleting: false });
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
