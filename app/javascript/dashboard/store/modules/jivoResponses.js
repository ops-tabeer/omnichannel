import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import JivoResponsesAPI from '../../api/jivoResponses';
import { throwErrorMessage } from '../utils/api';

const types = {
  SET_UI_FLAG: 'SET_JIVO_RESPONSES_UI_FLAG',
  SET_RECORDS: 'SET_JIVO_RESPONSES',
  SET_META: 'SET_JIVO_RESPONSES_META',
  ADD_RECORD: 'ADD_JIVO_RESPONSE',
  EDIT_RECORD: 'EDIT_JIVO_RESPONSE',
  DELETE_RECORD: 'DELETE_JIVO_RESPONSE',
  DELETE_RECORDS: 'DELETE_JIVO_RESPONSES',
};

export const state = {
  records: [],
  meta: {
    totalCount: 0,
    page: 1,
  },
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isBulkUpdating: false,
  },
};

export const getters = {
  getResponses: $state => $state.records,
  getMeta: $state => $state.meta,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit }, { assistantId, status, query, page }) => {
    commit(types.SET_UI_FLAG, { isFetching: true });
    try {
      const response = await JivoResponsesAPI.list(assistantId, {
        status,
        query,
        page,
      });
      const { payload, meta } = response.data;
      commit(types.SET_RECORDS, payload);
      commit(types.SET_META, meta);
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

  bulkApprove: async ({ commit }, { assistantId, ids }) => {
    commit(types.SET_UI_FLAG, { isBulkUpdating: true });
    try {
      const response = await JivoResponsesAPI.bulkApprove(assistantId, ids);
      response.data.forEach(record => commit(types.EDIT_RECORD, record));
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isBulkUpdating: false });
    }
    return [];
  },

  bulkReject: async ({ commit }, { assistantId, ids }) => {
    commit(types.SET_UI_FLAG, { isBulkUpdating: true });
    try {
      await JivoResponsesAPI.bulkReject(assistantId, ids);
      commit(types.DELETE_RECORDS, ids);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isBulkUpdating: false });
    }
  },

  bulkDelete: async ({ commit }, { assistantId, ids }) => {
    commit(types.SET_UI_FLAG, { isBulkUpdating: true });
    try {
      await JivoResponsesAPI.bulkDelete(assistantId, ids);
      commit(types.DELETE_RECORDS, ids);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { isBulkUpdating: false });
    }
  },
};

export const mutations = {
  [types.SET_UI_FLAG]($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
  [types.SET_META]($state, meta) {
    $state.meta = {
      ...$state.meta,
      totalCount: Number(meta.total_count),
      page: Number(meta.page),
    };
  },
  [types.SET_RECORDS]: MutationHelpers.set,
  [types.ADD_RECORD]: MutationHelpers.create,
  [types.EDIT_RECORD]: MutationHelpers.update,
  [types.DELETE_RECORD]: MutationHelpers.destroy,
  [types.DELETE_RECORDS]($state, ids) {
    $state.records = $state.records.filter(record => !ids.includes(record.id));
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
