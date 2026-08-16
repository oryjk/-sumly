import type { AppUser } from "@/types/app";
import { requestApi } from "@/utils/request";

export function getCurrentUser() {
  return requestApi<AppUser>({
    url: "/users/me",
    auth: true,
  });
}

export function updateMyProfile(payload: { nickname?: string; real_name?: string }) {
  return requestApi<AppUser>({
    url: "/users/me",
    method: "PATCH",
    data: payload,
    auth: true,
  });
}
