import { ref } from "vue";
import { wechatLogin } from "@/api/auth";
import { getCurrentUser } from "@/api/user";
import { isMockEnabled } from "@/mock";
import { resolveSessionBootstrapMode } from "@/stores/bootstrapStrategy";
import {
  clearAccessToken,
  clearLocalSessionStorage,
  clearManualLogout,
  getAccessToken,
  hasManualLogout,
  setAccessToken,
  setManualLogout,
} from "@/utils/authStorage";
import { isUnauthorizedError } from "@/utils/request";
import type { AppUser } from "@/types/app";

const currentUser = ref<AppUser | null>(null);
const bootstrapError = ref("");
const isBootstrapping = ref(false);

let bootstrapPromise: Promise<void> | null = null;
let sessionVersion = 0;

function resetSessionState() {
  currentUser.value = null;
  bootstrapError.value = "";
}

function requestWechatCode(): Promise<string> {
  return new Promise((resolve, reject) => {
    uni.login({
      provider: "weixin",
      success: (result) => {
        if (!result.code) {
          reject(new Error("微信登录未返回 code"));
          return;
        }
        resolve(result.code);
      },
      fail: (error) => {
        reject(new Error(error.errMsg || "微信登录失败"));
      },
    });
  });
}

function assertSessionVersion(version: number) {
  if (version !== sessionVersion || hasManualLogout()) {
    clearLocalSessionStorage();
    resetSessionState();
    throw new Error("已退出登录，请重新登录");
  }
}

/**
 * Mock 模式专用 bootstrap：跳过微信登录，直接写入 mock token，
 * 然后通过（已被 mock 拦截的）API 调用建立用户上下文。
 */
async function bootstrapMockSession() {
  clearManualLogout();
  setAccessToken("mock-token");
  currentUser.value = await getCurrentUser();
}

async function loginAndBootstrap(sessionBootstrapVersion: number) {
  const code = await requestWechatCode();
  assertSessionVersion(sessionBootstrapVersion);
  const loginResult = await wechatLogin(code);
  assertSessionVersion(sessionBootstrapVersion);

  setAccessToken(loginResult.token);
  assertSessionVersion(sessionBootstrapVersion);
  currentUser.value = loginResult.user;
}

async function bootstrapFromExistingToken() {
  currentUser.value = await getCurrentUser();
}

export async function ensureSessionReady(force = false) {
  if (bootstrapPromise && !force) {
    return bootstrapPromise;
  }

  bootstrapPromise = (async () => {
    if (force && hasManualLogout()) {
      sessionVersion += 1;
      clearManualLogout();
    }

    const sessionBootstrapVersion = sessionVersion;
    isBootstrapping.value = true;
    bootstrapError.value = "";

    try {
      // Mock 模式：跳过微信登录，直接用 mock 数据建立会话
      if (isMockEnabled()) {
        await bootstrapMockSession();
        return;
      }

      const bootstrapMode = resolveSessionBootstrapMode({
        hasAccessToken: !!getAccessToken(),
        isManuallyLoggedOut: hasManualLogout(),
        force,
      });

      if (bootstrapMode === "blocked_by_logout") {
        resetSessionState();
        throw new Error("已退出登录，请重新登录");
      }

      if (bootstrapMode === "existing_token") {
        try {
          await bootstrapFromExistingToken();
          return;
        } catch (error) {
          if (!isUnauthorizedError(error)) {
            throw error;
          }
          clearAccessToken();
        }
      }

      // #ifdef H5
      // H5 没有微信 OAuth 通道：uni.login 会失败甚至在部分环境不回调，
      // 导致 bootstrapPromise 挂起、所有 await ensureSessionReady() 的页面卡死。
      // 无 token 时保持游客态正常返回，由页面内的登录入口显式登录，
      // 不能抛错把首页数据加载打成错误卡片。
      if (!getAccessToken()) {
        resetSessionState();
        return;
      }
      // #endif

      await loginAndBootstrap(sessionBootstrapVersion);
    } catch (error) {
      resetSessionState();
      bootstrapError.value = error instanceof Error ? error.message : "会话初始化失败";
      throw error;
    } finally {
      isBootstrapping.value = false;
      bootstrapPromise = null;
    }
  })();

  return bootstrapPromise;
}

export function applyCurrentUser(user: AppUser) {
  currentUser.value = user;
}

export function clearSession() {
  sessionVersion += 1;
  clearLocalSessionStorage();
  setManualLogout();
  resetSessionState();
}

export function useAppSession() {
  return {
    currentUser,
    bootstrapError,
    isBootstrapping,
    ensureSessionReady,
    applyCurrentUser,
    clearSession,
  };
}
