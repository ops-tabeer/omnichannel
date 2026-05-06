import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import JivoScenariosAPI from '../../api/jivoScenarios';
import { throwErrorMessage } from '../utils/api';

const types = {
  SET_UI_FLAG: 'SET_JIVO_SCENARIOS_UI_FLAG',
  SET_RECORDS: 'SET_JIVO_SCENARIOS',
  ADD_RECORD: 'ADD_JIVO_SCENARIO',
  EDIT_RECORD: 'EDIT_JIVO_SCENARIO',
  DELETE_RECORD: 'DELETE_JIVO_SCENARIO',
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
  getScenarios: $state => $state.records,
  getScenario: $state => id => $state.records.find(record => record.id === id),
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit }, assistantId) => {
    commit(types.SET_UI_FLAG, { isFetching: true });
    try {
      const response = await JivoScenariosAPI.list(assistantId);
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
      const response = await JivoScenariosAPI.create(assistantId, data);
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
      const response = await JivoScenariosAPI.update(assistantId, id, data);
      commit(types.EDIT_RECORD, response.data);
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isUpdating: false });
    }
    return null;
  },

  delete: async ({ commit }, { assistantId, id }) => {
    commit(types.SET_UI_FLAG, { isDeleting: true });
    try {
      await JivoScenariosAPI.delete(assistantId, id);
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
