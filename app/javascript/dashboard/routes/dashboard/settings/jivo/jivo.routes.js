import Index from './Index.vue';
import Documents from './Documents.vue';
import Faqs from './Faqs.vue';
import Inboxes from './Inboxes.vue';
import Scenarios from './Scenarios.vue';
import CustomTools from './CustomTools.vue';
import AssistantEdit from './AssistantEdit.vue';
import ScenarioEdit from './ScenarioEdit.vue';
import CustomToolEdit from './CustomToolEdit.vue';
import Playground from './Playground.vue';
import AssistantsDispatcher from './AssistantsDispatcher.vue';
import { frontendURL } from '../../../../helper/URLHelper';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/jivo'),
      name: 'jivo_assistants',
      component: Index,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/new'),
      name: 'jivo_assistant_new',
      component: AssistantEdit,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/custom_tools'),
      name: 'jivo_custom_tools',
      component: CustomTools,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/custom_tools/new'),
      name: 'jivo_custom_tool_new',
      component: CustomToolEdit,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/custom_tools/:id/edit'),
      name: 'jivo_custom_tool_edit',
      component: CustomToolEdit,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/dispatch/:navigationPath'),
      name: 'jivo_assistants_dispatch',
      component: AssistantsDispatcher,
      meta: {
        permissions: ['administrator', 'agent'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/:assistantId/edit'),
      name: 'jivo_assistant_edit',
      component: AssistantEdit,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/:assistantId/documents'),
      name: 'jivo_documents',
      component: Documents,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/:assistantId/faqs'),
      name: 'jivo_faqs',
      component: Faqs,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/:assistantId/inboxes'),
      name: 'jivo_inboxes',
      component: Inboxes,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/:assistantId/scenarios'),
      name: 'jivo_scenarios',
      component: Scenarios,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/jivo/:assistantId/scenarios/new'),
      name: 'jivo_scenario_new',
      component: ScenarioEdit,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL(
        'accounts/:accountId/jivo/:assistantId/scenarios/:scenarioId/edit'
      ),
      name: 'jivo_scenario_edit',
      component: ScenarioEdit,
      meta: {
        permissions: ['administrator'],
      },
    },
    {
      path: frontendURL('accounts/:accountId/settings/jivo/:pathMatch(.*)*'),
      redirect: to => ({
        name: 'jivo_assistants',
        params: { accountId: to.params.accountId },
      }),
    },
    {
      path: frontendURL('accounts/:accountId/jivo/:assistantId/playground'),
      name: 'jivo_playground',
      component: Playground,
      meta: {
        permissions: ['administrator', 'agent'],
      },
    },
  ],
};
