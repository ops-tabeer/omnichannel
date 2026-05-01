import Index from './Index.vue';
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/jivo'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'jivo_assistants',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
