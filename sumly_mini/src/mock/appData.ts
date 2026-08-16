import type { AppUser } from "@/types/app";

let mockNickname = "Mock 用户";

export function getMockUser(): AppUser {
  return {
    id: 1,
    nickname: mockNickname,
    avatar_url: null,
    real_name: "测试用户",
    phone_number: null,
    status: "active",
  };
}

export function setMockNickname(nickname: string): void {
  mockNickname = nickname;
}
