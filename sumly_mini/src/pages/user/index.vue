<script setup lang="ts">
import { computed, ref } from "vue";
import { onShow } from "@dcloudio/uni-app";
import { updateMyProfile } from "@/api/user";
import { applyCurrentUser, ensureSessionReady, useAppSession } from "@/stores/appSession";
import NeoInput from "@/components/NeoInput/NeoInput.vue";

const { currentUser, isBootstrapping } = useAppSession();

const nicknameDraft = ref("");
const isSaving = ref(false);
const hasLoadedDraft = ref(false);

const isLoggedIn = computed(() => currentUser.value !== null);

const fieldRows = computed(() => {
  const user = currentUser.value;
  if (!user) {
    return [];
  }
  return [
    { label: "用户 ID", value: String(user.id) },
    { label: "昵称", value: user.nickname || "（未设置）" },
    { label: "真实姓名", value: user.real_name || "（未填写）" },
    { label: "手机号", value: user.phone_number || "（未绑定）" },
    { label: "状态", value: user.status },
  ];
});

async function loadPageData() {
  try {
    await ensureSessionReady();
  } catch (error) {
    uni.showToast({ title: error instanceof Error ? error.message : "会话初始化失败", icon: "none" });
    return;
  }
  if (currentUser.value && !hasLoadedDraft.value) {
    nicknameDraft.value = currentUser.value.nickname;
    hasLoadedDraft.value = true;
  }
}

async function handleSaveNickname() {
  if (isSaving.value) {
    return;
  }
  const nickname = nicknameDraft.value.trim();
  if (!nickname) {
    uni.showToast({ title: "昵称不能为空", icon: "none" });
    return;
  }
  isSaving.value = true;
  try {
    const updated = await updateMyProfile({ nickname });
    applyCurrentUser(updated);
    nicknameDraft.value = updated.nickname;
    uni.showToast({ title: "已保存", icon: "success" });
  } catch (error) {
    uni.showToast({ title: error instanceof Error ? error.message : "保存失败", icon: "none" });
  } finally {
    isSaving.value = false;
  }
}

onShow(() => {
  void loadPageData();
});
</script>

<template>
  <view class="page-container">
    <view v-if="isBootstrapping" class="app-card">
      <view class="app-hint">正在加载...</view>
    </view>

    <view v-else-if="!isLoggedIn" class="app-card">
      <view class="app-card-title">未登录</view>
      <!-- #ifndef H5 -->
      <view class="app-hint">请返回首页点击「微信登录」后再查看资料。</view>
      <!-- #endif -->
      <!-- #ifdef H5 -->
      <view class="app-hint">请返回首页使用开发登录后再查看资料。</view>
      <!-- #endif -->
    </view>

    <template v-else>
      <view class="app-card">
        <view class="app-card-title">我的资料</view>
        <view v-for="row in fieldRows" :key="row.label" class="app-field-row">
          <text class="app-field-label">{{ row.label }}</text>
          <text class="app-field-value">{{ row.value }}</text>
        </view>
      </view>

      <view class="app-card">
        <view class="app-card-title">修改昵称</view>
        <NeoInput v-model="nicknameDraft" placeholder="输入新昵称" :maxlength="120" />
        <button class="app-primary-button profile-save-button" :disabled="isSaving" @click="handleSaveNickname">
          {{ isSaving ? "保存中..." : "保存" }}
        </button>
      </view>
    </template>
  </view>
</template>

<style scoped>
.profile-save-button {
  margin-top: 24rpx;
}

@media (min-width: 768px) {
  .profile-save-button {
    margin-top: 16px;
  }
}
</style>
