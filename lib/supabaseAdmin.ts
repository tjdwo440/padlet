import "server-only";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  isHttpUrl,
  isPublishableKey,
  isSecretKey,
  readEnv,
} from "./config";

const authOptions = { persistSession: false, autoRefreshToken: false } as const;

let adminClient: SupabaseClient | null = null;

// Secret key 클라이언트: 사용자 세션/JWT를 결합하지 않는다.
export function getSupabaseAdmin() {
  if (adminClient) return adminClient;

  const url = readEnv("NEXT_PUBLIC_SUPABASE_URL", isHttpUrl);
  const secretKey = readEnv("SUPABASE_SECRET_KEY", isSecretKey);

  adminClient = createClient(url, secretKey, { auth: authOptions });
  return adminClient;
}

export function getSupabaseServerAnon() {
  const url = readEnv("NEXT_PUBLIC_SUPABASE_URL", isHttpUrl);
  const publishableKey = readEnv(
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    isPublishableKey,
  );

  return createClient(url, publishableKey, { auth: authOptions });
}
