-- MINDLET precheck.sql : migration.sql 적용 전 확인용(읽기 전용, 아무것도 변경하지 않음)
-- 결과를 확인한 뒤 migration.sql 을 실행하세요.

-- 1) memos / memo_credentials 컬럼 구조
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('memos', 'memo_credentials', 'admin_sessions', 'rate_limits')
order by table_name, ordinal_position;

-- 2) 제약조건(PK/FK/CHECK)
select conrelid::regclass as table_name, conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace
                   and relname in ('memos', 'memo_credentials', 'admin_sessions', 'rate_limits'))
order by 1, 3, 2;

-- 3) 데이터 개수와 암호 해시 현황 (memos.password_hash 가 있는 경우에만 3-b 실행)
select count(*) as memo_count from public.memos;

-- 3-b) memos.password_hash 컬럼이 있을 때만 실행하세요(없으면 오류가 나도 무방).
select
  count(*) filter (where password_hash is null or btrim(password_hash) = '') as without_hash,
  count(*) filter (where password_hash ~ '^\$2[aby]\$[0-9]{2}\$.{53}$') as bcrypt_hash,
  count(*) filter (where password_hash is not null and btrim(password_hash) <> ''
                     and password_hash !~ '^\$2[aby]\$[0-9]{2}\$.{53}$') as non_bcrypt_hash
from public.memos;

-- 4) RLS 상태
select c.relname, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
order by c.relname;

-- 5) 현재 정책 (남아 있는 허용 정책 확인)
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- 6) 테이블 권한 (anon / authenticated 에 쓰기 권한이 있는지)
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated', 'PUBLIC')
  and table_name in ('memos', 'memo_credentials', 'admin_sessions', 'rate_limits')
order by table_name, grantee, privilege_type;

-- 7) 기존 함수와 SECURITY DEFINER 여부
select p.proname, pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef as security_definer, p.proacl
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('create_memo_with_credentials', 'rate_limit_hit', 'rate_limit_reset', 'set_updated_at');

-- 8) memos 에 의존하는 뷰/기타 객체(password_hash 컬럼 삭제를 막을 수 있음)
select distinct dependent.relname as dependent_object, dependent.relkind
from pg_depend d
join pg_rewrite r on r.oid = d.objid
join pg_class dependent on dependent.oid = r.ev_class
where d.refobjid = 'public.memos'::regclass and dependent.oid <> 'public.memos'::regclass;
