import "server-only";

import type { RateLimitRule } from "./constants";
import { HttpError } from "./http";
import { hmacHex } from "./secrets";
import { getSupabaseAdmin } from "./supabaseAdmin";

export function clientKey(ip: string) {
  return hmacHex("client-ip", ip);
}

// 시도를 먼저 기록(원자적 증가)한 뒤 허용 여부를 판단한다. 저장소 오류는 그대로 던져
// 보호 대상 작업이 실행되지 않도록 한다(fail closed).
export async function consumeRateLimit(rule: RateLimitRule, key: string) {
  const { data, error } = await getSupabaseAdmin().rpc("rate_limit_hit", {
    p_scope: rule.scope,
    p_key: key,
    p_limit: rule.limit,
    p_window_seconds: rule.windowSeconds,
  });
  if (error) throw error;

  const row = Array.isArray(data) ? data[0] : null;
  if (!row || typeof row.allowed !== "boolean") {
    throw new Error("rate_limit_hit returned an unexpected result");
  }

  if (!row.allowed) {
    const retryAfter = Math.max(1, Number(row.retry_after_seconds) || rule.windowSeconds);
    throw new HttpError(429, "요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.", {
      "Retry-After": String(retryAfter),
    });
  }
}

export async function resetRateLimit(rule: RateLimitRule, key: string) {
  const { error } = await getSupabaseAdmin().rpc("rate_limit_reset", {
    p_scope: rule.scope,
    p_key: key,
  });
  if (error) throw error;
}
