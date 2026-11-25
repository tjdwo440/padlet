import { PASTEL_COLORS, CONTENT_MAX_LENGTH, TITLE_MAX_LENGTH } from "./constants";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

export function isFourDigitPassword(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}$/.test(value);
}

export function isPastelColor(value: unknown): value is (typeof PASTEL_COLORS)[number] {
  return (PASTEL_COLORS as readonly unknown[]).includes(value);
}

// Postgres char_length와 같은 기준(코드 포인트)으로 길이를 센다.
function textLength(value: string) {
  return Array.from(value).length;
}

function cleanText(value: unknown, max: number) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const length = textLength(trimmed);
  if (length < 1 || length > max || trimmed.includes("\u0000")) return null;
  return trimmed;
}

export type MemoInput = {
  title: string;
  content: string;
  password: string;
  color: string;
};

export type MemoInputResult =
  | { ok: true; value: MemoInput }
  | { ok: false; error: string };

export function parseMemoInput(body: Record<string, unknown>): MemoInputResult {
  const title = cleanText(body.title, TITLE_MAX_LENGTH);
  const content = cleanText(body.content, CONTENT_MAX_LENGTH);

  if (!title) return { ok: false, error: `제목은 1~${TITLE_MAX_LENGTH}자로 입력해 주세요.` };
  if (!content) {
    return { ok: false, error: `내용은 1~${CONTENT_MAX_LENGTH}자로 입력해 주세요.` };
  }
  if (!isFourDigitPassword(body.password)) {
    return { ok: false, error: "삭제 비밀번호는 숫자 4자리여야 합니다." };
  }

  let color: string;
  if (body.color === undefined || body.color === null) {
    color = PASTEL_COLORS[Math.floor(Math.random() * PASTEL_COLORS.length)];
  } else if (isPastelColor(body.color)) {
    color = body.color;
  } else {
    return { ok: false, error: "허용되지 않은 메모 색상입니다." };
  }

  return { ok: true, value: { title, content, password: body.password, color } };
}
