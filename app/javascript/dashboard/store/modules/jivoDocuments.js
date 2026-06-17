import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import JivoDocumentsAPI from '../../api/jivoDocuments';
import { throwErrorMessage } from '../utils/api';

const types = {
  SET_UI_FLAG: 'SET_JIVO_DOCUMENTS_UI_FLAG',
  SET_RECORDS: 'SET_JIVO_DOCUMENTS',
  ADD_RECORD: 'ADD_JIVO_DOCUMENT',
  UPDATE_RECORD: 'UPDATE_JIVO_DOCUMENT',
  DELETE_RECORD: 'DELETE_JIVO_DOCUMENT',
};

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isDeleting: false,
    isRecrawling: false,
  },
};

export const getters = {
  getDocuments: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit }, assistantId) => {
    commit(types.SET_UI_FLAG, { isFetching: true });
    try {
      const response = await JivoDocumentsAPI.list(assistantId);
      commit(types.SET_RECORDS, response.data);
    } catch (error) {
      // ignore
    } finally {
      commit(types.SET_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, { assistantId, ...data }) => {
    commit(types.SET_UI_FLAG, { isCreating: true });
    try {
      const response = await JivoDocumentsAPI.create(assistantId, data);
      commit(types.ADD_RECORD, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isCreating: false });
    }
    return null;
  },

  delete: async ({ commit }, { assistantId, id }) => {
    commit(types.SET_UI_FLAG, { isDeleting: true });
    try {
      await JivoDocumentsAPI.delete(assistantId, id);
      commit(types.DELETE_RECORD, id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isDeleting: false });
    }
  },

  recrawl: async ({ commit }, { assistantId, id }) => {
    commit(types.SET_UI_FLAG, { isRecrawling: true });
    try {
      const response = await JivoDocumentsAPI.recrawl(assistantId, id);
      commit(types.UPDATE_RECORD, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isRecrawling: false });
    }
    return null;
  },
};

export const mutations = {
  [types.SET_UI_FLAG]($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  [types.SET_RECORDS]: MutationHelpers.set,
  [types.ADD_RECORD]: MutationHelpers.create,
  [types.UPDATE_RECORD]: MutationHelpers.update,
  [types.DELETE_RECORD]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
