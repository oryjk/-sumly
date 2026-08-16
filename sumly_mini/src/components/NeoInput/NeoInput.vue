<script setup lang="ts">
/**
 * NeoInput —— 全局统一的文本输入框，neo-brutalism 风格。
 * 视觉值只引用 uni.css 的 --neo-* 令牌，禁止硬编码。
 * 用法：<NeoInput v-model="value" placeholder="..." :maxlength="120" />
 */
withDefaults(
  defineProps<{
    modelValue: string;
    placeholder?: string;
    maxlength?: number;
  }>(),
  { placeholder: "", maxlength: 140 },
);

const emit = defineEmits<{
  (e: "update:modelValue", value: string): void;
}>();

function handleInput(event: unknown) {
  const detail = (event as { detail?: { value?: string } }).detail;
  emit("update:modelValue", detail?.value ?? "");
}
</script>

<template>
  <input
    class="neo-input"
    :value="modelValue"
    :placeholder="placeholder"
    :maxlength="maxlength"
    @input="handleInput"
  />
</template>

<style scoped>
.neo-input {
  background: var(--neo-card);
  border: var(--neo-border);
  border-radius: var(--neo-radius);
  /* uni-input 默认 height 固定 1.4em 且 overflow:hidden，
     必须显式给定高度，否则边框会把内部 input 压到不可点 */
  height: var(--neo-input-h);
  padding: 0 24rpx;
  font-size: 28rpx;
  color: var(--neo-ink);
}

@media (min-width: 768px) {
  .neo-input {
    padding: 0 14px;
    font-size: 15px;
  }
}
</style>
