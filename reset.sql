-- MINDLET reset.sql : 이 앱의 테이블/함수만 삭제합니다 (개발·연습용 DB 전용)
--
-- !! 경고: memos 의 모든 메모와 암호 해시, 관리자 세션, 요청 제한 기록이 영구 삭제됩니다.
-- !! 남겨야 할 메모가 있으면 실행하지 말고 migration.sql 을 사용하세요.
--
-- 사용 순서: reset.sql 실행 -> schema.sql 실행
-- 다른 테이블과 public 스키마 전체 권한은 건드리지 않습니다.

begin;

drop table if exists public.memo_credentials cascade;
drop table if exists public.memos cascade;
drop table if exists public.admin_sessions cascade;
drop table if exists public.rate_limits cascade;

drop function if exists public.create_memo_with_credentials(text, text, text, text) cascade;
drop function if exists public.rate_limit_hit(text, text, integer, integer) cascade;
drop function if exists public.rate_limit_reset(text, text) cascade;
-- 다른 테이블의 트리거가 쓰고 있으면 오류로 중단되며(전체 롤백), 그때는 아래 줄을 지우고 진행하세요.
drop function if exists public.set_updated_at();

commit;
