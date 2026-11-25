import "server-only";

import { randomBytes } from "node:crypto";
import { cookies } from "next/headers";
import { ADMIN_SESSION_SECONDS } from "./constants";
import { HttpError } from "./http";
import { hmacHex } from "./secrets";
import { getSupabaseAdmin } from "./supabaseAdmin";

export const ADMIN_COOKIE = "mindlet_admin";

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export const adminCookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "strict",
  path: "/",
} as const;

// DB에는 원본 토큰이 아니라 HMAC 검증값만 저장한다.
export async function createAdminSession() {
  const token = randomBytes(32).toString("base64url");
  const now = new Date();
  const expiresAt = new Date(now.getTime() + ADMIN_SESSION_SECONDS * 1000);
  const supabase = getSupabaseAdmin();

  const { error } = await supabase.from("admin_sessions").insert({
    token_hash: hmacHex("admin-session", token),
    expires_at: expiresAt.toISOString(),
  });
  if (error) throw error;

  // 만료된 세션 정리는 실패해도 로그인 자체에는 영향이 없다.
  await supabase.from("admin_sessions").delete().lt("expires_at", now.toISOString());

  return token;
}

async function currentToken() {
  const token = (await cookies()).get(ADMIN_COOKIE)?.value;
  return token && TOKEN_PATTERN.test(token) ? token : null;
}

export async function isAdminRequest() {
  const token = await currentToken();
  if (!token) return false;

  const { data, error } = await getSupabaseAdmin()
    .from("admin_sessions")
    .select("token_hash")
    .eq("token_hash", hmacHex("admin-session", token))
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (error) throw error;

  return Boolean(data);
}

export async function requireAdmin() {
  if (!(await isAdminRequest())) {
    throw new HttpError(401, "관리자 인증이 필요합니다.");
  }
}

export async function destroyAdminSession() {
  const token = await currentToken();
  if (!token) return;

  const { error } = await getSupabaseAdmin()
    .from("admin_sessions")
    .delete()
    .eq("token_hash", hmacHex("admin-session", token));
  if (error) throw error;
}
