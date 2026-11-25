export const PASTEL_COLORS = [
  "#fef3c7",
  "#dbeafe",
  "#dcfce7",
  "#fce7f3",
  "#f3e8ff",
  "#fed7aa",
  "#e0f2fe",
  "#fae8ff",
] as const;

export const TITLE_MAX_LENGTH = 80;
export const CONTENT_MAX_LENGTH = 2000;

export const RATE_LIMITS = {
  memoCreate: { scope: "memo_create", limit: 20, windowSeconds: 10 * 60 },
  memoDelete: { scope: "memo_delete", limit: 30, windowSeconds: 10 * 60 },
  memoDeleteFail: { scope: "memo_delete_fail", limit: 5, windowSeconds: 10 * 60 },
  adminLoginFail: { scope: "admin_login_fail", limit: 5, windowSeconds: 15 * 60 },
} as const;

export type RateLimitRule = (typeof RATE_LIMITS)[keyof typeof RATE_LIMITS];

export const ADMIN_SESSION_SECONDS = 8 * 60 * 60;
