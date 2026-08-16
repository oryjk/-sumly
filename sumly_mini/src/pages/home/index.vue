<script setup lang="ts">
import { computed, ref } from "vue";
import { ensureSessionReady, clearSession, loginWithDevIdentifier, useAppSession } from "@/stores/appSession";
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

const devIdentifier = ref("");
const isDevLoggingIn = ref(false);

async function handleDevLogin() {
  const identifier = devIdentifier.value.trim();
  if (!identifier) {
    uni.showToast({ title: "请输入测试标识", icon: "none" });
    return;
  }
  if (isDevLoggingIn.value) {
    return;
  }
  isDevLoggingIn.value = true;
  try {
    await loginWithDevIdentifier(identifier);
    uni.$emit("session:login-completed");
  } catch (error) {
    uni.showToast({ title: error instanceof Error ? error.message : "登录失败", icon: "none" });
  } finally {
    isDevLoggingIn.value = false;
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
      <view class="home-title">记金</view>
      <view class="home-subtitle">记录你的黄金资产</view>
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

        <!-- #ifndef H5 -->
        <button v-if="!isLoggedIn" class="app-primary-button home-action" @click="handleLogin">
          微信登录
        </button>
        <!-- #endif -->
        <!-- #ifdef H5 -->
        <template v-if="!isLoggedIn">
          <button v-if="isMockEnabled()" class="app-primary-button home-action" @click="handleLogin">
            登录（mock）
          </button>
          <view v-else class="home-dev-login">
            <input
              v-model="devIdentifier"
              class="app-input"
              placeholder="测试标识，如 test-user-01"
              maxlength="120"
            />
            <button class="app-primary-button home-action" :disabled="isDevLoggingIn" @click="handleDevLogin">
              {{ isDevLoggingIn ? "登录中..." : "开发登录" }}
            </button>
          </view>
        </template>
        <!-- #endif -->
        <template v-else>
          <button class="app-primary-button home-action" @click="openProfile">查看我的资料</button>
          <button class="app-plain-button home-action" @click="handleLogout">退出登录</button>
        </template>
      </template>

      <!-- #ifndef H5 -->
      <view class="app-hint">
        {{ isMockEnabled() ? "当前为 mock 模式（VITE_USE_MOCK=true），登录不请求真实后端。" : "登录走 sumly_go 后端 POST /api/v1/app/auth/wechat/login。" }}
      </view>
      <!-- #endif -->
      <!-- #ifdef H5 -->
      <view class="app-hint">
        {{ isMockEnabled() ? "当前为 mock 模式（VITE_USE_MOCK=true），登录不请求真实后端。" : "H5 开发登录走 POST /api/v1/app/auth/dev/login（后端需 DEV_LOGIN_ENABLED=true）。" }}
      </view>
      <!-- #endif -->
    </view>
  </view>
</template>

<style scoped>
.home-title {
  font-size: 52rpx;
  font-weight: 900;
  color: #111111;
  letter-spacing: 2rpx;
}

.home-subtitle {
  margin-top: 8rpx;
  font-size: 26rpx;
  color: #6b6560;
}

.home-action {
  margin-top: 24rpx;
}

.home-error {
  color: #ff6b6b;
  font-weight: 600;
}

.home-dev-login {
  margin-top: 24rpx;
}

@media (min-width: 768px) {
  .home-title {
    font-size: 28px;
  }

  .home-subtitle {
    font-size: 14px;
  }

  .home-action,
  .home-dev-login {
    margin-top: 16px;
  }
}
</style>
