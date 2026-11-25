-- MINDLET migration.sql : "데이터가 이미 있는" 기존 DB를 새 구조로 바꿉니다.
--
-- 적용 전제조건
--   1. 먼저 precheck.sql 을 실행해 현재 구조와 데이터를 눈으로 확인합니다.
--   2. 백업(Supabase 대시보드 > Database > Backups, 또는 pg_dump)을 만들어 둡니다.
--   3. public.memos 에 id(uuid), title(text), content(text) 컬럼이 있어야 합니다.
--      그렇지 않으면 이 스크립트는 추정으로 진행하지 않고 중단합니다.
--   4. 기존 암호 해시가 memos.password_hash 에 bcrypt($2a/$2b) 형식으로 들어 있어야 합니다.
--   5. SQL Editor(postgres 역할)에서 한 번에 실행합니다. 전체가 하나의 트랜잭션이라
--      중간에 검증이 실패하면 아무것도 바뀌지 않고 롤백됩니다.
--   6. 여러 번 실행해도 안전하도록 작성되어 있습니다.
--
-- 보존되는 것: 메모 id, 제목/내용, 생성/수정 일시, 기존 bcrypt 암호 해시
-- 건드리지 않는 것: 이 앱과 무관한 테이블, public 스키마 전체 권한
-- SQL의 anon / authenticated / service_role 은 DB 역할 이름입니다(레거시 API 키 이름과 무관).

begin;

-- ---------------------------------------------------------------------------
-- 1. 전제조건 확인
-- ---------------------------------------------------------------------------
do $$
declare
  v_type text;
begin
  if to_regclass('public.memos') is null then
    raise exception 'public.memos 가 없습니다. 빈 DB에는 schema.sql 을 사용하세요.';
  end if;

  select data_type into v_type from information_schema.columns
   where table_schema = 'public' and table_name = 'memos' and column_name = 'id';
  if v_type is distinct from 'uuid' then
    raise exception 'public.memos.id 가 uuid 가 아닙니다(현재: %). 자동 마이그레이션을 중단합니다.', coalesce(v_type, '없음');
  end if;

  select data_type into v_type from information_schema.columns
   where table_schema = 'public' and table_name = 'memos' and column_name = 'title';
  if v_type is distinct from 'text' and v_type is distinct from 'character varying' then
    raise exception 'public.memos.title 컬럼을 확인할 수 없습니다. precheck.sql 결과를 확인하세요.';
  end if;

  select data_type into v_type from information_schema.columns
   where table_schema = 'public' and table_name = 'memos' and column_name = 'content';
  if v_type is distinct from 'text' and v_type is distinct from 'character varying' then
    raise exception 'public.memos.content 컬럼을 확인할 수 없습니다. precheck.sql 결과를 확인하세요.';
  end if;

  if to_regclass('public.memo_credentials') is not null
     and (
       select count(*) from information_schema.columns
        where table_schema = 'public' and table_name = 'memo_credentials'
          and column_name in ('memo_id', 'password_hash')
     ) <> 2 then
    raise exception '기존 public.memo_credentials 의 구조가 예상과 다릅니다(memo_id, password_hash 필요).';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. memos 컬럼 보강 (기존 데이터는 그대로 유지)
-- ---------------------------------------------------------------------------
alter table public.memos add column if not exists color text;
alter table public.memos add column if not exists position integer;
alter table public.memos add column if not exists created_at timestamptz;
alter table public.memos add column if not exists updated_at timestamptz;

update public.memos set color = '#fef3c7' where color is null or color = '';
update public.memos set position = 0 where position is null;
update public.memos set created_at = now() where created_at is null;
update public.memos set updated_at = coalesce(created_at, now()) where updated_at is null;

alter table public.memos alter column color set default '#fef3c7';
alter table public.memos alter column color set not null;
alter table public.memos alter column position set default 0;
alter table public.memos alter column position set not null;
alter table public.memos alter column created_at set default now();
alter table public.memos alter column created_at set not null;
alter table public.memos alter column updated_at set default now();
alter table public.memos alter column updated_at set not null;

-- ---------------------------------------------------------------------------
-- 3. 비공개 암호 테이블
-- ---------------------------------------------------------------------------
create table if not exists public.memo_credentials (
  memo_id uuid primary key references public.memos(id) on delete cascade,
  password_hash text not null
);

do $$
declare
  v_fk record;
  v_orphans bigint;
  v_dups bigint;
begin
  -- 중복 검증
  select count(*) into v_dups from (
    select memo_id from public.memo_credentials group by memo_id having count(*) > 1
  ) d;
  if v_dups > 0 then
    raise exception 'memo_credentials 에 memo_id 중복이 % 건 있습니다.', v_dups;
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.memo_credentials'::regclass and contype = 'p'
  ) then
    alter table public.memo_credentials add primary key (memo_id);
  end if;

  -- 메모가 없는 암호 해시(고아 행)는 의미가 없으므로 정리
  select count(*) into v_orphans from public.memo_credentials c
   where not exists (select 1 from public.memos m where m.id = c.memo_id);
  if v_orphans > 0 then
    raise notice 'memos 에 없는 memo_credentials % 건을 삭제합니다.', v_orphans;
    delete from public.memo_credentials c
     where not exists (select 1 from public.memos m where m.id = c.memo_id);
  end if;

  -- 외래키를 "메모 삭제 시 함께 삭제" 로 통일
  for v_fk in
    select conname from pg_constraint
     where conrelid = 'public.memo_credentials'::regclass and contype = 'f'
  loop
    execute format('alter table public.memo_credentials drop constraint %I', v_fk.conname);
  end loop;

  alter table public.memo_credentials
    add constraint memo_credentials_memo_id_fkey
    foreign key (memo_id) references public.memos(id) on delete cascade;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. 기존 암호 해시 이전 + 검증 + 공개 테이블에서 제거
-- ---------------------------------------------------------------------------
do $$
declare
  v_missing bigint;
  v_mismatch bigint;
  v_not_bcrypt bigint;
  v_without bigint;
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'memos' and column_name = 'password_hash'
  ) then
    execute $q$
      select count(*) from public.memos
       where password_hash is not null and btrim(password_hash) <> ''
         and password_hash !~ '^\$2[aby]\$[0-9]{2}\$.{53}$'
    $q$ into v_not_bcrypt;
    if v_not_bcrypt > 0 then
      raise exception 'bcrypt 형식이 아닌 password_hash 가 % 건 있습니다. 자동 이전을 중단합니다.', v_not_bcrypt;
    end if;

    execute $q$
      insert into public.memo_credentials (memo_id, password_hash)
      select id, password_hash from public.memos
       where password_hash is not null and btrim(password_hash) <> ''
      on conflict (memo_id) do nothing
    $q$;

    -- 누락 검증
    execute $q$
      select count(*) from public.memos m
       where m.password_hash is not null and btrim(m.password_hash) <> ''
         and not exists (select 1 from public.memo_credentials c where c.memo_id = m.id)
    $q$ into v_missing;
    if v_missing > 0 then
      raise exception '암호 해시 이전 누락이 % 건 있습니다.', v_missing;
    end if;

    -- 값 일치 검증(이미 다른 해시가 들어 있던 경우 감지)
    execute $q$
      select count(*) from public.memos m
        join public.memo_credentials c on c.memo_id = m.id
       where m.password_hash is not null and btrim(m.password_hash) <> ''
         and c.password_hash <> m.password_hash
    $q$ into v_mismatch;
    if v_mismatch > 0 then
      raise exception 'memos.password_hash 와 memo_credentials.password_hash 가 다른 메모가 % 건 있습니다.', v_mismatch;
    end if;

    -- 이전이 모두 검증된 뒤에만 공개 테이블에서 제거(의존 객체가 있으면 여기서 실패 → 롤백)
    execute 'alter table public.memos drop column password_hash';
  end if;

  select count(*) into v_without from public.memos m
   where not exists (select 1 from public.memo_credentials c where c.memo_id = m.id);
  if v_without > 0 then
    raise notice '작성자 암호가 없는 메모가 % 건 있습니다(관리자만 삭제 가능).', v_without;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 5. 제약조건 (기존 데이터가 위반해도 마이그레이션이 막히지 않도록 NOT VALID)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.memos'::regclass and conname = 'memos_title_length_check') then
    alter table public.memos add constraint memos_title_length_check
      check (char_length(btrim(title)) between 1 and 80) not valid;
  end if;

  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.memos'::regclass and conname = 'memos_content_length_check') then
    alter table public.memos add constraint memos_content_length_check
      check (char_length(btrim(content)) between 1 and 2000) not valid;
  end if;

  if exists (select 1 from public.memos
              where char_length(btrim(title)) not between 1 and 80
                 or char_length(btrim(content)) not between 1 and 2000) then
    raise notice '길이 제한(제목 80자/내용 2000자)을 넘는 기존 메모가 있습니다. 새 메모부터 제한이 적용됩니다.';
  end if;
end
$$;

create index if not exists memos_created_at_idx on public.memos (created_at desc);
create index if not exists memos_position_idx on public.memos (position asc, created_at desc);

-- ---------------------------------------------------------------------------
-- 6. 관리자 세션 / 요청 제한 테이블
-- ---------------------------------------------------------------------------
create table if not exists public.admin_sessions (
  token_hash text primary key check (char_length(token_hash) = 64),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table if not exists public.rate_limits (
  scope text not null,
  key text not null,
  window_start timestamptz not null,
  hit_count integer not null default 0,
  expires_at timestamptz not null,
  primary key (scope, key, window_start)
);

create index if not exists admin_sessions_expires_at_idx on public.admin_sessions (expires_at);
create index if not exists rate_limits_expires_at_idx on public.rate_limits (expires_at);

-- ---------------------------------------------------------------------------
-- 7. 트리거 / 서버 전용 함수 (SECURITY INVOKER)
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists memos_set_updated_at on public.memos;
create trigger memos_set_updated_at
before update on public.memos
for each row
execute function public.set_updated_at();

-- 기존 SECURITY DEFINER 버전이 있을 수 있으므로 지우고 다시 만든다(권한도 아래에서 재설정).
drop function if exists public.create_memo_with_credentials(text, text, text, text);

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

create or replace function public.rate_limit_hit(
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

create or replace function public.rate_limit_reset(p_scope text, p_key text)
returns void
language sql
set search_path = public
as $$
  delete from public.rate_limits where scope = p_scope and key = p_key;
$$;

-- ---------------------------------------------------------------------------
-- 8. RLS: 기존 정책을 모두 지우고 필요한 공개 조회 정책만 다시 만든다.
--    (남아 있는 허용 정책은 `false` 정책을 추가해도 사라지지 않으므로 반드시 삭제)
-- ---------------------------------------------------------------------------
alter table public.memos enable row level security;
alter table public.memo_credentials enable row level security;
alter table public.admin_sessions enable row level security;
alter table public.rate_limits enable row level security;

do $$
declare
  v_policy record;
begin
  for v_policy in
    select policyname, tablename from pg_policies
     where schemaname = 'public'
       and tablename in ('memos', 'memo_credentials', 'admin_sessions', 'rate_limits')
  loop
    execute format('drop policy %I on public.%I', v_policy.policyname, v_policy.tablename);
  end loop;
end
$$;

create policy "Public memos are readable"
on public.memos
for select
to anon, authenticated
using (true);

-- ---------------------------------------------------------------------------
-- 9. GRANT: 이 앱의 테이블/함수만 대상으로 재설정
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
-- 10. 자체 점검: 하나라도 어긋나면 예외로 전체 트랜잭션이 롤백됩니다.
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

  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('memo_credentials', 'admin_sessions', 'rate_limits')
  ) then
    raise exception '비공개 테이블에 정책이 남아 있습니다';
  end if;

  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'memos') <> 1 then
    raise exception 'memos 정책은 공개 조회 정책 1개여야 합니다';
  end if;

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
