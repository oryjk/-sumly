import type { LoginResponse } from "@/types/app";
import { requestApi } from "@/utils/request";

export function wechatLogin(jsCode: string) {
  return requestApi<LoginResponse>({
    url: "/auth/wechat/login",
    method: "POST",
    data: { js_code: jsCode },
  });
}
