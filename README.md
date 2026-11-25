# MINDLET

Next.js(App Router) · TypeScript · Tailwind CSS · Supabase · Vercel 기반의 단일 메모 보드입니다.
주소를 아는 사람은 누구나 메모를 조회·작성할 수 있고, 작성자는 자신이 정한 4자리 숫자 암호로, 관리자는 별도 로그인 후 메모를 삭제할 수 있습니다.

## 1. 요구 환경

- Node.js 22 이상 (개발·검증에 사용한 버전: Node v26.13.1, npm 11.20.0)
- npm (반드시 `npm ci` 사용 — `package-lock.json` 기준 설치)
- Supabase 프로젝트 (Publishable key / Secret key 방식)

## 2. 로컬 실행

```bash
# 1) 압축 해제한 프로젝트 폴더에서 터미널 열기
# 2) 버전 확인
node -v
npm -v
# 3) 의존성 설치
npm ci
# 4) 환경 변수 파일 만들기
cp .env.example .env.local        # Windows PowerShell: Copy-Item .env.example .env.local
```

### 2-1. `.env.local` 값 채우기

| 변수 | 설명 |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase 프로젝트 URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_...` (브라우저 조회용) |
| `SUPABASE_SECRET_KEY` | `sb_secret_...` (서버 전용, 절대 공개 금지) |
| `ADMIN_PASSWORD_HASH` | 관리자 암호의 bcrypt 해시 |
| `ADMIN_SESSION_SECRET` | 관리자 세션 HMAC 비밀값 (관리자 암호 해시와 별개) |

레거시 변수(`NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`)는 사용하지 않습니다.
변수가 없거나 형식이 틀리면 서버가 값은 출력하지 않고 **변수 이름과 해결 방법만** 안내합니다.

### 2-2. 관리자 암호 해시 생성

```bash
npm run hash-admin
```

암호를 숨김 입력으로 받아 bcrypt(cost 12) 해시를 출력합니다(8자 이상). 출력되는 두 줄 중:

- **`.env.local`에는 `\$`로 이스케이프된 줄**을 붙여 넣습니다. Next.js의 dotenv-expand가 `$2b$12$...`의 `$`를 변수 치환으로 해석해 해시가 깨지기 때문입니다(실제로 확인함).
- **Vercel 대시보드에는 이스케이프 없는 원본 해시**를 넣습니다.

### 2-3. 세션 비밀값 생성

```bash
npm run gen-session-secret
```

출력된 `ADMIN_SESSION_SECRET=...` 값을 `.env.local`에 넣습니다. (직접 만들 때는 32자 이상의 무작위 문자열)

### 2-4. DB 준비 (둘 중 하나)

Supabase 대시보드 → SQL Editor에서 실행합니다. 이 저장소는 DB를 자동으로 변경하지 않습니다.

**A. 신규 빈 DB → `schema.sql`**

- `memos`, `memo_credentials`, `admin_sessions`, `rate_limits` 테이블과 RPC 3개, RLS/권한을 만듭니다. 샘플 데이터는 넣지 않습니다.
- `memos` 또는 `memo_credentials`가 이미 있으면 가드가 중단시킵니다(기존 데이터 보호). 이 경우 B를 사용하세요.

**B. 기존 데이터가 있는 DB → `migration.sql`**

적용 전제조건:

1. **백업**(또는 Supabase 브랜치/스냅샷)을 먼저 만듭니다.
2. `precheck.sql`을 먼저 실행해 현재 구조(컬럼, 정책, 권한, `password_hash` 형식·누락)를 확인합니다.
3. `memos.id`는 `uuid`, `title`/`content` 컬럼이 있어야 합니다.
4. 기존 `memos.password_hash`가 있다면 모두 bcrypt 해시(`$2a$/$2b$/$2y$`)여야 합니다. 아니면 트랜잭션 전체가 롤백됩니다.
5. SQL Editor에서 한 번에 실행합니다(트랜잭션, 재실행 가능).

동작: 필요한 컬럼 추가 → `memo_credentials` 생성 → 기존 해시 이전 → 누락·불일치 검증 → `memos.password_hash` 제거 → 기존 `memos`/비공개 테이블의 정책 전부 제거 후 공개 SELECT 정책만 재생성 → 권한 회수/부여. 메모 ID·제목·내용·생성/수정 일시·기존 해시는 보존됩니다. 이 앱의 4개 테이블 외 다른 테이블과 `public` 스키마 전체 권한은 건드리지 않습니다.

적용 후 `verify.sql`(읽기 전용)로 권한 상태를 확인합니다.

### 2-5. 실행

```bash
npm run dev     # http://localhost:3000
```

## 3. Vercel 배포

> 이 저장소 작업에서는 실제 배포를 하지 않았습니다. 아래는 직접 배포할 때의 절차입니다.

1. GitHub 등에 저장소를 올리고 Vercel에서 Import 합니다. (`.env.local`은 `.gitignore`로 제외됨)
2. Project → Settings → Environment Variables에 위 **다섯 변수**를 Production/Preview에 등록합니다.
   - `ADMIN_PASSWORD_HASH`는 `\` 없이 원본 해시 그대로.
   - 비밀값에 `NEXT_PUBLIC_` 접두사를 붙이지 않습니다.
3. Deploy 합니다. (환경 변수는 빌드 없이도 통과하지만, 런타임에 필요합니다.)
4. 배포 후 확인: 빈 보드 표시 → 작성 → 삭제(올바른/틀린 암호) → 관리자 로그인/개별 삭제/전체 삭제/로그아웃 → 다른 Origin에서의 요청 거부.

## 4. 구조와 보안 설계

- **키 사용**: 브라우저 조회는 Publishable key, 쓰기·암호 검증·삭제·세션·요청 제한은 서버(`lib/supabaseAdmin.ts`, `server-only`)에서 Secret key로 수행. 서버 클라이언트는 `persistSession:false`, `autoRefreshToken:false`.
- **API**: 기존 경로 유지(`/api/memos`, `/api/memos/delete`, `/api/memos/[id]/delete`, `/api/admin/*`). 모든 라우트는 `runtime = "nodejs"`이며 `lib/handlers.ts`의 공통 함수를 호출합니다. 순서: Origin 검사 → 요청 제한 → JSON 파싱 → 검증 → bcrypt → DB.
- **Origin 검사**: 모든 상태 변경 API에서 `Origin` 헤더와 요청 호스트를 비교하며, 없거나 다르면 403. 요청 호스트는 서버가 받은 `Host` 헤더를 사용합니다(Next 16의 `request.url`은 서버 바인딩 호스트라 브라우저 주소와 다를 수 있음). Vercel에서는 https를 요구합니다. 주소 고정이나 별도 환경 변수는 없습니다.
- **클라이언트 IP**: Vercel에서는 `X-Forwarded-For`를 Vercel 엣지가 덮어쓰므로(클라이언트가 위조 불가) 첫 값을 사용하고, Vercel 외 환경(로컬)에서는 헤더를 신뢰하지 않고 단일 버킷으로 처리합니다. 근거: Vercel 공식 문서 *Request headers* (`x-forwarded-for`, `x-real-ip`).
- **요청 제한**(Supabase `rate_limits` + 원자적 RPC `rate_limit_hit`, bcrypt 실행 전 확인, 저장소 오류 시 작업 거부): 작성 IP당 10분 20회 / 삭제 요청 IP당 10분 30회 / 삭제 실패 메모ID+IP당 10분 5회 / 관리자 로그인 실패 IP당 15분 5회. 실패 제한은 시도 전에 소비하고 성공 시 초기화합니다(6번째 시도가 429).
- **관리자 세션**: 무작위 토큰 → `ADMIN_SESSION_SECRET` HMAC 검증값만 DB(`admin_sessions`)에 저장, 수명 8시간, 요청마다 서버 확인, 로그아웃 시 서버 세션 폐기 + 쿠키 삭제. 쿠키: `HttpOnly; SameSite=Strict; Path=/;` 프로덕션 `Secure`.
- **RLS/GRANT**: 4개 앱 테이블 모두 RLS. 일반 사용자(`anon`/`authenticated`)는 `memos`의 공개 컬럼 SELECT만 가능. 비공개 테이블·RPC는 정책 없이 권한을 명시 회수하고 `service_role`만 허용. 함수는 `SECURITY DEFINER` 없이 invoker로 두었습니다.
- **작성 원자성**: `create_memo_with_credentials` RPC가 메모와 암호 해시를 한 트랜잭션으로 저장합니다.

### 알려진 한계

- 여러 IP를 돌려 쓰는 4자리 암호 무차별 대입은 명세된 제한(메모+IP당)으로는 완전히 막을 수 없습니다. 암호는 4자리 숫자이므로 중요한 정보를 메모에 쓰지 마세요.
- `package-lock.json`은 `npm ci`가 통과하도록 `@emnapi/*` optional 의존성 항목만 추가해 보정했고 패키지 버전은 올리지 않았습니다. 루트 이름은 `mindlet`입니다.

## 5. 점검 명령

```bash
npm run lint
npx tsc --noEmit
npm run build
```
