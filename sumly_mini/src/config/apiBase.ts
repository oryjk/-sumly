export const FALLBACK_APP_API_BASE = "http://127.0.0.1:18090/api/v1/app";

export function normalizeAppApiBase(value: string): string {
  const normalized = value.trim().replace(/\/+$/, "");
  if (!/^https?:\/\/[^/?#]+(?:\/[^/?#]+)*\/api\/v1\/app$/i.test(normalized)) {
    throw new Error("VITE_API_BASE_URL 必须指向 App API 根路径 /api/v1/app");
  }
  return normalized;
}

export function buildAppApiUrl(base: string, path: string): string {
  if (!path.startsWith("/") || path.startsWith("/api/") || /^https?:\/\//i.test(path)) {
    throw new Error("请求路径必须是相对于 App API 根路径的领域路径");
  }
  return `${normalizeAppApiBase(base)}${path}`;
}

export function getApiBaseUrl(): string {
  const baseUrl = import.meta.env.VITE_API_BASE_URL?.trim() || FALLBACK_APP_API_BASE;
  return normalizeAppApiBase(baseUrl);
}
