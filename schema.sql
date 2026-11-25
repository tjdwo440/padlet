-- MINDLET schema.sql : 신규 "빈" Supabase DB 전용
--
-- * Supabase 대시보드 > SQL Editor 에서 한 번에 실행합니다.
-- * 이미 public.memos 가 있는 DB에서는 실행되지 않고 오류로 중단됩니다.
--   그런 DB(데이터 보존 필요)에는 migration.sql 을 사용하세요.
-- * 샘플 데이터는 넣지 않습니다.
-- * SQL의 anon / authenticated / service_role 은 DB 역할 이름이며,
--   레거시 API 키 이름(anon key / service_role key)과 무관합니다.

begin;

do $$
begin
  if to_regclass('public.memos') is not null
     or to_regclass('public.memo_credentials') is not null then
    raise exception 'public.memos 또는 public.memo_credentials 가 이미 있습니다. 기존 DB에는 migration.sql 을 사용하세요.';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 테이블
-- ---------------------------------------------------------------------------

-- 공개 메모. 암호/암호 해시는 이 테이블에 저장하지 않습니다.
create table public.memos (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 80),
  content text not null check (char_length(btrim(content)) between 1 and 2000),
  color text not null default '#fef3c7' check (char_length(color) > 0),
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 작성자 암호(bcrypt) 해시. 서버(Secret key)만 접근합니다.
create table public.memo_credentials (
  memo_id uuid primary key references public.memos(id) on delete cascade,
  password_hash text not null
);

-- 관리자 세션. 원본 토큰이 아니라 HMAC 검증값만 저장합니다.
create table public.admin_sessions (
  token_hash text primary key check (char_length(token_hash) = 64),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

-- 요청 횟수 제한(고정 윈도우 카운터). 키에는 IP 원문이 아니라 HMAC 값이 들어갑니다.
create table public.rate_limits (
  scope text not null,
  key text not null,
  window_start timestamptz not null,
  hit_count integer not null default 0,
  expires_at timestamptz not null,
  primary key (scope, key, window_start)
);

create index memos_created_at_idx on public.memos (created_at desc);
create index memos_position_idx on public.memos (position asc, created_at desc);
create index admin_sessions_expires_at_idx on public.admin_sessions (expires_at);
create index rate_limits_expires_at_idx on public.rate_limits (expires_at);

-- ---------------------------------------------------------------------------
-- 트리거 / 서버 전용 함수
--   SECURITY INVOKER(기본값)입니다. 호출자(service_role)의 권한으로만 실행되므로
--   SECURITY DEFINER 가 필요하지 않습니다.
-- ---------------------------------------------------------------------------

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger memos_set_updated_at
before update on public.memos
for each row
execute function public.set_updated_at();

-- 메모와 암호 해시를 한 트랜잭션으로 저장합니다(암호 없는 메모가 남지 않음).
create function public.create_memo_with_credentials(
  p_title text,
  p_content text,
  p_password_hash text,
  p_color text default '#fef3c7'
)
returns public.memos
language plpgsql
set search_path = public
as $$
declare
  inserted_memo public.memos;
begin
  if p_title is null or char_length(btrim(p_title)) not between 1 and 80 then
    raise exception 'Invalid title length';
  end if;

  if p_content is null or char_length(btrim(p_content)) not between 1 and 2000 then
    raise exception 'Invalid content length';
  end if;

  if p_password_hash is null or p_password_hash !~ '^\$2[aby]\$[0-9]{2}\$.{53}$' then
    raise exception 'Invalid password hash';
  end if;

  insert into public.memos (title, content, color)
  values (p_title, p_content, coalesce(nullif(p_color, ''), '#fef3c7'))
  returning * into inserted_memo;

  insert into public.memo_credentials (memo_id, password_hash)
  values (inserted_memo.id, p_password_hash);

  return inserted_memo;
end;
$$;

-- 윈도우 카운터를 원자적으로 1 증가시키고 허용 여부를 돌려줍니다.
create function public.rate_limit_hit(
  p_scope text,
  p_key text,
  p_limit integer,
  p_window_seconds integer
)
returns table (allowed boolean, retry_after_seconds integer)
language plpgsql
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_count integer;
begin
  if p_scope is null or p_key is null or p_limit < 1 or p_window_seconds < 1 then
    raise exception 'Invalid rate limit arguments';
  end if;

  v_window_start :=
    to_timestamp(floor(extract(epoch from v_now) / p_window_seconds) * p_window_seconds);
  v_window_end := v_window_start + make_interval(secs => p_window_seconds);

  if random() < 0.02 then
    delete from public.rate_limits where expires_at < v_now;
  end if;

  insert into public.rate_limits as r (scope, key, window_start, hit_count, expires_at)
  values (p_scope, p_key, v_window_start, 1, v_window_end)
  on conflict (scope, key, window_start)
  do update set hit_count = r.hit_count + 1
  returning r.hit_count into v_count;

  return query
  select
    v_count <= p_limit,
    greatest(1, ceil(extract(epoch from (v_window_end - v_now)))::integer);
end;
$$;

create function public.rate_limit_reset(p_scope text, p_key text)
returns void
language sql
set search_path = public
as $$
  delete from public.rate_limits where scope = p_scope and key = p_key;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.memos enable row level security;
alter table public.memo_credentials enable row level security;
alter table public.admin_sessions enable row level security;
alter table public.rate_limits enable row level security;

-- 공개 조회만 허용합니다. INSERT/UPDATE/DELETE 정책은 만들지 않으므로(기본 거부)
-- 직접 쓰기는 RLS 와 아래 GRANT 양쪽에서 막힙니다.
create policy "Public memos are readable"
on public.memos
for select
to anon, authenticated
using (true);

-- memo_credentials / admin_sessions / rate_limits 에는 일반 사용자용 정책을 만들지 않습니다.

-- ---------------------------------------------------------------------------
-- GRANT (이 앱의 테이블/함수에만 적용. public 스키마 전체 권한은 건드리지 않음)
-- ---------------------------------------------------------------------------

grant usage on schema public to anon, authenticated, service_role;

revoke all on table public.memos from public, anon, authenticated;
revoke all on table public.memo_credentials from public, anon, authenticated;
revoke all on table public.admin_sessions from public, anon, authenticated;
revoke all on table public.rate_limits from public, anon, authenticated;

grant select on table public.memos to anon, authenticated;

grant all on table public.memos to service_role;
grant all on table public.memo_credentials to service_role;
grant all on table public.admin_sessions to service_role;
grant all on table public.rate_limits to service_role;

revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.create_memo_with_credentials(text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.rate_limit_hit(text, text, integer, integer)
  from public, anon, authenticated;
revoke all on function public.rate_limit_reset(text, text)
  from public, anon, authenticated;

grant execute on function public.create_memo_with_credentials(text, text, text, text)
  to service_role;
grant execute on function public.rate_limit_hit(text, text, integer, integer)
  to service_role;
grant execute on function public.rate_limit_reset(text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 자체 점검: 하나라도 어긋나면 예외로 전체 트랜잭션이 롤백됩니다.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
  r text;
begin
  foreach t in array array['memos', 'memo_credentials', 'admin_sessions', 'rate_limits'] loop
    if not (select c.relrowsecurity from pg_class c
            where c.oid = ('public.' || t)::regclass) then
      raise exception 'RLS 가 꺼져 있습니다: %', t;
    end if;

    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, 'public.' || t, 'insert, update, delete, truncate, references, trigger') then
        raise exception '% 역할에 % 쓰기 권한이 남아 있습니다', r, t;
      end if;
      if t <> 'memos' and has_table_privilege(r, 'public.' || t, 'select') then
        raise exception '% 역할이 % 를 조회할 수 있습니다', r, t;
      end if;
    end loop;
  end loop;

  foreach r in array array['anon', 'authenticated'] loop
    if has_function_privilege(r, 'public.create_memo_with_credentials(text, text, text, text)', 'execute')
       or has_function_privilege(r, 'public.rate_limit_hit(text, text, integer, integer)', 'execute')
       or has_function_privilege(r, 'public.rate_limit_reset(text, text)', 'execute') then
      raise exception '% 역할이 서버 전용 함수를 실행할 수 있습니다', r;
    end if;
  end loop;
end
$$;

commit;
