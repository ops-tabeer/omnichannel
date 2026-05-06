<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import JivoToolIcon from 'dashboard/components-next/jivo/JivoToolIcon.vue';

const props = defineProps({
  mode: { type: String, default: 'create' },
  customTool: { type: Object, default: () => ({}) },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'close']);
const { t } = useI18n();

const form = ref({
  title: props.customTool.title || '',
  description: props.customTool.description || '',
  endpoint_url: props.customTool.endpoint_url || '',
  http_method: props.customTool.http_method || 'GET',
  auth_type: props.customTool.auth_type || 'none',
  auth_config: { ...(props.customTool.auth_config || {}) },
  param_schema: (props.customTool.param_schema || []).map(p => ({ ...p })),
  request_template: props.customTool.request_template || '',
  response_template: props.customTool.response_template || '',
  enabled:
    props.customTool.enabled === undefined ? true : props.customTool.enabled,
  rate_limit_per_minute: props.customTool.rate_limit_per_minute ?? null,
});

const isValid = computed(
  () =>
    form.value.title.trim() &&
    form.value.endpoint_url.trim() &&
    form.value.endpoint_url.startsWith('https://')
);

const addParam = () => {
  form.value.param_schema.push({
    name: '',
    type: 'string',
    description: '',
    required: true,
  });
};

const removeParam = index => {
  form.value.param_schema.splice(index, 1);
};

const submit = () => {
  if (!isValid.value) return;
  const rateLimit = Number(form.value.rate_limit_per_minute);
  const payload = {
    ...form.value,
    rate_limit_per_minute:
      Number.isFinite(rateLimit) && rateLimit > 0 ? rateLimit : null,
    param_schema: form.value.param_schema.filter(p => p.name.trim()),
  };
  emit('save', payload);
};
</script>

<template>
  <div class="bg-n-solid-1 rounded-lg border border-n-weak overflow-hidden">
    <div class="p-6 space-y-4">
      <div class="flex items-center gap-2 text-sm text-n-slate-11">
        <JivoToolIcon custom />
        <span>{{ t('JIVO.CUSTOM_TOOLS.FORM.HEADER_HINT') }}</span>
      </div>
      <Input
        v-model="form.title"
        :label="t('JIVO.CUSTOM_TOOLS.FORM.TITLE.LABEL')"
        :placeholder="t('JIVO.CUSTOM_TOOLS.FORM.TITLE.PLACEHOLDER')"
      />

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.DESCRIPTION.LABEL') }}
        </label>
        <textarea
          v-model="form.description"
          rows="2"
          :placeholder="t('JIVO.CUSTOM_TOOLS.FORM.DESCRIPTION.PLACEHOLDER')"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        />
      </div>

      <Input
        v-model="form.endpoint_url"
        :label="t('JIVO.CUSTOM_TOOLS.FORM.ENDPOINT_URL.LABEL')"
        :placeholder="t('JIVO.CUSTOM_TOOLS.FORM.ENDPOINT_URL.PLACEHOLDER')"
        :help-text="t('JIVO.CUSTOM_TOOLS.FORM.ENDPOINT_URL.HELP')"
      />

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.HTTP_METHOD.LABEL') }}
        </label>
        <select
          v-model="form.http_method"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12"
        >
          <option value="GET">
            {{ t('JIVO.CUSTOM_TOOLS.FORM.HTTP_METHOD.GET') }}
          </option>
          <option value="POST">
            {{ t('JIVO.CUSTOM_TOOLS.FORM.HTTP_METHOD.POST') }}
          </option>
        </select>
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.AUTH_TYPE.LABEL') }}
        </label>
        <select
          v-model="form.auth_type"
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12"
        >
          <option value="none">
            {{ t('JIVO.CUSTOM_TOOLS.FORM.AUTH_TYPE.NONE') }}
          </option>
          <option value="bearer">
            {{ t('JIVO.CUSTOM_TOOLS.FORM.AUTH_TYPE.BEARER') }}
          </option>
          <option value="basic">
            {{ t('JIVO.CUSTOM_TOOLS.FORM.AUTH_TYPE.BASIC') }}
          </option>
          <option value="api_key">
            {{ t('JIVO.CUSTOM_TOOLS.FORM.AUTH_TYPE.API_KEY') }}
          </option>
        </select>
      </div>

      <div v-if="form.auth_type === 'bearer'" class="space-y-3">
        <Input
          v-model="form.auth_config.token"
          :label="t('JIVO.CUSTOM_TOOLS.FORM.AUTH_CONFIG.BEARER_TOKEN')"
          type="password"
        />
      </div>

      <div v-if="form.auth_type === 'basic'" class="space-y-3">
        <Input
          v-model="form.auth_config.username"
          :label="t('JIVO.CUSTOM_TOOLS.FORM.AUTH_CONFIG.USERNAME')"
        />
        <Input
          v-model="form.auth_config.password"
          :label="t('JIVO.CUSTOM_TOOLS.FORM.AUTH_CONFIG.PASSWORD')"
          type="password"
        />
      </div>

      <div v-if="form.auth_type === 'api_key'" class="space-y-3">
        <Input
          v-model="form.auth_config.name"
          :label="t('JIVO.CUSTOM_TOOLS.FORM.AUTH_CONFIG.HEADER_NAME')"
          placeholder="X-API-Key"
        />
        <Input
          v-model="form.auth_config.key"
          :label="t('JIVO.CUSTOM_TOOLS.FORM.AUTH_CONFIG.HEADER_VALUE')"
          type="password"
        />
        <input v-model="form.auth_config.location" type="hidden" />
        <p class="text-xs text-n-slate-11">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.AUTH_CONFIG.HEADER_NOTE') }}
        </p>
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-2">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.PARAMS.LABEL') }}
        </label>
        <div class="space-y-2">
          <div
            v-for="(param, idx) in form.param_schema"
            :key="idx"
            class="flex gap-2 items-start p-2 border border-n-weak rounded-md"
          >
            <Input
              v-model="param.name"
              :placeholder="t('JIVO.CUSTOM_TOOLS.FORM.PARAMS.NAME')"
            />
            <select
              v-model="param.type"
              class="px-2 py-1 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 text-sm"
            >
              <option value="string">
                {{ t('JIVO.CUSTOM_TOOLS.FORM.PARAMS.TYPES.STRING') }}
              </option>
              <option value="number">
                {{ t('JIVO.CUSTOM_TOOLS.FORM.PARAMS.TYPES.NUMBER') }}
              </option>
              <option value="boolean">
                {{ t('JIVO.CUSTOM_TOOLS.FORM.PARAMS.TYPES.BOOLEAN') }}
              </option>
            </select>
            <Input
              v-model="param.description"
              :placeholder="t('JIVO.CUSTOM_TOOLS.FORM.PARAMS.DESCRIPTION')"
            />
            <label
              class="flex items-center gap-1 text-xs text-n-slate-12 whitespace-nowrap pt-2"
            >
              <input v-model="param.required" type="checkbox" />
              {{ t('JIVO.CUSTOM_TOOLS.FORM.PARAMS.REQUIRED') }}
            </label>
            <Button
              icon="i-lucide-trash-2"
              ruby
              xs
              faded
              @click="removeParam(idx)"
            />
          </div>
        </div>
        <Button
          class="mt-2"
          icon="i-lucide-circle-plus"
          :label="t('JIVO.CUSTOM_TOOLS.FORM.PARAMS.ADD')"
          slate
          xs
          faded
          @click="addParam"
        />
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.REQUEST_TEMPLATE.LABEL') }}
        </label>
        <textarea
          v-model="form.request_template"
          rows="3"
          :placeholder="
            t('JIVO.CUSTOM_TOOLS.FORM.REQUEST_TEMPLATE.PLACEHOLDER')
          "
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand font-mono text-xs"
        />
        <p class="text-xs text-n-slate-11 mt-1">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.REQUEST_TEMPLATE.HELP') }}
        </p>
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.RESPONSE_TEMPLATE.LABEL') }}
        </label>
        <textarea
          v-model="form.response_template"
          rows="3"
          :placeholder="
            t('JIVO.CUSTOM_TOOLS.FORM.RESPONSE_TEMPLATE.PLACEHOLDER')
          "
          class="w-full px-3 py-2 border border-n-weak rounded-md bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand font-mono text-xs"
        />
        <p class="text-xs text-n-slate-11 mt-1">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.RESPONSE_TEMPLATE.HELP') }}
        </p>
      </div>

      <Input
        v-model="form.rate_limit_per_minute"
        type="number"
        min="0"
        :label="t('JIVO.CUSTOM_TOOLS.FORM.RATE_LIMIT.LABEL')"
        :placeholder="t('JIVO.CUSTOM_TOOLS.FORM.RATE_LIMIT.PLACEHOLDER')"
        :help-text="t('JIVO.CUSTOM_TOOLS.FORM.RATE_LIMIT.HELP')"
      />

      <div class="flex items-center justify-between gap-4">
        <label class="text-sm text-n-slate-12">
          {{ t('JIVO.CUSTOM_TOOLS.FORM.ENABLED.LABEL') }}
        </label>
        <ToggleSwitch v-model="form.enabled" />
      </div>
    </div>

    <div class="p-6 border-t border-n-weak flex justify-end gap-2">
      <Button
        :label="t('JIVO.CUSTOM_TOOLS.FORM.CANCEL')"
        slate
        faded
        @click="emit('close')"
      />
      <Button
        :label="
          mode === 'create'
            ? t('JIVO.CUSTOM_TOOLS.FORM.CREATE')
            : t('JIVO.CUSTOM_TOOLS.FORM.SAVE')
        "
        :is-loading="isLoading"
        :disabled="!isValid"
        @click="submit"
      />
    </div>
  </div>
</template>
