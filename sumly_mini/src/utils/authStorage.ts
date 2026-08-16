const TOKEN_KEY = "sumly_mini_token";
const MANUAL_LOGOUT_KEY = "sumly_mini_manual_logout";

export function getAccessToken(): string {
  return uni.getStorageSync(TOKEN_KEY) || "";
}

export function setAccessToken(token: string): void {
  uni.setStorageSync(TOKEN_KEY, token);
  uni.removeStorageSync(MANUAL_LOGOUT_KEY);
}

export function clearAccessToken(): void {
  uni.removeStorageSync(TOKEN_KEY);
}

export function hasManualLogout(): boolean {
  return uni.getStorageSync(MANUAL_LOGOUT_KEY) === "1";
}

export function setManualLogout(): void {
  uni.setStorageSync(MANUAL_LOGOUT_KEY, "1");
}

export function clearManualLogout(): void {
  uni.removeStorageSync(MANUAL_LOGOUT_KEY);
}

export function clearLocalSessionStorage(): void {
  clearAccessToken();
}
