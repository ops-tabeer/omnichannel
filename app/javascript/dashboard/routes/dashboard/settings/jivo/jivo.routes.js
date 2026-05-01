import Index from './Index.vue';
import Documents from './Documents.vue';
import Faqs from './Faqs.vue';
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
        {
          path: ':assistantId/documents',
          name: 'jivo_documents',
          component: Documents,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: ':assistantId/faqs',
          name: 'jivo_faqs',
          component: Faqs,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
