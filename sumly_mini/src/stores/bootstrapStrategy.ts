export function resolveBootstrapStrategy(hasAccessToken: boolean): "existing_token" | "wechat_login" {
  return hasAccessToken ? "existing_token" : "wechat_login";
}

export function resolveSessionBootstrapMode(options: {
  hasAccessToken: boolean;
  isManuallyLoggedOut: boolean;
  force?: boolean;
}): "blocked_by_logout" | "existing_token" | "wechat_login" {
  if (options.isManuallyLoggedOut && !options.force) {
    return "blocked_by_logout";
  }

  return resolveBootstrapStrategy(options.hasAccessToken);
}
