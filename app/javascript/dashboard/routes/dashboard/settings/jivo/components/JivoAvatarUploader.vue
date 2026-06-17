<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistant: { type: Object, required: true },
});

const store = useStore();
const { t } = useI18n();

const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
const ACCEPTED_TYPES = ['image/png', 'image/jpeg', 'image/jpg', 'image/webp'];

const fileInputRef = ref(null);
const isUploading = ref(false);
const localPreview = ref(null);

const avatarUrl = computed(
  () => localPreview.value || props.assistant.avatar_url || null
);

const triggerPicker = () => fileInputRef.value?.click();

const handleFile = async event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (!file) return;

  if (!ACCEPTED_TYPES.includes(file.type)) {
    useAlert(t('JIVO.ASSISTANTS.FORM.AVATAR.INVALID_TYPE'));
    return;
  }
  if (file.size > AVATAR_MAX_BYTES) {
    useAlert(t('JIVO.ASSISTANTS.FORM.AVATAR.TOO_LARGE'));
    return;
  }

  localPreview.value = URL.createObjectURL(file);
  isUploading.value = true;
  try {
    await store.dispatch('jivoAssistants/uploadAvatar', {
      id: props.assistant.id,
      file,
    });
    useAlert(t('JIVO.ASSISTANTS.FORM.AVATAR.UPLOADED'));
  } catch (error) {
    localPreview.value = null;
    useAlert(error.message || t('JIVO.ASSISTANTS.FORM.AVATAR.FAILED'));
  } finally {
    isUploading.value = false;
  }
};

const remove = async () => {
  if (!props.assistant.avatar_url) return;
  try {
    await store.dispatch('jivoAssistants/removeAvatar', props.assistant.id);
    localPreview.value = null;
    useAlert(t('JIVO.ASSISTANTS.FORM.AVATAR.REMOVED'));
  } catch (error) {
    useAlert(error.message || t('JIVO.ASSISTANTS.FORM.AVATAR.FAILED'));
  }
};
</script>

<template>
  <div class="flex items-center gap-4">
    <div
      class="relative w-20 h-20 rounded-full bg-n-alpha-black2 border border-n-weak overflow-hidden flex items-center justify-center shrink-0"
    >
      <img
        v-if="avatarUrl"
        :src="avatarUrl"
        :alt="assistant.name || 'avatar'"
        class="w-full h-full object-cover"
      />
      <span v-else class="i-lucide-sparkles text-2xl text-n-slate-11" />
    </div>

    <div class="flex flex-col gap-2">
      <div class="flex gap-2">
        <Button
          :label="
            avatarUrl
              ? t('JIVO.ASSISTANTS.FORM.AVATAR.REPLACE')
              : t('JIVO.ASSISTANTS.FORM.AVATAR.UPLOAD')
          "
          icon="i-lucide-upload"
          xs
          :is-loading="isUploading"
          :disabled="!assistant.id"
          @click="triggerPicker"
        />
        <Button
          v-if="avatarUrl && assistant.avatar_url"
          :label="t('JIVO.ASSISTANTS.FORM.AVATAR.REMOVE')"
          icon="i-lucide-trash-2"
          ruby
          xs
          faded
          @click="remove"
        />
      </div>
      <p class="text-xs text-n-slate-11">
        {{ t('JIVO.ASSISTANTS.FORM.AVATAR.HELP') }}
      </p>
      <p v-if="!assistant.id" class="text-xs text-n-amber-text">
        {{ t('JIVO.ASSISTANTS.FORM.AVATAR.SAVE_FIRST') }}
      </p>
      <input
        ref="fileInputRef"
        type="file"
        accept="image/png,image/jpeg,image/webp"
        class="hidden"
        @change="handleFile"
      />
    </div>
  </div>
</template>
