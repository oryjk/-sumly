export type AppUserStatus = "active" | "frozen";

export interface AppUser {
  id: number;
  nickname: string;
  avatar_url: string | null;
  real_name: string | null;
  phone_number: string | null;
  status: AppUserStatus;
}

export interface LoginResponse {
  token: string;
  user: AppUser;
}
