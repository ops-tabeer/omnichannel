import Index from './Index.vue';
import Documents from './Documents.vue';
import Faqs from './Faqs.vue';
import Scenarios from './Scenarios.vue';
import CustomTools from './CustomTools.vue';
import AssistantEdit from './AssistantEdit.vue';
import ScenarioEdit from './ScenarioEdit.vue';
import CustomToolEdit from './CustomToolEdit.vue';
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
          path: 'new',
          name: 'jivo_assistant_new',
          component: AssistantEdit,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: ':assistantId/edit',
          name: 'jivo_assistant_edit',
          component: AssistantEdit,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'custom_tools',
          name: 'jivo_custom_tools',
          component: CustomTools,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'custom_tools/new',
          name: 'jivo_custom_tool_new',
          component: CustomToolEdit,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'custom_tools/:id/edit',
          name: 'jivo_custom_tool_edit',
          component: CustomToolEdit,
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
        {
          path: ':assistantId/scenarios',
          name: 'jivo_scenarios',
          component: Scenarios,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: ':assistantId/scenarios/new',
          name: 'jivo_scenario_new',
          component: ScenarioEdit,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: ':assistantId/scenarios/:scenarioId/edit',
          name: 'jivo_scenario_edit',
          component: ScenarioEdit,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
