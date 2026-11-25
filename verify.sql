-- MINDLET verify.sql : schema.sql / migration.sql 적용 후 권한 점검(읽기 전용)
-- 기대 결과는 각 항목 위 주석을 참고하세요.

-- 1) 4개 앱 테이블 모두 rls_enabled = true
select relname, relrowsecurity as rls_enabled
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('memos', 'memo_credentials', 'admin_sessions', 'rate_limits');

-- 2) 정책: memos 에 select 정책 1개(anon, authenticated)만 있고 나머지 테이블은 0개
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- 3) anon / authenticated 권한: memos 의 SELECT 만 true, 나머지는 모두 false
select r.role_name, t.table_name,
       has_table_privilege(r.role_name, 'public.' || t.table_name, 'select') as can_select,
       has_table_privilege(r.role_name, 'public.' || t.table_name, 'insert') as can_insert,
       has_table_privilege(r.role_name, 'public.' || t.table_name, 'update') as can_update,
       has_table_privilege(r.role_name, 'public.' || t.table_name, 'delete') as can_delete
from (values ('anon'), ('authenticated')) as r(role_name)
cross join (values ('memos'), ('memo_credentials'), ('admin_sessions'), ('rate_limits')) as t(table_name)
order by 1, 2;

-- 4) 함수 실행 권한: anon / authenticated 는 모두 false, service_role 만 true
select f.fn, r.role_name, has_function_privilege(r.role_name, f.fn, 'execute') as can_execute
from (values
  ('public.create_memo_with_credentials(text, text, text, text)'),
  ('public.rate_limit_hit(text, text, integer, integer)'),
  ('public.rate_limit_reset(text, text)')
) as f(fn)
cross join (values ('anon'), ('authenticated'), ('service_role')) as r(role_name)
order by 1, 2;

-- 5) 공개 테이블에 password_hash 컬럼이 없어야 함(0 행)
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'memos' and column_name = 'password_hash';

-- 6) 암호 없는 메모(마이그레이션 전부터 암호가 없던 데이터만 존재해야 함)
select count(*) as memos_without_credentials
from public.memos m
where not exists (select 1 from public.memo_credentials c where c.memo_id = m.id);

-- 7) 함수는 모두 SECURITY INVOKER(security_definer = false) 이어야 함
select proname, prosecdef as security_definer
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('create_memo_with_credentials', 'rate_limit_hit', 'rate_limit_reset', 'set_updated_at');
