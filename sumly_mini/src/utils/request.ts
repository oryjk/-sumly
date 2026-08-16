import { buildAppApiUrl, getApiBaseUrl } from "@/config/apiBase";
import { getAccessToken } from "@/utils/authStorage";
import { isMockEnabled, tryMockRequest } from "@/mock";
import type { BackendApiResponse } from "@/types/backend";

type RequestMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
type RequestPayload = string | Record<string, unknown> | ArrayBuffer | undefined;

interface RequestOptions<TBody extends RequestPayload> {
  url: string;
  method?: RequestMethod;
  data?: TBody;
  auth?: boolean;
}

export class ApiRequestError extends Error {
  statusCode: number;

  constructor(message: string, statusCode = 0) {
    super(message);
    this.name = "ApiRequestError";
    this.statusCode = statusCode;
  }
}

export function isUnauthorizedError(error: unknown): boolean {
  return error instanceof ApiRequestError && error.statusCode === 401;
}

export async function requestRaw<TResponse, TBody extends RequestPayload = Record<string, unknown>>(
  options: RequestOptions<TBody>,
): Promise<TResponse> {
  const token = options.auth ? getAccessToken() : "";
  const method = options.method ?? "GET";
  const requestUrl = /^https?:\/\//i.test(options.url) ? options.url : buildAppApiUrl(getApiBaseUrl(), options.url);

  // Mock 拦截：开发环境下通过 VITE_USE_MOCK 开启。
  // 开启后必须“全有或全无”：未覆盖的接口直接报错，不允许回落到真实后端，
  // 否则页面会混显 mock 数据和真实数据，误导联调判断。
  if (isMockEnabled()) {
    const mockResult = tryMockRequest(method, requestUrl, options.data);
    if (mockResult === null) {
      return Promise.reject(new ApiRequestError(`mock 模式未覆盖该接口: ${method} ${options.url}`, 0));
    }
    return mockResult as Promise<TResponse>;
  }

  return new Promise<TResponse>((resolve, reject) => {
    uni.request({
      url: requestUrl,
      method: method as never,
      data: options.data,
      header: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      success: (response) => {
        const { statusCode, data } = response;
        if (statusCode >= 200 && statusCode < 300) {
          resolve(data as TResponse);
          return;
        }

        const message =
          typeof data === "object" && data && "message" in data
            ? String((data as { message?: string }).message || "请求失败")
            : `请求失败(${statusCode})`;

        reject(new ApiRequestError(message, statusCode));
      },
      fail: (error) => {
        reject(new ApiRequestError(error.errMsg || "网络请求失败"));
      },
    });
  });
}

export async function requestApi<TResponse, TBody extends RequestPayload = Record<string, unknown>>(
  options: RequestOptions<TBody>,
): Promise<TResponse> {
  const response = await requestRaw<BackendApiResponse<TResponse>, TBody>(options);
  if (response.code !== 0) {
    throw new ApiRequestError(response.message || "请求失败", response.code || 0);
  }

  return (response.data ?? null) as TResponse;
}

export const request = requestRaw;
