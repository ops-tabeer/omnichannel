import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import JivoCustomToolsAPI from '../../api/jivoCustomTools';
import { throwErrorMessage } from '../utils/api';

const types = {
  SET_UI_FLAG: 'SET_JIVO_CUSTOM_TOOLS_UI_FLAG',
  SET_RECORDS: 'SET_JIVO_CUSTOM_TOOLS',
  ADD_RECORD: 'ADD_JIVO_CUSTOM_TOOL',
  EDIT_RECORD: 'EDIT_JIVO_CUSTOM_TOOL',
  DELETE_RECORD: 'DELETE_JIVO_CUSTOM_TOOL',
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
  getCustomTools: $state => $state.records,
  getCustomTool: $state => id =>
    $state.records.find(record => record.id === id),
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_UI_FLAG, { isFetching: true });
    try {
      const response = await JivoCustomToolsAPI.get();
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
      const response = await JivoCustomToolsAPI.create(data);
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
      const response = await JivoCustomToolsAPI.update(id, data);
      commit(types.EDIT_RECORD, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isUpdating: false });
    }
    return null;
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_UI_FLAG, { isDeleting: true });
    try {
      await JivoCustomToolsAPI.delete(id);
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
