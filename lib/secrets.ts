import "server-only";

import { createHmac } from "node:crypto";
import { readEnv } from "./config";

const MIN_SECRET_LENGTH = 32;

export function getSessionSecret() {
  return readEnv(
    "ADMIN_SESSION_SECRET",
    (value) => value.length >= MIN_SECRET_LENGTH,
  );
}

// 용도(purpose)를 접두어로 분리해 세션/IP 검증값이 서로 재사용되지 않게 한다.
export function hmacHex(purpose: "admin-session" | "client-ip", value: string) {
  return createHmac("sha256", getSessionSecret())
    .update(`${purpose}:${value}`)
    .digest("hex");
}

export function getAdminPasswordHash() {
  return readEnv("ADMIN_PASSWORD_HASH", (value) =>
    /^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$/.test(value),
  );
}
