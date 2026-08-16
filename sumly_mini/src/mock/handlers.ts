import { getMockUser, setMockNickname } from "@/mock/appData";
import type { BackendApiResponse } from "@/types/backend";

type RequestMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

function appPath(url: string): string {
  const path = new URL(url).pathname;
  const marker = "/api/v1/app";
  const index = path.indexOf(marker);
  if (index === -1) {
    return path;
  }
  return path.slice(index + marker.length);
}

function success<T>(data: T): BackendApiResponse<T> {
  return { code: 0, message: "ok", data };
}

export function tryMockHandler(method: RequestMethod, url: string, data: unknown): unknown | null {
  const path = appPath(url);
  if (path === "/auth/wechat/login" && method === "POST") {
    return success({ token: "mock-token", user: getMockUser() });
  }
  if (path === "/users/me" && method === "GET") {
    return success(getMockUser());
  }
  if (path === "/users/me" && method === "PATCH") {
    const body = (data ?? {}) as { nickname?: unknown; real_name?: unknown };
    if (typeof body.nickname === "string" && body.nickname.trim()) {
      setMockNickname(body.nickname.trim());
    }
    return success(getMockUser());
  }
  return null;
}
