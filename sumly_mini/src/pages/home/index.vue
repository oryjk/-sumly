<script setup lang="ts">
import { computed } from "vue";
import { ensureSessionReady, clearSession, useAppSession } from "@/stores/appSession";
import { isMockEnabled } from "@/mock";

const PROFILE_PAGE_PATH = "/pages/user/index";

const { currentUser, bootstrapError, isBootstrapping } = useAppSession();

const displayName = computed(() => {
  const user = currentUser.value;
  if (!user) {
    return "未登录";
  }
  return user.nickname || `用户 ${user.id}`;
});

const isLoggedIn = computed(() => currentUser.value !== null);

async function handleLogin() {
  try {
    await ensureSessionReady(true);
    uni.$emit("session:login-completed");
  } catch (error) {
    uni.showToast({ title: error instanceof Error ? error.message : "登录失败", icon: "none" });
  }
}

function handleLogout() {
  clearSession();
  uni.showToast({ title: "已退出登录", icon: "none" });
}

function openProfile() {
  if (!isLoggedIn.value) {
    uni.showToast({ title: "请先登录", icon: "none" });
    return;
  }
  uni.navigateTo({ url: PROFILE_PAGE_PATH });
}
</script>

<template>
  <view class="page-container">
    <view class="app-card">
      <view class="home-title">sumly</view>
      <view class="home-subtitle">微信小程序 + Go 后端骨架</view>
    </view>

    <view class="app-card">
      <view class="app-card-title">登录状态</view>

      <view v-if="isBootstrapping" class="app-hint">正在初始化会话...</view>

      <template v-else>
        <view class="app-field-row">
          <text class="app-field-label">当前用户</text>
          <text class="app-field-value">{{ displayName }}</text>
        </view>
        <view v-if="isLoggedIn" class="app-field-row">
          <text class="app-field-label">用户 ID</text>
          <text class="app-field-value">{{ currentUser?.id }}</text>
        </view>
        <view v-if="isLoggedIn" class="app-field-row">
          <text class="app-field-label">状态</text>
          <text class="app-field-value">{{ currentUser?.status }}</text>
        </view>

        <view v-if="bootstrapError" class="app-hint home-error">{{ bootstrapError }}</view>

        <button v-if="!isLoggedIn" class="app-primary-button home-action" @click="handleLogin">
          微信登录
        </button>
        <template v-else>
          <button class="app-primary-button home-action" @click="openProfile">查看我的资料</button>
          <button class="app-plain-button home-action" @click="handleLogout">退出登录</button>
        </template>
      </template>

      <view class="app-hint">
        {{ isMockEnabled() ? "当前为 mock 模式（VITE_USE_MOCK=true），登录不请求真实后端。" : "登录走 sumly_go 后端 POST /api/v1/app/auth/wechat/login。" }}
      </view>
    </view>
  </view>
</template>

<style scoped>
.home-title {
  font-size: 44rpx;
  font-weight: 700;
  color: #111827;
}

.home-subtitle {
  margin-top: 8rpx;
  font-size: 26rpx;
  color: #6b7280;
}

.home-action {
  margin-top: 24rpx;
}

.home-error {
  color: #dc2626;
}
</style>
