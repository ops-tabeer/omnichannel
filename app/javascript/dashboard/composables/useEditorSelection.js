import { reactive, readonly } from 'vue';

const state = reactive({
  from: 0,
  to: 0,
  text: '',
});

export const setEditorSelection = ({ from, to, text }) => {
  state.from = from || 0;
  state.to = to || 0;
  state.text = text || '';
};

export const useEditorSelection = () => readonly(state);
