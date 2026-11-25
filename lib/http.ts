import "server-only";

import { isIP } from "node:net";
import { NextResponse } from "next/server";
import { ConfigError } from "./config";

export class HttpError extends Error {
  readonly status: number;
  readonly headers?: Record<string, string>;

  constructor(status: number, message: string, headers?: Record<string, string>) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.headers = headers;
  }
}

const MAX_BODY_CHARS = 20_000;

export function json(
  body: unknown,
  init: { status?: number; headers?: Record<string, string> } = {},
) {
  return NextResponse.json(body, {
    status: init.status ?? 200,
    headers: { "Cache-Control": "no-store", ...init.headers },
  });
}

export function handleError(label: string, error: unknown, fallbackMessage: string) {
  if (error instanceof HttpError) {
    return json({ error: error.message }, { status: error.status, headers: error.headers });
  }

  if (error instanceof ConfigError) {
    console.error(label, `환경 변수 오류: ${error.variable}`);
    return json({ error: error.message }, { status: 500 });
  }

  // 오류 객체 전체 대신 코드와 메시지만 남겨 비밀값이 로그에 섞이지 않게 한다.
  const summary =
    error && typeof error === "object"
      ? {
          code: (error as { code?: unknown }).code,
          message: (error as { message?: unknown }).message,
        }
      : String(error);
  console.error(label, summary);
  return json({ error: fallbackMessage }, { status: 500 });
}

const HOST_PATTERN = /^[A-Za-z0-9.\-[\]:]+$/;

function expectedOrigin(request: Request) {
  const onVercel = Boolean(process.env.VERCEL);
  const headers = request.headers;

  // Vercel은 host/x-forwarded-* 헤더를 플랫폼이 직접 설정한다. 그 외(로컬)에서는
  // 전달 헤더를 신뢰하지 않고 요청 URL의 프로토콜과 Host 헤더만 사용한다.
  const host = (
    headers.get("host") ?? (onVercel ? headers.get("x-forwarded-host") : null)
  )?.trim();
  if (!host || !HOST_PATTERN.test(host)) return null;

  const protocol = onVercel
    ? "https:"
    : new URL(request.url).protocol;

  try {
    return new URL(`${protocol}//${host}`).origin;
  } catch {
    return null;
  }
}

// 상태를 변경하는 모든 API에서 호출한다. Origin이 없거나 요청 주소와 다르면 거부한다.
export function assertSameOrigin(request: Request) {
  const forbidden = new HttpError(403, "허용되지 않은 요청입니다.");
  const origin = request.headers.get("origin");
  if (!origin || origin === "null") throw forbidden;

  let requestOrigin: string;
  try {
    requestOrigin = new URL(origin).origin;
  } catch {
    throw forbidden;
  }

  if (requestOrigin !== expectedOrigin(request)) throw forbidden;
}

export async function readJsonObject(request: Request) {
  let text: string;
  try {
    text = await request.text();
  } catch {
    throw new HttpError(400, "잘못된 요청입니다.");
  }
  if (text.length > MAX_BODY_CHARS) throw new HttpError(400, "요청 본문이 너무 큽니다.");

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpError(400, "잘못된 JSON 형식입니다.");
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new HttpError(400, "잘못된 요청입니다.");
  }
  return parsed as Record<string, unknown>;
}

// Vercel은 X-Forwarded-For를 외부 값 전달 없이 직접 덮어쓴다(스푸핑 방지).
// Vercel이 아닌 환경에서는 클라이언트가 조작할 수 있으므로 헤더를 무시한다.
export function getClientIp(request: Request) {
  if (!process.env.VERCEL) return "local";

  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const candidate = forwarded || request.headers.get("x-real-ip")?.trim();
  return candidate && isIP(candidate) ? candidate : "unknown";
}
