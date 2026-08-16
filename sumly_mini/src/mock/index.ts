import { tryMockHandler } from "@/mock/handlers";
import type { BackendApiResponse } from "@/types/backend";

export function isMockEnabled(): boolean {
  return import.meta.env.VITE_USE_MOCK === "true";
}

// Mock 拦截保持“全有或全无”：未覆盖的接口返回 null，由 request 层直接报错。
export function tryMockRequest<T>(
  method: string,
  url: string,
  data: unknown,
): Promise<BackendApiResponse<T>> | null {
  const result = tryMockHandler(method as never, url, data);
  if (result === null) {
    return null;
  }
  return Promise.resolve(result as BackendApiResponse<T>);
}
