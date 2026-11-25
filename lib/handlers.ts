import "server-only";

import {
  ADMIN_COOKIE,
  adminCookieOptions,
  createAdminSession,
  destroyAdminSession,
  isAdminRequest,
  requireAdmin,
} from "./adminSession";
import { ADMIN_SESSION_SECONDS, RATE_LIMITS } from "./constants";
import {
  HttpError,
  assertSameOrigin,
  getClientIp,
  handleError,
  json,
  readJsonObject,
} from "./http";
import { hashPassword, verifyPassword } from "./password";
import { clientKey, consumeRateLimit, resetRateLimit } from "./rateLimit";
import { getAdminPasswordHash } from "./secrets";
import { getSupabaseAdmin, getSupabaseServerAnon } from "./supabaseAdmin";
import { isFourDigitPassword, isUuid, parseMemoInput } from "./validation";

const INVALID_ID = "올바른 메모 ID가 아닙니다.";

export async function listMemos() {
  try {
    const { data, error } = await getSupabaseServerAnon()
      .from("memos")
      .select("id,title,content,color,position,created_at,updated_at")
      .order("created_at", { ascending: false });
    if (error) throw error;
    return json({ memos: data ?? [] });
  } catch (error) {
    return handleError("GET /api/memos", error, "메모 목록을 불러오지 못했습니다.");
  }
}

export async function createMemo(request: Request) {
  try {
    assertSameOrigin(request);
    await consumeRateLimit(RATE_LIMITS.memoCreate, clientKey(getClientIp(request)));

    const input = parseMemoInput(await readJsonObject(request));
    if (!input.ok) throw new HttpError(400, input.error);
    const { title, content, color, password } = input.value;

    // 메모와 암호 해시는 하나의 RPC(단일 트랜잭션)로 저장한다.
    const { data, error } = await getSupabaseAdmin().rpc("create_memo_with_credentials", {
      p_title: title,
      p_content: content,
      p_color: color,
      p_password_hash: await hashPassword(password),
    });
    if (error) throw error;

    return json({ memo: data }, { status: 201 });
  } catch (error) {
    return handleError("POST /api/memos", error, "메모를 저장하지 못했습니다.");
  }
}

export async function deleteMemoWithPassword(request: Request, pathId?: string) {
  try {
    assertSameOrigin(request);
    const ip = clientKey(getClientIp(request));
    await consumeRateLimit(RATE_LIMITS.memoDelete, ip);

    const body = await readJsonObject(request);
    const id = pathId ?? body.id;
    if (!isUuid(id)) throw new HttpError(400, INVALID_ID);
    if (!isFourDigitPassword(body.password)) {
      throw new HttpError(400, "숫자 4자리 비밀번호를 입력해 주세요.");
    }

    // 실패 횟수 제한은 bcrypt 비교 전에, 시도를 먼저 기록하는 방식으로 적용한다.
    const failKey = `${id}:${ip}`;
    await consumeRateLimit(RATE_LIMITS.memoDeleteFail, failKey);

    const supabase = getSupabaseAdmin();
    const { data: credential, error: readError } = await supabase
      .from("memo_credentials")
      .select("password_hash")
      .eq("memo_id", id)
      .maybeSingle();
    if (readError) throw readError;
    if (!credential) throw new HttpError(404, "메모를 찾을 수 없습니다.");

    if (!(await verifyPassword(body.password, credential.password_hash))) {
      throw new HttpError(403, "삭제 비밀번호가 일치하지 않습니다.");
    }

    const { error: deleteError } = await supabase.from("memos").delete().eq("id", id);
    if (deleteError) throw deleteError;

    await resetRateLimit(RATE_LIMITS.memoDeleteFail, failKey).catch(() => undefined);
    return json({ ok: true });
  } catch (error) {
    return handleError("POST /api/memos/delete", error, "메모를 삭제하지 못했습니다.");
  }
}

export async function adminLogin(request: Request) {
  try {
    assertSameOrigin(request);
    const ip = clientKey(getClientIp(request));
    await consumeRateLimit(RATE_LIMITS.adminLoginFail, ip);

    const body = await readJsonObject(request);
    const password = body.password;
    if (typeof password !== "string" || password.length < 1 || password.length > 200) {
      throw new HttpError(400, "관리자 비밀번호를 입력해 주세요.");
    }

    if (!(await verifyPassword(password, getAdminPasswordHash()))) {
      throw new HttpError(401, "관리자 비밀번호가 일치하지 않습니다.");
    }

    const token = await createAdminSession();
    await resetRateLimit(RATE_LIMITS.adminLoginFail, ip).catch(() => undefined);

    const response = json({ ok: true });
    response.cookies.set(ADMIN_COOKIE, token, {
      ...adminCookieOptions,
      maxAge: ADMIN_SESSION_SECONDS,
    });
    return response;
  } catch (error) {
    return handleError("POST /api/admin/login", error, "관리자 로그인에 실패했습니다.");
  }
}

export async function adminLogout(request: Request) {
  try {
    assertSameOrigin(request);
    await destroyAdminSession();

    const response = json({ ok: true });
    response.cookies.set(ADMIN_COOKIE, "", { ...adminCookieOptions, maxAge: 0 });
    return response;
  } catch (error) {
    return handleError("POST /api/admin/logout", error, "로그아웃하지 못했습니다.");
  }
}

export async function adminSessionStatus() {
  try {
    return json({ isAdmin: await isAdminRequest() });
  } catch (error) {
    console.error("GET /api/admin/session", (error as { message?: unknown })?.message);
    return json({ isAdmin: false });
  }
}

export async function adminDeleteMemo(request: Request, pathId?: string) {
  try {
    assertSameOrigin(request);
    await requireAdmin();

    const id = pathId ?? (await readJsonObject(request)).id;
    if (!isUuid(id)) throw new HttpError(400, INVALID_ID);

    const { error } = await getSupabaseAdmin().from("memos").delete().eq("id", id);
    if (error) throw error;
    return json({ ok: true });
  } catch (error) {
    return handleError("POST /api/admin/delete", error, "메모를 강제 삭제하지 못했습니다.");
  }
}

export async function adminDeleteAll(request: Request) {
  try {
    assertSameOrigin(request);
    await requireAdmin();

    const { error } = await getSupabaseAdmin().from("memos").delete().not("id", "is", null);
    if (error) throw error;
    return json({ ok: true });
  } catch (error) {
    return handleError("POST /api/admin/delete-all", error, "전체 메모를 삭제하지 못했습니다.");
  }
}

