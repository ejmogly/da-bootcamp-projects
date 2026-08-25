-- ============================================================
-- 공통 전처리 SQL
-- 작성일: 2026-06-30
-- 대상 DB: votes (votes DB), votes (hackle DB)
--
-- [실행 순서]
-- 1. votes DB 전처리 (accounts_* 테이블)
-- 2. votes DB 전처리 (hackle_events 테이블)
-- 3. 집계 뷰 생성 (유저별 피처 집계)
-- 4. 마스터 테이블 생성 (v_common_master → master_table)
--
-- [preprocessing.sql과의 관계]
-- preprocessing.sql의 v_* 뷰(v_user_base, v_conversion_master 등)는
--
-- [status 값 정의]
-- accounts_friendrequest.status : A=수락, P=대기, R=거절
-- accounts_user.ban_status      : N=정상, W=탈퇴(?)/경고(?), NB=계정정지, RB=제한정지
--   ※ ban_status W 정의 팀 내 확인 필요
-- ============================================================


-- ============================================================
-- STEP 0. 기존 테이블/뷰 삭제 (재실행 시 에러 방지)
-- ============================================================
USE votes;

DROP TABLE IF EXISTS master_table;
DROP TABLE IF EXISTS accounts_user_clean;
DROP TABLE IF EXISTS accounts_friendrequest_clean;
DROP TABLE IF EXISTS accounts_attendance_clean;
DROP TABLE IF EXISTS accounts_paymenthistory_clean;
DROP TABLE IF EXISTS accounts_pointhistory_clean;
DROP TABLE IF EXISTS accounts_group_clean;
DROP TABLE IF EXISTS accounts_user_contacts_clean;

DROP VIEW IF EXISTS v_friend_stats;
DROP VIEW IF EXISTS v_friend_edges;
DROP VIEW IF EXISTS v_vote_sender_stats;
DROP VIEW IF EXISTS v_vote_receiver_stats;
DROP VIEW IF EXISTS v_payment_stats;
DROP VIEW IF EXISTS v_point_stats;
DROP VIEW IF EXISTS v_hackle_stats;

USE votes;
DROP TABLE IF EXISTS hackle_events_clean;


-- ============================================================
-- STEP 1. votes DB 전처리
-- ============================================================
USE votes;


-- ------------------------------------------------------------
-- 1. accounts_user
--    - is_superuser=1, is_staff=1 제거 (봇/관리자 계정)
--    - gender(2건), group_id(3건) 결측 제거 → 총 5행 감소
--    - friend_id_list, block_user_id_list, hide_user_id_list
--      → JSON_LENGTH로 갯수 컬럼 생성 후 원본 리스트 제외
--    ※ is_superuser/is_staff 제거 시 다른 테이블(friendrequest,
--      paymenthistory 등)에도 해당 유저 데이터가 남아 있으므로
--      JOIN 시 accounts_user_clean 기준으로 필터링할 것
-- ------------------------------------------------------------
CREATE TABLE accounts_user_clean AS
SELECT
    id,
    gender,
    group_id,
    ban_status,
    point,
    is_push_on,
    created_at,
    report_count,
    alarm_count,
    pending_chat,
    pending_votes,
    JSON_LENGTH(friend_id_list)       AS friend_count,
    JSON_LENGTH(block_user_id_list)   AS block_user_count,
    JSON_LENGTH(hide_user_id_list)    AS hide_user_count
FROM accounts_user
WHERE is_superuser = 0
  AND is_staff     = 0
  AND gender       IS NOT NULL
  AND group_id     IS NOT NULL;

-- 최종 row 수 확인
SELECT COUNT(*) AS user_cnt FROM accounts_user_clean;


-- ------------------------------------------------------------
-- 2. accounts_friendrequest
--    - 완전 중복 63건 제거 (pk id 보존)
--    - 원본 유지 (재요청 중복은 의도적 행동으로 판단, 삭제 안 함)
--    ※ status 활용 기준
--      - 친구 관계 엣지 생성 시 : status='A'만 사용
--      - 요청 수 집계 시 : 전체 status 사용
-- ------------------------------------------------------------
CREATE TABLE accounts_friendrequest_clean AS
SELECT f.*
FROM accounts_friendrequest f
JOIN (
    SELECT MIN(id) AS id
    FROM accounts_friendrequest
    GROUP BY status, created_at, updated_at, receive_user_id, send_user_id
) d ON f.id = d.id;

-- row 수 확인
SELECT COUNT(*) AS friendrequest_cnt FROM accounts_friendrequest_clean;


-- ------------------------------------------------------------
-- 3. accounts_attendance
--    - 결측/중복 없음
--    - attendance_date_list 빈 배열('[]') 20,945건 → 출석 0회로 처리, 삭제 안 함
--    - JSON_LENGTH로 출석 횟수 컬럼 추가 ('[]' → 0)
--    - 첫/마지막 출석일 파싱은 Python에서 처리
-- ------------------------------------------------------------
CREATE TABLE accounts_attendance_clean AS
SELECT
    *,
    JSON_LENGTH(attendance_date_list) AS attendance_count
FROM accounts_attendance;

-- row 수 확인
SELECT COUNT(*) AS attendance_cnt FROM accounts_attendance_clean;


-- ------------------------------------------------------------
-- 4. accounts_paymenthistory
--    - 완전 중복 제거 (중복 전 95,140건 → 후 94,609건 예상), pk id 보존
-- ------------------------------------------------------------
CREATE TABLE accounts_paymenthistory_clean AS
SELECT p.*
FROM accounts_paymenthistory p
JOIN (
    SELECT MIN(id) AS id
    FROM accounts_paymenthistory
    GROUP BY productId, phone_type, created_at, user_id
) d ON p.id = d.id;

-- row 수 확인
SELECT COUNT(*) AS payment_cnt FROM accounts_paymenthistory_clean;


-- ------------------------------------------------------------
-- 5. accounts_pointhistory
--    - user_question_record_id 결측 2,992건 → 유지
--      (포인트 집계에 해당 컬럼 불필요, 출석 보상 등 다른 경로 포인트)
--    - 완전 중복 1,939건 제거, pk id 보존
-- ------------------------------------------------------------
CREATE TABLE accounts_pointhistory_clean AS
SELECT p.*
FROM accounts_pointhistory p
JOIN (
    SELECT MIN(id) AS id
    FROM accounts_pointhistory
    GROUP BY delta_point, created_at, user_id, user_question_record_id
) d ON p.id = d.id;

-- row 수 확인 (2,336,979건 예상)
SELECT COUNT(*) AS pointhistory_cnt FROM accounts_pointhistory_clean;


-- ------------------------------------------------------------
-- 6. accounts_group
--    - 중복 5건 제거 (id 작은 것 원본으로 유지)
--    ※ id 컬럼 유지 필수 → accounts_user.group_id와 JOIN 키로 사용
-- ------------------------------------------------------------
CREATE TABLE accounts_group_clean AS
SELECT g.*
FROM accounts_group g
JOIN (
    SELECT MIN(id) AS id
    FROM accounts_group
    GROUP BY grade, class_num, school_id
) d ON g.id = d.id;

-- row 수 확인 (84,510건 예상)
SELECT COUNT(*) AS group_cnt FROM accounts_group_clean;


-- ------------------------------------------------------------
-- 7. accounts_user_contacts
--    - invite_user_id_list JSON 배열 → 길이(초대 수) 컬럼 추가
--    - 상세 파싱(누구를 초대했는지)은 Python에서 처리
-- ------------------------------------------------------------
CREATE TABLE accounts_user_contacts_clean AS
SELECT
    *,
    JSON_LENGTH(invite_user_id_list) AS invite_user_count
FROM accounts_user_contacts;

-- row 수 확인
SELECT COUNT(*) AS contacts_cnt FROM accounts_user_contacts_clean;


-- ============================================================
-- STEP 2. votes DB 전처리
-- ============================================================
USE votes;


-- ------------------------------------------------------------
-- 8. hackle_events
--    - event_id 전부 고유, 중복 없음
--    - id 컬럼 = event_id와 동일 → id 컬럼 제외
--    - friend_count, votes_count, heart_balance, question_id 결측 존재
--      → 이벤트 종류에 따라 해당 값이 없는 게 정상이므로 유지
--      → 분석 시 필요한 event_key로 필터링해서 사용
--    - session_id, event_datetime 기준 정렬
-- ------------------------------------------------------------
CREATE TABLE hackle_events_clean AS
SELECT
    event_id,
    event_datetime,
    event_key,
    session_id,
    item_name,
    page_name,
    friend_count,
    votes_count,
    heart_balance,
    question_id
FROM hackle_events;

-- row 수 확인
SELECT COUNT(*) AS hackle_cnt FROM hackle_events_clean;


-- ============================================================
-- STEP 3. 집계 뷰 생성 (유저별 피처 집계)
-- ============================================================
USE votes;


-- ------------------------------------------------------------
-- 9. 친구 네트워크 집계
--    - 발신/수신 양방향 집계 후 합산
--    - 전체 요청 수(status 무관) + 수락 수(status='A')
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_friend_stats AS
SELECT
    user_id,
    SUM(sent_total)                                          AS sent_request_count,
    SUM(sent_accepted)                                       AS accepted_sent_count,
    SUM(received_total)                                      AS received_request_count,
    SUM(received_accepted)                                   AS accepted_received_count,
    SUM(sent_accepted) + SUM(received_accepted)              AS accepted_friend_count,
    ROUND(
        (SUM(sent_accepted) + SUM(received_accepted))
        / NULLIF(SUM(sent_total) + SUM(received_total), 0)
    , 4)                                                     AS friend_accept_rate
FROM (
    SELECT
        send_user_id        AS user_id,
        COUNT(*)            AS sent_total,
        SUM(status = 'A')   AS sent_accepted,
        0                   AS received_total,
        0                   AS received_accepted
    FROM accounts_friendrequest_clean
    GROUP BY send_user_id

    UNION ALL

    SELECT
        receive_user_id     AS user_id,
        0, 0,
        COUNT(*)            AS received_total,
        SUM(status = 'A')   AS received_accepted
    FROM accounts_friendrequest_clean
    GROUP BY receive_user_id
) combined
GROUP BY user_id;


-- ------------------------------------------------------------
-- 10. 친구 관계 엣지 + 시점
--     - 허브유저 이웃 추출 및 친구 맺기 전후 활성화 분석에 사용
--     - status='A'(수락) 양방향 엣지 생성
--     - updated_at = 친구 관계 확정 시점
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_friend_edges AS
SELECT send_user_id AS user_id, receive_user_id AS friend_id, updated_at AS friend_date
FROM accounts_friendrequest_clean
WHERE status = 'A'

UNION ALL

SELECT receive_user_id, send_user_id, updated_at
FROM accounts_friendrequest_clean
WHERE status = 'A';


-- ------------------------------------------------------------
-- 11. 투표 활동 집계
--     - 발신자(투표한 수) / 수신자(득표 수) 각각 집계
--     - accounts_userquestionrecord 원본 사용
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_vote_sender_stats AS
SELECT
    user_id,
    COUNT(*)                     AS vote_given_count,
    COUNT(DISTINCT question_id)  AS question_participation_count,
    SUM(opened_times)            AS result_open_count
FROM accounts_userquestionrecord
GROUP BY user_id;

CREATE OR REPLACE VIEW v_vote_receiver_stats AS
SELECT
    chosen_user_id               AS user_id,
    COUNT(*)                     AS vote_received_count,
    SUM(status = 'C')            AS closed_cnt,
    SUM(status = 'I')            AS initial_open_cnt,
    SUM(status = 'B')            AS blocked_cnt,
    SUM(answer_status = 'A')     AS answered_cnt,
    ROUND(
        SUM(answer_status = 'A') / NULLIF(COUNT(*), 0)
    , 4)                         AS answer_rate
FROM accounts_userquestionrecord
GROUP BY chosen_user_id;


-- ------------------------------------------------------------
-- 12. 결제 집계
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_payment_stats AS
SELECT
    p.user_id,
    COUNT(*)                                          AS total_payments,
    MIN(p.created_at)                                 AS first_pay_at,
    MAX(p.created_at)                                 AS last_pay_at,
    DATEDIFF(MIN(p.created_at), u.created_at)         AS days_to_first_pay,
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END          AS is_paid
FROM accounts_paymenthistory_clean p
JOIN accounts_user_clean u ON p.user_id = u.id
GROUP BY p.user_id, u.created_at;


-- ------------------------------------------------------------
-- 13. 포인트 집계
--     - delta_point > 0 : 획득 / delta_point < 0 : 사용
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_point_stats AS
SELECT
    user_id,
    SUM(CASE WHEN delta_point > 0 THEN 1    ELSE 0 END)          AS point_earn_count,
    SUM(CASE WHEN delta_point < 0 THEN 1    ELSE 0 END)          AS point_use_count,
    SUM(CASE WHEN delta_point > 0 THEN delta_point ELSE 0 END)   AS total_earned_point,
    ABS(SUM(CASE WHEN delta_point < 0 THEN delta_point ELSE 0 END)) AS total_used_point
FROM accounts_pointhistory_clean
GROUP BY user_id;


-- ------------------------------------------------------------
-- 14. hackle 집계 (votes 기준)
--     - session_id → user_id 연결은 hackle_properties 경유
--     - 세션 수, 전체 이벤트 수, 앱 실행 수 집계
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW votes.v_hackle_stats AS
SELECT
    hp.user_id,
    COUNT(DISTINCT he.session_id)         AS session_count,
    COUNT(*)                              AS event_count,
    SUM(he.event_key = 'launch_app')      AS launch_app_count,
    SUM(he.event_key = '$session_start')  AS session_start_count
FROM votes.hackle_events_clean he
JOIN votes.hackle_properties   hp ON he.session_id = hp.session_id
GROUP BY hp.user_id;


-- ============================================================
-- STEP 4. 마스터 테이블 생성
--   accounts_user_clean 기준 LEFT JOIN → 전체 유저 수 유지
--   한 번 실행 후 master_table로 저장 → 이후 CSV 또는
--   SELECT * FROM master_table 로 불러와서 사용
-- ============================================================
DROP TABLE IF EXISTS master_table;

CREATE TABLE master_table AS
SELECT
    u.id                                         AS user_id,
    u.gender,
    u.group_id,
    u.ban_status,
    u.point,
    u.created_at,
    u.friend_count,
    u.block_user_count,
    u.hide_user_count,

    -- 친구 네트워크
    COALESCE(fr.sent_request_count,      0)      AS sent_request_count,
    COALESCE(fr.accepted_sent_count,     0)      AS accepted_sent_count,
    COALESCE(fr.received_request_count,  0)      AS received_request_count,
    COALESCE(fr.accepted_received_count, 0)      AS accepted_received_count,
    COALESCE(fr.accepted_friend_count,   0)      AS accepted_friend_count,
    COALESCE(fr.friend_accept_rate,      0)      AS friend_accept_rate,

    -- 투표 발신
    COALESCE(vs.vote_given_count,            0)  AS vote_given_count,
    COALESCE(vs.question_participation_count,0)  AS question_participation_count,
    COALESCE(vs.result_open_count,           0)  AS result_open_count,

    -- 투표 수신
    COALESCE(vr.vote_received_count,     0)      AS vote_received_count,
    COALESCE(vr.closed_cnt,              0)      AS closed_cnt,        
    COALESCE(vr.initial_open_cnt,        0)      AS initial_open_cnt,
    COALESCE(vr.blocked_cnt,             0)      AS blocked_cnt,
    COALESCE(vr.answer_rate,             0)      AS answer_rate,

    -- 출석
    COALESCE(at.attendance_count,        0)      AS attendance_count,

    -- 결제
    COALESCE(py.total_payments,          0)      AS total_payments,
    COALESCE(py.is_paid,                 0)      AS is_paid,
    py.first_pay_at,
    py.days_to_first_pay,

    -- 포인트
    COALESCE(pt.point_earn_count,        0)      AS point_earn_count,
    COALESCE(pt.point_use_count,         0)      AS point_use_count,
    COALESCE(pt.total_earned_point,      0)      AS total_earned_point,
    COALESCE(pt.total_used_point,        0)      AS total_used_point,

    -- 초대
    COALESCE(ct.invite_user_count,       0)      AS invited_cnt

FROM accounts_user_clean u
LEFT JOIN v_friend_stats        fr ON u.id = fr.user_id
LEFT JOIN v_vote_sender_stats   vs ON u.id = vs.user_id
LEFT JOIN v_vote_receiver_stats vr ON u.id = vr.user_id
LEFT JOIN accounts_attendance_clean at ON u.id = at.user_id
LEFT JOIN v_payment_stats       py ON u.id = py.user_id
LEFT JOIN v_point_stats         pt ON u.id = pt.user_id
LEFT JOIN accounts_user_contacts_clean ct ON u.id = ct.user_id
;

-- 최종 확인
SELECT COUNT(*) AS total_users FROM master_table;
SELECT * FROM master_table LIMIT 5;


-- ============================================================
-- hackle DB 전처리 (데이터 #2 유저 이벤트 데이터)
-- ============================================================
USE final;


-- ------------------------------------------------------------
-- 1. hackle_properties
--    - PK: id
--    - session_id → user_id 연결 키 테이블
-- ------------------------------------------------------------
DROP TABLE IF EXISTS hackle_properties_clean;

CREATE TABLE hackle_properties_clean AS
SELECT *
FROM hackle_properties
WHERE user_id REGEXP '^[0-9]+$'
  AND user_id IS NOT NULL
  AND user_id != '';

-- 확인
SELECT
    COUNT(*)                    AS total,
    COUNT(DISTINCT user_id)     AS unique_users,
    COUNT(DISTINCT session_id)  AS unique_sessions
FROM hackle_properties_clean;
  
       
-- row 수 확인
SELECT COUNT(*) AS hackle_properties_cnt FROM hackle_properties_clean;

-- 샘플 데이터 확인
SELECT * FROM hackle_properties_clean LIMIT 10;

-- ------------------------------------------------------------
-- 2. device_properties
--    - PK: id
--    - device_id 기준 장치 정보 테이블
-- ------------------------------------------------------------
-- device_properties 완전 중복 확인
SELECT COUNT(*) AS total,
       COUNT(DISTINCT CONCAT(id, '|', device_id, '|', 
                             device_model, '|', device_vendor)) AS distinct_cnt
FROM device_properties;

CREATE TABLE device_properties_clean AS
SELECT d.*
FROM device_properties d
JOIN (
    SELECT MIN(id) AS id
    FROM device_properties
    GROUP BY device_id, device_model, device_vendor
) dedup ON d.id = dedup.id;

-- row 수 확인
SELECT COUNT(*) AS device_properties_cnt FROM device_properties_clean;

-- 샘플 데이터 확인
SELECT * FROM device_properties_clean LIMIT 10;

-- ------------------------------------------------------------
-- 3. hackle_events
--     - PK: event_id
--     - event_id 전부 고유, 중복 없음
--       결측 존재 → 이벤트 종류에 따라 해당 값이 없는 게
--       정상이므로 유지
--       → 분석 시 필요한 event_key로 필터링해서 사용
--     - session_id → hackle_properties_clean 경유
--       → user_id 연결
-- ------------------------------------------------------------
DROP TABLE IF EXISTS hackle_events_clean;

CREATE TABLE hackle_events_clean AS
SELECT
    event_id,
    event_datetime,
    event_key,
    session_id,
    item_name,
    page_name,
    friend_count,
    votes_count,
    heart_balance,
    question_id
FROM hackle_events;

-- row 수 확인
SELECT COUNT(*) AS hackle_events_cnt FROM hackle_events_clean;

-- 샘플 데이터 확인
SELECT * FROM hackle_events_clean LIMIT 10;

-- ------------------------------------------------------------
-- 4. user_properties
--     - PK: user_id (accounts_user.id와 연결)
--     - 유저별 학교/학년/반/성별 정보 테이블
--     - hackle_properties.user_id와 JOIN하여
--       유저 세그먼트 분석에 활용
--     - 중복 여부 확인 후 제거
-- ------------------------------------------------------------
-- user_properties 완전 중복 확인
SELECT COUNT(*) AS total,
       COUNT(DISTINCT CONCAT(user_id, '|', class, '|', 
                             gender, '|', grade, '|', school_id)) AS distinct_cnt
FROM user_properties;

DROP TABLE IF EXISTS user_properties_clean;

CREATE TABLE user_properties_clean AS
SELECT * FROM user_properties;

-- row 수 확인
SELECT COUNT(*) AS user_properties_cnt FROM user_properties_clean;

-- 샘플 데이터 확인
SELECT * FROM user_properties LIMIT 10;


-- ------------------------------------------------------------
-- 5. 핵심 지표 집계 (hackle_properties 기준)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS hub_user_base_hackle;

CREATE TABLE hub_user_base_hackle AS
SELECT
    hp.user_id,

    -- 1. 친구 수 (이벤트 발생 시점 최댓값) → accepted_friend_count 대응
    MAX(he.friend_count)                                   AS max_friend_count,

    -- 2. 투표 수신 수 (이벤트 발생 시점 최댓값) → vote_received_count 대응
    MAX(he.votes_count)                                    AS max_votes_count,

    -- 3. 초성 열람 대체 → initial_open_cnt 대응
    SUM(he.event_key = 'click_question_open')              AS question_open_cnt,

    -- 참고용 부가 지표 (전파 분석에 활용 가능)
    SUM(he.event_key = 'complete_question')                AS complete_question_cnt,
    SUM(he.event_key = 'click_appbar_friend_plus')          AS friend_plus_cnt,
    SUM(he.event_key = 'click_friend_invite')               AS friend_invite_cnt,
    SUM(he.event_key = 'click_timeline_chat_start')         AS chat_start_cnt,
    COUNT(DISTINCT he.session_id)                           AS session_cnt

FROM hackle_events_clean he
JOIN hackle_properties_clean hp ON he.session_id = hp.session_id
WHERE he.friend_count IS NOT NULL
  AND he.votes_count  IS NOT NULL
GROUP BY hp.user_id;

-- 결과 확인
SELECT COUNT(*) AS total_users FROM hub_user_base_hackle;

-- ============================================================
-- 데이터 #2 (유저 이벤트 데이터) 정합성 검토
-- 검토 배경: 데이터 #1(약 14개월)과 데이터 #2(23일)의 기간 불균형으로
--            데이터 #2를 독립적으로 분석하는 방향을 검토하는 과정에서
--            3가지 정합성 문제를 발견하여 아래와 같이 정리함
-- ============================================================


-- ============================================================
-- 문제 1 hackle_properties 테이블의 user_id 오류
-- ============================================================

-- 1. 전체 user_id 구성 확인 (숫자형 / NULL 및 빈값 / 문자열)
SELECT
    COUNT(*)                                                          AS total,
    SUM(user_id REGEXP '^[0-9]+$')                                   AS numeric_cnt,
    SUM(user_id IS NULL OR user_id = '')                             AS null_empty_cnt,
    SUM(user_id NOT REGEXP '^[0-9]+$'
        AND user_id IS NOT NULL
        AND user_id != '')                                            AS string_cnt
FROM hackle_properties;
-- 결과: 숫자형 334,091건(63.6%) / NULL·빈값 82,255건(15.7%) / 문자열 109,004건(20.7%)


-- 2-1. 문자열 user_id를 가진 세션에서 발생한 event_key 분포 확인
--       (어떤 행동을 하는 세션인지 파악)
SELECT
    he.event_key,
    COUNT(*) AS cnt,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct
FROM hackle_properties hp
JOIN hackle_events_clean he ON hp.session_id = he.session_id
WHERE hp.user_id NOT REGEXP '^[0-9]+$'
  AND hp.user_id IS NOT NULL
  AND hp.user_id != ''
GROUP BY he.event_key
ORDER BY cnt DESC;
-- 결과 해석: complete_signup 이벤트가 있으면 "가입 직전 세션" 가능성
--          launch_app, view_login 만 있으면 "로그인 전 단계 세션"
--          결제(complete_purchase)까지 있으면 "로깅 오류" 가능성


-- 2-2. 숫자형 user_id와 문자열 user_id 세션의 행동 패턴 비교
--        (두 그룹의 이벤트 분포가 다른지 확인)
SELECT
    CASE
        WHEN hp.user_id REGEXP '^[0-9]+$' THEN '숫자형(정상)'
        ELSE '문자열(오류)'
    END AS user_id_type,
    he.event_key,
    COUNT(*) AS cnt
FROM hackle_properties hp
JOIN hackle_events_clean he ON hp.session_id = he.session_id
WHERE hp.user_id IS NOT NULL AND hp.user_id != ''
GROUP BY user_id_type, he.event_key
ORDER BY user_id_type, cnt DESC;
-- 해석: 두 그룹의 이벤트 패턴이 유사하여 "동일 유저, 로깅 오류"일 것으로 판단


-- 2-3. 문자열 user_id 세션에 complete_signup이 있는지 직접 확인
SELECT COUNT(*) AS signup_in_string_session
FROM hackle_properties hp
JOIN hackle_events_clean he ON hp.session_id = he.session_id
WHERE hp.user_id NOT REGEXP '^[0-9]+$'
  AND hp.user_id IS NOT NULL
  AND hp.user_id != ''
  AND he.event_key = 'complete_signup';
-- 해석: 값이 존재하는 것으로 보아, 가입 완료 시점 기준 아직 로깅에 반영이 안 된 케이스로 확인


-- 3. 문자열 user_id의 등장 횟수 분포 확인
SELECT
    cnt,
    COUNT(*) AS user_cnt,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct
FROM (
    SELECT user_id, COUNT(*) AS cnt
    FROM hackle_properties
    WHERE user_id NOT REGEXP '^[0-9]+$'
      AND user_id IS NOT NULL
      AND user_id != ''
    GROUP BY user_id
) sub
GROUP BY cnt
ORDER BY cnt;
-- 결과: cnt=1이 87.60%로 압도적 다수 → 비로그인 세션 또는 로깅 오류 추정


-- 4. 문자열 user_id → session_id로 보고 복구 가능 여부 확인
SELECT
    COUNT(*) AS string_total,
    SUM(CASE WHEN hp2.session_id IS NOT NULL THEN 1 ELSE 0 END) AS recoverable,
    SUM(CASE WHEN hp2.session_id IS NULL THEN 1 ELSE 0 END)     AS not_recoverable
FROM hackle_properties hp1
LEFT JOIN (
    SELECT DISTINCT session_id
    FROM hackle_properties
    WHERE user_id REGEXP '^[0-9]+$'
) hp2 ON hp1.user_id = hp2.session_id
WHERE hp1.user_id NOT REGEXP '^[0-9]+$'
  AND hp1.user_id IS NOT NULL
  AND hp1.user_id != '';
-- 결과: 복구 가능 83,856건(77%) / 복구 불가 25,148건(23%)


-- 5. 복구 시 중복 발생 규모 확인 (문자열 user_id 1개당 매핑되는 숫자형 행 수)
SELECT
    cnt,
    COUNT(*) AS case_cnt
FROM (
    SELECT
        hp1.user_id,
        COUNT(hp2.session_id) AS cnt
    FROM hackle_properties hp1
    JOIN hackle_properties hp2 ON hp1.user_id = hp2.session_id
    WHERE hp1.user_id NOT REGEXP '^[0-9]+$'
      AND hp1.user_id IS NOT NULL
      AND hp1.user_id != ''
      AND hp2.user_id REGEXP '^[0-9]+$'
    GROUP BY hp1.user_id
) sub
GROUP BY cnt
ORDER BY cnt;
-- 결과: 1:1 매핑 43,791건 / 1:N 매핑 존재 → 복구 시 중복 발생 확인


-- 6. 숫자형 user_id 기준 session_id 중복 규모 및 비율 확인

-- 6-1. 전체 session_id 중 중복이 차지하는 비율
SELECT
    COUNT(DISTINCT session_id)                                      AS total_sessions,
    SUM(CASE WHEN cnt > 1 THEN 1 ELSE 0 END)                      AS dup_sessions,
    ROUND(SUM(CASE WHEN cnt > 1 THEN 1 ELSE 0 END)
        / COUNT(DISTINCT session_id) * 100, 2)                     AS dup_pct,
    SUM(CASE WHEN cnt = 1 THEN 1 ELSE 0 END)                      AS unique_sessions,
    ROUND(SUM(CASE WHEN cnt = 1 THEN 1 ELSE 0 END)
        / COUNT(DISTINCT session_id) * 100, 2)                     AS unique_pct
FROM (
    SELECT session_id, COUNT(*) AS cnt
    FROM hackle_properties
    WHERE user_id REGEXP '^[0-9]+$'
    GROUP BY session_id
) sub;
-- 결과: 중복 session 82,032건(35.12%) 확인


-- 6-2. 중복 횟수별 분포 (몇 개 중복이 얼마나 되는지)
SELECT
    cnt                  AS dup_count,
    COUNT(*) AS session_cnt,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct
FROM (
    SELECT session_id, COUNT(*) AS cnt
    FROM hackle_properties
    WHERE user_id REGEXP '^[0-9]+$'
    GROUP BY session_id
    HAVING COUNT(*) > 1
) sub
GROUP BY cnt
ORDER BY cnt;
-- 결과: 2중복 79.56%, 3중복 18.52% 등 분포 확인
--      80% 가량이 2중복인 것으로 보아, 쌍으로 발생하는 구조적 문제라고 판단됨


-- 7. 중복 session_id의 원인 패턴 분류 및 비율 확인

-- 7-1. 중복 session_id의 원인 유형 분류
SELECT
    dup_type,
    COUNT(*)                                          AS session_cnt,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct
FROM (
    SELECT
        session_id,
        CASE
            WHEN COUNT(DISTINCT versionname) > 1
             AND COUNT(DISTINCT user_id) = 1
                THEN 'versionname 차이만 존재'

            WHEN COUNT(DISTINCT user_id) > 1
             AND SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) > 0
                THEN 'NULL user_id 혼재'

            WHEN COUNT(DISTINCT user_id) > 1
             AND SUM(CASE WHEN user_id NOT REGEXP '^[0-9]+$'
                           AND user_id IS NOT NULL
                           AND user_id != ''
                          THEN 1 ELSE 0 END) > 0
                THEN '문자열 user_id 혼재'

            ELSE '기타 복합 중복'
        END AS dup_type
    FROM hackle_properties
    GROUP BY session_id
    HAVING COUNT(*) > 1
) classified
GROUP BY dup_type
ORDER BY session_cnt DESC;
-- 결과: 3가지 패턴별 건수 및 비율 확인
--      문자열 혼재 89,332건(45.5%) / 복합 중복 64,626건(32.9%) / versionname 차이만 존재 42,366건(21.6%) 


-- 7-2. 패턴별 핵심 수치 요약
SELECT
    SUM(CASE WHEN vname_diff = 1 AND user_diff = 0 THEN 1 ELSE 0 END) AS only_versionname_diff,
    SUM(CASE WHEN null_mixed = 1 THEN 1 ELSE 0 END)                   AS null_user_mixed,
    SUM(CASE WHEN str_mixed = 1 THEN 1 ELSE 0 END)                    AS string_user_mixed,
    COUNT(*)                                                           AS total_dup_sessions
FROM (
    SELECT
        session_id,
        CASE WHEN COUNT(DISTINCT versionname) > 1 THEN 1 ELSE 0 END AS vname_diff,
        CASE WHEN COUNT(DISTINCT user_id) > 1 THEN 1 ELSE 0 END     AS user_diff,
        CASE WHEN SUM(user_id IS NULL) > 0 THEN 1 ELSE 0 END        AS null_mixed,
        CASE WHEN SUM(user_id NOT REGEXP '^[0-9]+$'
                      AND user_id IS NOT NULL
                      AND user_id != '') > 0
             THEN 1 ELSE 0 END                                        AS str_mixed
    FROM hackle_properties
    GROUP BY session_id
    HAVING COUNT(*) > 1
) sub;
-- 결과: 3가지 원인이 각각 몇 건인지 한 행으로 요약


-- 8. hackle_properties_clean 생성 (숫자형 user_id만 유지)
DROP TABLE IF EXISTS hackle_properties_clean;

CREATE TABLE hackle_properties_clean AS
SELECT *
FROM hackle_properties
WHERE user_id REGEXP '^[0-9]+$'
  AND user_id IS NOT NULL
  AND user_id != '';

SELECT
    COUNT(*)                    AS total,
    COUNT(DISTINCT user_id)     AS unique_users,
    COUNT(DISTINCT session_id)  AS unique_sessions
FROM hackle_properties_clean;
-- 결과: 334,091건


-- ============================================================
-- 문제 2 hackle_events.votes_count가 vote_received_count와 불일치
-- ============================================================

-- 1. 시계열 고정 여부 확인
-- 2회 이상 접속한 유저 중 votes_count가 한 번도 바뀌지 않은 유저 비율
SELECT
    COUNT(*)                                                           AS total_users,
    SUM(CASE WHEN distinct_votes = 1 THEN 1 ELSE 0 END)              AS fixed_users,
    ROUND(SUM(CASE WHEN distinct_votes = 1 THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 2)                                          AS fixed_pct,
    SUM(CASE WHEN distinct_votes > 1 THEN 1 ELSE 0 END)              AS changed_users,
    ROUND(SUM(CASE WHEN distinct_votes > 1 THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 2)                                          AS changed_pct
FROM (
    SELECT
        hp.user_id,
        COUNT(DISTINCT he.votes_count) AS distinct_votes
    FROM hackle_properties_clean hp
    JOIN hackle_events_clean he ON hp.session_id = he.session_id
    WHERE he.votes_count IS NOT NULL
    GROUP BY hp.user_id
    HAVING COUNT(DISTINCT DATE(he.event_datetime)) >= 2
) sub;
-- 결과: 2회 이상 접속한 유저 중 votes_count가 전혀 변하지 않은 유저 = 12.5%


-- 2. votes_count와 vote_received_count 간 배율 구간별 분포
SELECT
    ratio_group,
    COUNT(*)                                          AS user_cnt,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct
FROM (
    SELECT
        CASE
            WHEN ratio BETWEEN 0.5 AND 2  THEN '① 0.5~2배 (유사)'
            WHEN ratio BETWEEN 2   AND 10 THEN '② 2~10배'
            WHEN ratio BETWEEN 10  AND 100 THEN '③ 10~100배'
            WHEN ratio BETWEEN 100 AND 1000 THEN '④ 100~1000배'
            ELSE                               '⑤ 1000배 이상'
        END AS ratio_group
    FROM (
        SELECT
            h.user_id,
            ROUND(h.max_votes_count / NULLIF(vr.vote_received_count, 0), 2) AS ratio
        FROM hub_user_base_hackle h
        JOIN v_vote_receiver_stats vr ON h.user_id = vr.user_id
        WHERE vr.vote_received_count > 0
          AND h.max_votes_count IS NOT NULL
    ) sub
) grouped
GROUP BY ratio_group
ORDER BY ratio_group;
-- 결과: 유사 배율은 약 31% 수준


-- 3. 전체 hackle 유저 중 candidate_count = 0인 비율 확인
SELECT
    COUNT(*)                                                            AS total_users,
    SUM(CASE WHEN COALESCE(pc.candidate_cnt, 0) = 0 THEN 1 ELSE 0 END) AS zero_candidate_users,
    ROUND(SUM(CASE WHEN COALESCE(pc.candidate_cnt, 0) = 0 THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 2)                                            AS zero_pct,
    SUM(CASE WHEN COALESCE(pc.candidate_cnt, 0) > 0 THEN 1 ELSE 0 END)  AS has_candidate_users,
    ROUND(SUM(CASE WHEN COALESCE(pc.candidate_cnt, 0) > 0 THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 2)                                            AS has_candidate_pct
FROM hub_user_base_hackle h
LEFT JOIN (
    SELECT user_id, COUNT(*) AS candidate_cnt
    FROM polls_usercandidate
    GROUP BY user_id
) pc ON h.user_id = pc.user_id;
-- 결과: votes_count 높은 유저 중 candidate_count = 0이 2.3%


-- 4. votes_count vs vote_received_count 피어슨 상관계수 계산
SELECT
    ROUND(
        (AVG(h.max_votes_count * v.vote_received_count)
         - AVG(h.max_votes_count) * AVG(v.vote_received_count))
        / (STDDEV(h.max_votes_count) * STDDEV(v.vote_received_count))
    , 4) AS votes_corr
FROM hub_user_base_hackle h
JOIN v_vote_receiver_stats v ON h.user_id = v.user_id;
-- 결과: 0.2957 → 약한 상관관계 (0.3 미만 = 통상 "약함")


-- ============================================================
-- 문제 3 hackle_events.friend_count는 정합성 확인됨
-- ============================================================

-- 1. friend_count vs accepted_friend_count 피어슨 상관계수 계산
SELECT
    ROUND(
        (AVG(h.max_friend_count * f.accepted_friend_count)
         - AVG(h.max_friend_count) * AVG(f.accepted_friend_count))
        / (STDDEV(h.max_friend_count) * STDDEV(f.accepted_friend_count))
    , 4) AS friend_corr
FROM hub_user_base_hackle h
JOIN v_friend_stats f ON h.user_id = f.user_id;
-- 결과: 0.909 → 매우 강한 양의 상관관계
--       → 두 지표가 같은 개념을 측정하고 있음을 확인


-- 2. votes_count와 friend_count 상관계수 나란히 비교
SELECT
    ROUND(
        (AVG(h.max_friend_count * f.accepted_friend_count)
         - AVG(h.max_friend_count) * AVG(f.accepted_friend_count))
        / (STDDEV(h.max_friend_count) * STDDEV(f.accepted_friend_count))
    , 4) AS friend_corr,
    ROUND(
        (AVG(h.max_votes_count * v.vote_received_count)
         - AVG(h.max_votes_count) * AVG(v.vote_received_count))
        / (STDDEV(h.max_votes_count) * STDDEV(v.vote_received_count))
    , 4) AS votes_corr
FROM hub_user_base_hackle h
JOIN v_friend_stats f ON h.user_id = f.user_id
JOIN v_vote_receiver_stats v ON h.user_id = v.user_id;
-- 결과: friend_corr = 0.909 (매우 강함) / votes_corr = 0.2957 (약함)
--       → 같은 테이블 내 지표라도 신뢰도가 다름을 수치로 확인


# ---------------------------------------
# 영선 소셜허브 분석용 마스터 테이블 생성
# 기준: 공통 전처리 완료 후 생성된 clean 테이블 사용
# ---------------------------------------

# 1. 기준 유저 테이블 생성
CREATE TABLE ys_base_user_01 AS
SELECT
    id AS user_id,
    created_at AS user_created_at,
    gender,
    group_id,
    point AS current_point,
    ban_status,
    is_push_on,
    report_count,
    alarm_count,
    pending_chat,
    pending_votes,
    friend_count AS profile_friend_count,
    block_user_count AS profile_block_count,
    hide_user_count AS profile_hide_count
FROM accounts_user_clean;

# 기준 유저 테이블 row 수 확인
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_base_user_01;

# group_id 조인 누락 확인
SELECT COUNT(*) AS missing_group_count
FROM ys_base_user_01 u
LEFT JOIN accounts_group g
    ON u.group_id = g.id
WHERE g.id IS NULL;

# ---------------------------------------
# 2. 친구 네트워크 집계
# ---------------------------------------

CREATE TABLE ys_friend_features_01 AS
SELECT
    s.user_id,
    s.sent_request_count,
    s.received_request_count,
    s.total_request_count,
    s.accepted_sent_count,
    s.accepted_received_count,
    s.accepted_friend_count,
    s.pending_sent_count,
    s.pending_received_count,
    s.rejected_sent_count,
    s.rejected_received_count,
    ROUND(s.accepted_friend_count / NULLIF(s.total_request_count, 0), 4) AS friend_accept_rate
FROM (
    SELECT
        user_id,
        SUM(sent_request_count) AS sent_request_count,
        SUM(received_request_count) AS received_request_count,
        SUM(sent_request_count) + SUM(received_request_count) AS total_request_count,
        SUM(accepted_sent_count) AS accepted_sent_count,
        SUM(accepted_received_count) AS accepted_received_count,
        SUM(accepted_sent_count) + SUM(accepted_received_count) AS accepted_friend_count,
        SUM(pending_sent_count) AS pending_sent_count,
        SUM(pending_received_count) AS pending_received_count,
        SUM(rejected_sent_count) AS rejected_sent_count,
        SUM(rejected_received_count) AS rejected_received_count
    FROM (
        SELECT
            send_user_id AS user_id,
            COUNT(*) AS sent_request_count,
            0 AS received_request_count,
            SUM(CASE WHEN status = 'A' THEN 1 ELSE 0 END) AS accepted_sent_count,
            0 AS accepted_received_count,
            SUM(CASE WHEN status = 'P' THEN 1 ELSE 0 END) AS pending_sent_count,
            0 AS pending_received_count,
            SUM(CASE WHEN status = 'R' THEN 1 ELSE 0 END) AS rejected_sent_count,
            0 AS rejected_received_count
        FROM accounts_friendrequest_clean
        GROUP BY send_user_id

        UNION ALL

        SELECT
            receive_user_id AS user_id,
            0 AS sent_request_count,
            COUNT(*) AS received_request_count,
            0 AS accepted_sent_count,
            SUM(CASE WHEN status = 'A' THEN 1 ELSE 0 END) AS accepted_received_count,
            0 AS pending_sent_count,
            SUM(CASE WHEN status = 'P' THEN 1 ELSE 0 END) AS pending_received_count,
            0 AS rejected_sent_count,
            SUM(CASE WHEN status = 'R' THEN 1 ELSE 0 END) AS rejected_received_count
        FROM accounts_friendrequest_clean
        GROUP BY receive_user_id
    ) t
    GROUP BY user_id
) s;

#확인
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_friend_features_01;

#상위 유저 확인
SELECT *
FROM ys_friend_features_01
ORDER BY accepted_friend_count DESC
LIMIT 20;

# ---------------------------------------
# 3. 투표 반응 집계
# ---------------------------------------

CREATE TABLE ys_vote_features_01 AS
SELECT
    user_id,
    SUM(vote_given_count) AS vote_given_count,
    SUM(vote_received_count) AS vote_received_count,
    SUM(blocked_vote_count) AS blocked_vote_count,
    SUM(result_open_count) AS result_open_count,
    SUM(has_read_count) AS has_read_count
FROM (
    -- 내가 투표한 기록
    SELECT
        user_id,
        COUNT(*) AS vote_given_count,
        0 AS vote_received_count,
        SUM(CASE WHEN status = 'B' THEN 1 ELSE 0 END) AS blocked_vote_count,
        0 AS result_open_count,
        0 AS has_read_count
    FROM accounts_userquestionrecord
    GROUP BY user_id

    UNION ALL

    -- 내가 선택받은 기록
    SELECT
        chosen_user_id AS user_id,
        0 AS vote_given_count,
        COUNT(*) AS vote_received_count,
        SUM(CASE WHEN status = 'B' THEN 1 ELSE 0 END) AS blocked_vote_count,
        SUM(COALESCE(opened_times, 0)) AS result_open_count,
        SUM(CASE WHEN has_read = 1 THEN 1 ELSE 0 END) AS has_read_count
    FROM accounts_userquestionrecord
    WHERE chosen_user_id IS NOT NULL
    GROUP BY chosen_user_id
) v
GROUP BY user_id;

#확인
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_vote_features_01;

#상위 유저 확인
SELECT *
FROM ys_vote_features_01
ORDER BY vote_received_count DESC
LIMIT 20;

# ---------------------------------------
# 4. 후보 노출 집계
# ---------------------------------------

CREATE TABLE ys_candidate_features_01 AS
SELECT
    user_id,
    COUNT(*) AS candidate_count
FROM polls_usercandidate
GROUP BY user_id;

SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_candidate_features_01;

# ---------------------------------------
# 5. 포인트 집계
# ---------------------------------------

CREATE TABLE ys_point_features_01 AS
SELECT
    user_id,
    COUNT(*) AS point_history_count,

    SUM(CASE WHEN delta_point > 0 THEN delta_point ELSE 0 END) AS point_earned_total,
    SUM(CASE WHEN delta_point < 0 THEN ABS(delta_point) ELSE 0 END) AS point_used_total,

    SUM(CASE WHEN delta_point > 0 THEN 1 ELSE 0 END) AS point_earned_count,
    SUM(CASE WHEN delta_point < 0 THEN 1 ELSE 0 END) AS point_used_count,

    SUM(CASE WHEN user_question_record_id IS NOT NULL THEN 1 ELSE 0 END) AS vote_related_point_count,
    SUM(CASE WHEN user_question_record_id IS NULL THEN 1 ELSE 0 END) AS non_vote_point_count
FROM accounts_pointhistory_clean
GROUP BY user_id;

#확인
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_point_features_01;

#상위 유저 확인 
SELECT *
FROM ys_point_features_01
ORDER BY point_used_total DESC
LIMIT 20;

# ---------------------------------------
# 6. 결제 집계
# ---------------------------------------

CREATE TABLE ys_payment_features_01 AS
SELECT
    user_id,
    1 AS is_paid_user,
    COUNT(*) AS payment_count,
    MIN(created_at) AS first_payment_at,
    MAX(created_at) AS last_payment_at,
    COUNT(DISTINCT productId) AS product_type_count
FROM accounts_paymenthistory_clean
GROUP BY user_id;

#확인 
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_payment_features_01;

#결제 횟수 상위 확인 
SELECT *
FROM ys_payment_features_01
ORDER BY payment_count DESC
LIMIT 20;

# ---------------------------------------
# 7. 출석 집계
# ---------------------------------------

CREATE TABLE ys_attendance_features_01 AS
SELECT
    user_id,
    attendance_count
FROM accounts_attendance_clean;

#확인 
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_attendance_features_01;

#출석 상위 유저 확인
SELECT *
FROM ys_attendance_features_01
ORDER BY attendance_count DESC
LIMIT 20;

# ---------------------------------------
# 8. 소셜허브 분석용 마스터 테이블 생성
# 유저 1명당 1행
# ---------------------------------------

CREATE TABLE ys_socialhub_master_01 AS
SELECT
    b.user_id,
    b.user_created_at,
    b.gender,
    b.group_id,
    g.grade,
    g.class_num,
    g.school_id,
    b.current_point,
    b.ban_status,
    b.is_push_on,
    b.report_count,
    b.alarm_count,
    b.pending_chat,
    b.pending_votes,
    b.profile_friend_count,
    b.profile_block_count,
    b.profile_hide_count,

    COALESCE(f.sent_request_count, 0) AS sent_request_count,
    COALESCE(f.received_request_count, 0) AS received_request_count,
    COALESCE(f.total_request_count, 0) AS total_request_count,
    COALESCE(f.accepted_sent_count, 0) AS accepted_sent_count,
    COALESCE(f.accepted_received_count, 0) AS accepted_received_count,
    COALESCE(f.accepted_friend_count, 0) AS accepted_friend_count,
    COALESCE(f.pending_sent_count, 0) AS pending_sent_count,
    COALESCE(f.pending_received_count, 0) AS pending_received_count,
    COALESCE(f.rejected_sent_count, 0) AS rejected_sent_count,
    COALESCE(f.rejected_received_count, 0) AS rejected_received_count,
    COALESCE(f.friend_accept_rate, 0) AS friend_accept_rate,

    COALESCE(v.vote_given_count, 0) AS vote_given_count,
    COALESCE(v.vote_received_count, 0) AS vote_received_count,
    COALESCE(v.blocked_vote_count, 0) AS blocked_vote_count,
    COALESCE(v.result_open_count, 0) AS result_open_count,
    COALESCE(v.has_read_count, 0) AS has_read_count,

    COALESCE(c.candidate_count, 0) AS candidate_count,

    COALESCE(p.point_history_count, 0) AS point_history_count,
    COALESCE(p.point_earned_total, 0) AS point_earned_total,
    COALESCE(p.point_used_total, 0) AS point_used_total,
    COALESCE(p.point_earned_count, 0) AS point_earned_count,
    COALESCE(p.point_used_count, 0) AS point_used_count,
    COALESCE(p.vote_related_point_count, 0) AS vote_related_point_count,
    COALESCE(p.non_vote_point_count, 0) AS non_vote_point_count,

    CASE WHEN pay.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_paid_user,
    COALESCE(pay.payment_count, 0) AS payment_count,
    pay.first_payment_at,
    pay.last_payment_at,
    COALESCE(pay.product_type_count, 0) AS product_type_count,

    COALESCE(a.attendance_count, 0) AS attendance_count

FROM ys_base_user_01 b
LEFT JOIN accounts_group g
    ON b.group_id = g.id
LEFT JOIN ys_friend_features_01 f
    ON b.user_id = f.user_id
LEFT JOIN ys_vote_features_01 v
    ON b.user_id = v.user_id
LEFT JOIN ys_candidate_features_01 c
    ON b.user_id = c.user_id
LEFT JOIN ys_point_features_01 p
    ON b.user_id = p.user_id
LEFT JOIN ys_payment_features_01 pay
    ON b.user_id = pay.user_id
LEFT JOIN ys_attendance_features_01 a
    ON b.user_id = a.user_id;

#마스터 테이블 확인 
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_socialhub_master_01;


 ---------------------------------------
# 영선 소셜허브 분석용 마스터 테이블 생성
# 기준: 공통 전처리 완료 후 생성된 clean 테이블 사용
# ---------------------------------------

# 1. 기준 유저 테이블 생성
CREATE TABLE ys_base_user_01 AS
SELECT
    id AS user_id,
    created_at AS user_created_at,
    gender,
    group_id,
    point AS current_point,
    ban_status,
    is_push_on,
    report_count,
    alarm_count,
    pending_chat,
    pending_votes,
    friend_count AS profile_friend_count,
    block_user_count AS profile_block_count,
    hide_user_count AS profile_hide_count
FROM accounts_user_clean;

# 기준 유저 테이블 row 수 확인
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_base_user_01;

# group_id 조인 누락 확인
SELECT COUNT(*) AS missing_group_count
FROM ys_base_user_01 u
LEFT JOIN accounts_group g
    ON u.group_id = g.id
WHERE g.id IS NULL;

# ---------------------------------------
# 2. 친구 네트워크 집계
# ---------------------------------------

CREATE TABLE ys_friend_features_01 AS
SELECT
    s.user_id,
    s.sent_request_count,
    s.received_request_count,
    s.total_request_count,
    s.accepted_sent_count,
    s.accepted_received_count,
    s.accepted_friend_count,
    s.pending_sent_count,
    s.pending_received_count,
    s.rejected_sent_count,
    s.rejected_received_count,
    ROUND(s.accepted_friend_count / NULLIF(s.total_request_count, 0), 4) AS friend_accept_rate
FROM (
    SELECT
        user_id,
        SUM(sent_request_count) AS sent_request_count,
        SUM(received_request_count) AS received_request_count,
        SUM(sent_request_count) + SUM(received_request_count) AS total_request_count,
        SUM(accepted_sent_count) AS accepted_sent_count,
        SUM(accepted_received_count) AS accepted_received_count,
        SUM(accepted_sent_count) + SUM(accepted_received_count) AS accepted_friend_count,
        SUM(pending_sent_count) AS pending_sent_count,
        SUM(pending_received_count) AS pending_received_count,
        SUM(rejected_sent_count) AS rejected_sent_count,
        SUM(rejected_received_count) AS rejected_received_count
    FROM (
        SELECT
            send_user_id AS user_id,
            COUNT(*) AS sent_request_count,
            0 AS received_request_count,
            SUM(CASE WHEN status = 'A' THEN 1 ELSE 0 END) AS accepted_sent_count,
            0 AS accepted_received_count,
            SUM(CASE WHEN status = 'P' THEN 1 ELSE 0 END) AS pending_sent_count,
            0 AS pending_received_count,
            SUM(CASE WHEN status = 'R' THEN 1 ELSE 0 END) AS rejected_sent_count,
            0 AS rejected_received_count
        FROM accounts_friendrequest_clean
        GROUP BY send_user_id

        UNION ALL

        SELECT
            receive_user_id AS user_id,
            0 AS sent_request_count,
            COUNT(*) AS received_request_count,
            0 AS accepted_sent_count,
            SUM(CASE WHEN status = 'A' THEN 1 ELSE 0 END) AS accepted_received_count,
            0 AS pending_sent_count,
            SUM(CASE WHEN status = 'P' THEN 1 ELSE 0 END) AS pending_received_count,
            0 AS rejected_sent_count,
            SUM(CASE WHEN status = 'R' THEN 1 ELSE 0 END) AS rejected_received_count
        FROM accounts_friendrequest_clean
        GROUP BY receive_user_id
    ) t
    GROUP BY user_id
) s;

#확인
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_friend_features_01;

#상위 유저 확인
SELECT *
FROM ys_friend_features_01
ORDER BY accepted_friend_count DESC
LIMIT 20;

# ---------------------------------------
# 3. 투표 반응 집계
# ---------------------------------------

CREATE TABLE ys_vote_features_01 AS
SELECT
    user_id,
    SUM(vote_given_count) AS vote_given_count,
    SUM(vote_received_count) AS vote_received_count,
    SUM(blocked_vote_count) AS blocked_vote_count,
    SUM(result_open_count) AS result_open_count,
    SUM(has_read_count) AS has_read_count
FROM (
    -- 내가 투표한 기록
    SELECT
        user_id,
        COUNT(*) AS vote_given_count,
        0 AS vote_received_count,
        SUM(CASE WHEN status = 'B' THEN 1 ELSE 0 END) AS blocked_vote_count,
        0 AS result_open_count,
        0 AS has_read_count
    FROM accounts_userquestionrecord
    GROUP BY user_id

    UNION ALL

    -- 내가 선택받은 기록
    SELECT
        chosen_user_id AS user_id,
        0 AS vote_given_count,
        COUNT(*) AS vote_received_count,
        SUM(CASE WHEN status = 'B' THEN 1 ELSE 0 END) AS blocked_vote_count,
        SUM(COALESCE(opened_times, 0)) AS result_open_count,
        SUM(CASE WHEN has_read = 1 THEN 1 ELSE 0 END) AS has_read_count
    FROM accounts_userquestionrecord
    WHERE chosen_user_id IS NOT NULL
    GROUP BY chosen_user_id
) v
GROUP BY user_id;

#확인
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_vote_features_01;

#상위 유저 확인
SELECT *
FROM ys_vote_features_01
ORDER BY vote_received_count DESC
LIMIT 20;

# ---------------------------------------
# 4. 후보 노출 집계
# ---------------------------------------

CREATE TABLE ys_candidate_features_01 AS
SELECT
    user_id,
    COUNT(*) AS candidate_count
FROM polls_usercandidate
GROUP BY user_id;

SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_candidate_features_01;

# ---------------------------------------
# 5. 포인트 집계
# ---------------------------------------

CREATE TABLE ys_point_features_01 AS
SELECT
    user_id,
    COUNT(*) AS point_history_count,

    SUM(CASE WHEN delta_point > 0 THEN delta_point ELSE 0 END) AS point_earned_total,
    SUM(CASE WHEN delta_point < 0 THEN ABS(delta_point) ELSE 0 END) AS point_used_total,

    SUM(CASE WHEN delta_point > 0 THEN 1 ELSE 0 END) AS point_earned_count,
    SUM(CASE WHEN delta_point < 0 THEN 1 ELSE 0 END) AS point_used_count,

    SUM(CASE WHEN user_question_record_id IS NOT NULL THEN 1 ELSE 0 END) AS vote_related_point_count,
    SUM(CASE WHEN user_question_record_id IS NULL THEN 1 ELSE 0 END) AS non_vote_point_count
FROM accounts_pointhistory_clean
GROUP BY user_id;

#확인
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_point_features_01;

#상위 유저 확인 
SELECT *
FROM ys_point_features_01
ORDER BY point_used_total DESC
LIMIT 20;

# ---------------------------------------
# 6. 결제 집계
# ---------------------------------------

CREATE TABLE ys_payment_features_01 AS
SELECT
    user_id,
    1 AS is_paid_user,
    COUNT(*) AS payment_count,
    MIN(created_at) AS first_payment_at,
    MAX(created_at) AS last_payment_at,
    COUNT(DISTINCT productId) AS product_type_count
FROM accounts_paymenthistory_clean
GROUP BY user_id;

#확인 
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_payment_features_01;

#결제 횟수 상위 확인 
SELECT *
FROM ys_payment_features_01
ORDER BY payment_count DESC
LIMIT 20;

# ---------------------------------------
# 7. 출석 집계
# ---------------------------------------

CREATE TABLE ys_attendance_features_01 AS
SELECT
    user_id,
    attendance_count
FROM accounts_attendance_clean;

#확인 
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_attendance_features_01;

#출석 상위 유저 확인
SELECT *
FROM ys_attendance_features_01
ORDER BY attendance_count DESC
LIMIT 20;

# ---------------------------------------
# 8. 소셜허브 분석용 마스터 테이블 생성
# 유저 1명당 1행
# ---------------------------------------

CREATE TABLE ys_socialhub_master_01 AS
SELECT
    b.user_id,
    b.user_created_at,
    b.gender,
    b.group_id,
    g.grade,
    g.class_num,
    g.school_id,
    b.current_point,
    b.ban_status,
    b.is_push_on,
    b.report_count,
    b.alarm_count,
    b.pending_chat,
    b.pending_votes,
    b.profile_friend_count,
    b.profile_block_count,
    b.profile_hide_count,

    COALESCE(f.sent_request_count, 0) AS sent_request_count,
    COALESCE(f.received_request_count, 0) AS received_request_count,
    COALESCE(f.total_request_count, 0) AS total_request_count,
    COALESCE(f.accepted_sent_count, 0) AS accepted_sent_count,
    COALESCE(f.accepted_received_count, 0) AS accepted_received_count,
    COALESCE(f.accepted_friend_count, 0) AS accepted_friend_count,
    COALESCE(f.pending_sent_count, 0) AS pending_sent_count,
    COALESCE(f.pending_received_count, 0) AS pending_received_count,
    COALESCE(f.rejected_sent_count, 0) AS rejected_sent_count,
    COALESCE(f.rejected_received_count, 0) AS rejected_received_count,
    COALESCE(f.friend_accept_rate, 0) AS friend_accept_rate,

    COALESCE(v.vote_given_count, 0) AS vote_given_count,
    COALESCE(v.vote_received_count, 0) AS vote_received_count,
    COALESCE(v.blocked_vote_count, 0) AS blocked_vote_count,
    COALESCE(v.result_open_count, 0) AS result_open_count,
    COALESCE(v.has_read_count, 0) AS has_read_count,

    COALESCE(c.candidate_count, 0) AS candidate_count,

    COALESCE(p.point_history_count, 0) AS point_history_count,
    COALESCE(p.point_earned_total, 0) AS point_earned_total,
    COALESCE(p.point_used_total, 0) AS point_used_total,
    COALESCE(p.point_earned_count, 0) AS point_earned_count,
    COALESCE(p.point_used_count, 0) AS point_used_count,
    COALESCE(p.vote_related_point_count, 0) AS vote_related_point_count,
    COALESCE(p.non_vote_point_count, 0) AS non_vote_point_count,

    CASE WHEN pay.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_paid_user,
    COALESCE(pay.payment_count, 0) AS payment_count,
    pay.first_payment_at,
    pay.last_payment_at,
    COALESCE(pay.product_type_count, 0) AS product_type_count,

    COALESCE(a.attendance_count, 0) AS attendance_count

FROM ys_base_user_01 b
LEFT JOIN accounts_group g
    ON b.group_id = g.id
LEFT JOIN ys_friend_features_01 f
    ON b.user_id = f.user_id
LEFT JOIN ys_vote_features_01 v
    ON b.user_id = v.user_id
LEFT JOIN ys_candidate_features_01 c
    ON b.user_id = c.user_id
LEFT JOIN ys_point_features_01 p
    ON b.user_id = p.user_id
LEFT JOIN ys_payment_features_01 pay
    ON b.user_id = pay.user_id
LEFT JOIN ys_attendance_features_01 a
    ON b.user_id = a.user_id;

#마스터 테이블 확인 
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_socialhub_master_01;

# ---------------------------------------
# 9. 소셜허브 핵심 변수 분포 확인
# ---------------------------------------

SELECT
    COUNT(*) AS user_count,

    ROUND(AVG(accepted_friend_count), 2) AS avg_accepted_friend_count,
    MAX(accepted_friend_count) AS max_accepted_friend_count,

    ROUND(AVG(received_request_count), 2) AS avg_received_request_count,
    MAX(received_request_count) AS max_received_request_count,

    ROUND(AVG(vote_received_count), 2) AS avg_vote_received_count,
    MAX(vote_received_count) AS max_vote_received_count,

    ROUND(AVG(candidate_count), 2) AS avg_candidate_count,
    MAX(candidate_count) AS max_candidate_count,

    ROUND(AVG(result_open_count), 2) AS avg_result_open_count,
    MAX(result_open_count) AS max_result_open_count
FROM ys_socialhub_master_01;

# ---------------------------------------
# 10. 친구 네트워크 규모별 결제/포인트/활동성 비교
# ---------------------------------------

SELECT
    friend_group,
    COUNT(*) AS user_count,
    SUM(is_paid_user) AS paid_user_count,
    ROUND(SUM(is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,

    ROUND(AVG(payment_count), 2) AS avg_payment_count,
    ROUND(AVG(point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(point_used_count), 2) AS avg_point_used_count,
    ROUND(AVG(attendance_count), 2) AS avg_attendance_count,
    ROUND(AVG(vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(candidate_count), 2) AS avg_candidate_count,
    ROUND(AVG(result_open_count), 2) AS avg_result_open_count

FROM (
    SELECT
        *,
        CASE
            WHEN accepted_friend_count = 0 THEN '0명'
            WHEN accepted_friend_count BETWEEN 1 AND 5 THEN '1~5명'
            WHEN accepted_friend_count BETWEEN 6 AND 20 THEN '6~20명'
            ELSE '20명 초과'
        END AS friend_group,
        CASE
            WHEN accepted_friend_count = 0 THEN 1
            WHEN accepted_friend_count BETWEEN 1 AND 5 THEN 2
            WHEN accepted_friend_count BETWEEN 6 AND 20 THEN 3
            ELSE 4
        END AS group_order
    FROM ys_socialhub_master_01
) t

GROUP BY friend_group, group_order
ORDER BY group_order;

#결과로 알수 있는 점 :수락 친구 수가 많아질수록 결제율이 꾸준히 증가했다. 특히 친구가 없는 유저의 결제율은 0.86%였지만, 
#친구가 20명을 초과하는 유저의 결제율은 10.60%로 약 12배 이상 높았다. 이는 친구 네트워크 규모가 큰 유저일수록 서비스 내 결제 가치가 높을 가능성을 보여준다.

# ---------------------------------------
# 11. 받은 투표 수 구간별 결제/포인트/활동성 비교
# ---------------------------------------

SELECT
    vote_received_group,
    COUNT(*) AS user_count,
    SUM(is_paid_user) AS paid_user_count,
    ROUND(SUM(is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,

    ROUND(AVG(payment_count), 2) AS avg_payment_count,
    ROUND(AVG(point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(point_used_count), 2) AS avg_point_used_count,
    ROUND(AVG(attendance_count), 2) AS avg_attendance_count,
    ROUND(AVG(accepted_friend_count), 2) AS avg_accepted_friend_count,
    ROUND(AVG(candidate_count), 2) AS avg_candidate_count,
    ROUND(AVG(result_open_count), 2) AS avg_result_open_count

FROM (
    SELECT
        *,
        CASE
            WHEN vote_received_count = 0 THEN '0회'
            WHEN vote_received_count BETWEEN 1 AND 5 THEN '1~5회'
            WHEN vote_received_count BETWEEN 6 AND 20 THEN '6~20회'
            ELSE '20회 초과'
        END AS vote_received_group,
        CASE
            WHEN vote_received_count = 0 THEN 1
            WHEN vote_received_count BETWEEN 1 AND 5 THEN 2
            WHEN vote_received_count BETWEEN 6 AND 20 THEN 3
            ELSE 4
        END AS group_order
    FROM ys_socialhub_master_01
) t

GROUP BY vote_received_group, group_order
ORDER BY group_order;
#결제 전환과 더 직접적으로 연결되는 것은 받은 투표 수보다 친구 네트워크 규모로 보인다.
#반면 받은 투표 수는 결제율보다는 포인트 사용량, 후보 노출, 결과 열람 같은 서비스 몰입 행동과 더 관련이 있어 보인다.

# ---------------------------------------
# 12. 후보 노출 수 구간별 결제/포인트/활동성 비교
# ---------------------------------------

SELECT
    candidate_group,
    COUNT(*) AS user_count,
    SUM(is_paid_user) AS paid_user_count,
    ROUND(SUM(is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,

    ROUND(AVG(payment_count), 2) AS avg_payment_count,
    ROUND(AVG(point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(point_used_count), 2) AS avg_point_used_count,
    ROUND(AVG(attendance_count), 2) AS avg_attendance_count,
    ROUND(AVG(accepted_friend_count), 2) AS avg_accepted_friend_count,
    ROUND(AVG(vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(result_open_count), 2) AS avg_result_open_count

FROM (
    SELECT
        *,
        CASE
            WHEN candidate_count = 0 THEN '0회'
            WHEN candidate_count BETWEEN 1 AND 20 THEN '1~20회'
            WHEN candidate_count BETWEEN 21 AND 100 THEN '21~100회'
            ELSE '100회 초과'
        END AS candidate_group,
        CASE
            WHEN candidate_count = 0 THEN 1
            WHEN candidate_count BETWEEN 1 AND 20 THEN 2
            WHEN candidate_count BETWEEN 21 AND 100 THEN 3
            ELSE 4
        END AS group_order
    FROM ys_socialhub_master_01
) t

GROUP BY candidate_group, group_order
ORDER BY group_order;

# ---------------------------------------
# 13. 친구 수 + 후보 노출 기준 소셜허브 후보 비교
# ---------------------------------------

SELECT
    CASE
        WHEN accepted_friend_count > 20
         AND candidate_count > 100
        THEN '소셜허브 후보'
        ELSE '일반 유저'
    END AS user_type,

    COUNT(*) AS user_count,
    SUM(is_paid_user) AS paid_user_count,
    ROUND(SUM(is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,

    ROUND(AVG(payment_count), 2) AS avg_payment_count,
    ROUND(AVG(point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(point_used_count), 2) AS avg_point_used_count,
    ROUND(AVG(attendance_count), 2) AS avg_attendance_count,
    ROUND(AVG(accepted_friend_count), 2) AS avg_accepted_friend_count,
    ROUND(AVG(received_request_count), 2) AS avg_received_request_count,
    ROUND(AVG(vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(candidate_count), 2) AS avg_candidate_count,
    ROUND(AVG(result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_master_01

GROUP BY
    CASE
        WHEN accepted_friend_count > 20
         AND candidate_count > 100
        THEN '소셜허브 후보'
        ELSE '일반 유저'
    END;

 CREATE TABLE ys_socialhub_yeseo_score_01 AS
WITH chosen AS (
    SELECT
        chosen_user_id AS user_id,
        SUM(status = 'C') AS chosen_cnt
    FROM accounts_userquestionrecord
    GROUP BY chosen_user_id
),

base AS (
    SELECT
        m.user_id,

        COALESCE(m.accepted_friend_count, 0) AS accepted_friend_count,
        COALESCE(m.vote_received_count, 0) AS vote_received_count,
        COALESCE(c.chosen_cnt, 0) AS chosen_cnt

    FROM ys_socialhub_master_01 m
    LEFT JOIN chosen c
        ON m.user_id = c.user_id
),

log_base AS (
    SELECT
        *,

        LOG(1 + accepted_friend_count) AS log_friend_count,
        LOG(1 + vote_received_count) AS log_vote_received_count,
        LOG(1 + chosen_cnt) AS log_chosen_cnt

    FROM base
),

minmax AS (
    SELECT
        MIN(log_friend_count) AS min_friend,
        MAX(log_friend_count) AS max_friend,

        MIN(log_vote_received_count) AS min_vote_received,
        MAX(log_vote_received_count) AS max_vote_received,

        MIN(log_chosen_cnt) AS min_chosen,
        MAX(log_chosen_cnt) AS max_chosen

    FROM log_base
),

score AS (
    SELECT
        l.user_id,

        l.accepted_friend_count,
        l.vote_received_count,
        l.chosen_cnt,

        (l.log_friend_count - m.min_friend)
            / NULLIF(m.max_friend - m.min_friend, 0) AS norm_friend_count,

        (l.log_vote_received_count - m.min_vote_received)
            / NULLIF(m.max_vote_received - m.min_vote_received, 0) AS norm_vote_received_count,

        (l.log_chosen_cnt - m.min_chosen)
            / NULLIF(m.max_chosen - m.min_chosen, 0) AS norm_chosen_cnt

    FROM log_base l
    CROSS JOIN minmax m
)

SELECT
    *,

    (
        COALESCE(norm_friend_count, 0) * 1
        + COALESCE(norm_vote_received_count, 0) * 3
        + COALESCE(norm_chosen_cnt, 0) * 3
    ) AS socialhub_score

FROM score;

#점수 높은 유저 확인 

SELECT
    user_id,
    accepted_friend_count,
    vote_received_count,
    chosen_cnt,

    ROUND(norm_friend_count, 4) AS norm_friend_count,
    ROUND(norm_vote_received_count, 4) AS norm_vote_received_count,
    ROUND(norm_chosen_cnt, 4) AS norm_chosen_cnt,

    ROUND(socialhub_score, 4) AS socialhub_score

FROM ys_socialhub_yeseo_score_01
ORDER BY socialhub_score DESC
LIMIT 100;

#상위 10% 핵심 유저 표시하기

CREATE TABLE ys_socialhub_yeseo_rank_01 AS
WITH ranked AS (
    SELECT
        s.*,
        NTILE(100) OVER (ORDER BY socialhub_score DESC) AS score_percentile_group
    FROM ys_socialhub_yeseo_score_01 s
)

SELECT
    *,

    CASE
        WHEN score_percentile_group <= 10 THEN 1
        ELSE 0
    END AS is_core_user_top10

FROM ranked;

#핵심 유저 수 확인

SELECT
    COUNT(*) AS total_user_count,
    SUM(is_core_user_top10) AS core_user_count,
    ROUND(SUM(is_core_user_top10) * 100.0 / COUNT(*), 2) AS core_user_ratio_percent
FROM ys_socialhub_yeseo_rank_01;

#상위 10% 기준값 확인
SELECT
    MIN(socialhub_score) AS top10_cutoff_score,
    ROUND(MIN(socialhub_score), 4) AS top10_cutoff_score_round
FROM ys_socialhub_yeseo_rank_01
WHERE is_core_user_top10 = 1;

# 핵심 유저 안에 투표 지표가 있는지 확인 
SELECT
    COUNT(*) AS core_user_count,

    SUM(vote_received_count > 0) AS vote_received_user_count,
    ROUND(SUM(vote_received_count > 0) * 100.0 / COUNT(*), 2) AS vote_received_user_ratio_percent,

    SUM(chosen_cnt > 0) AS chosen_user_count,
    ROUND(SUM(chosen_cnt > 0) * 100.0 / COUNT(*), 2) AS chosen_user_ratio_percent,

    SUM(vote_received_count > 0 OR chosen_cnt > 0) AS vote_related_user_count,
    ROUND(SUM(vote_received_count > 0 OR chosen_cnt > 0) * 100.0 / COUNT(*), 2) AS vote_related_user_ratio_percent,

    SUM(vote_received_count = 0 AND chosen_cnt = 0) AS only_friend_based_user_count,
    ROUND(SUM(vote_received_count = 0 AND chosen_cnt = 0) * 100.0 / COUNT(*), 2) AS only_friend_based_user_ratio_percent

FROM ys_socialhub_yeseo_rank_01
WHERE is_core_user_top10 = 1;

# 핵심 유저 vs 그 외 유저 비교 

SELECT
    CASE
        WHEN r.is_core_user_top10 = 1 THEN '핵심 유저 상위 10%'
        ELSE '그 외 유저'
    END AS user_group,

    COUNT(*) AS user_count,

    ROUND(AVG(r.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(r.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(r.chosen_cnt), 2) AS avg_chosen_cnt,
    ROUND(AVG(r.socialhub_score), 4) AS avg_socialhub_score,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.payment_count), 2) AS avg_payment_count,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.point_used_count), 2) AS avg_point_used_count,
    ROUND(AVG(m.attendance_count), 2) AS avg_attendance_count,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_yeseo_rank_01 r
JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id

GROUP BY user_group;

# 점수 구간별로 보기 

SELECT
    CASE
        WHEN r.score_percentile_group <= 10 THEN '상위 10%'
        WHEN r.score_percentile_group <= 20 THEN '상위 11~20%'
        WHEN r.score_percentile_group <= 30 THEN '상위 21~30%'
        WHEN r.score_percentile_group <= 40 THEN '상위 31~40%'
        WHEN r.score_percentile_group <= 50 THEN '상위 41~50%'
        ELSE '하위 50%'
    END AS score_group,

    COUNT(*) AS user_count,

    ROUND(AVG(r.socialhub_score), 4) AS avg_socialhub_score,
    ROUND(AVG(r.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(r.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(r.chosen_cnt), 2) AS avg_chosen_cnt,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_yeseo_rank_01 r
JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id

GROUP BY score_group

ORDER BY
    CASE score_group
        WHEN '상위 10%' THEN 1
        WHEN '상위 11~20%' THEN 2
        WHEN '상위 21~30%' THEN 3
        WHEN '상위 31~40%' THEN 4
        WHEN '상위 41~50%' THEN 5
        WHEN '하위 50%' THEN 6
    END;
#0. status 분포 먼저 확인

SELECT
    status,
    COUNT(*) AS row_count
FROM accounts_userquestionrecord
GROUP BY status;

#1. I 기준 소셜허브 점수 테이블 만들기
USE final;

CREATE TABLE ys_socialhub_initial_score_01 AS
WITH initial_open AS (
    SELECT
        chosen_user_id AS user_id,
        SUM(status = 'I') AS initial_open_count
    FROM accounts_userquestionrecord
    GROUP BY chosen_user_id
),

base AS (
    SELECT
        m.user_id,

        COALESCE(m.accepted_friend_count, 0) AS accepted_friend_count,
        COALESCE(m.vote_received_count, 0) AS vote_received_count,
        COALESCE(i.initial_open_count, 0) AS initial_open_count

    FROM ys_socialhub_master_01 m
    LEFT JOIN initial_open i
        ON m.user_id = i.user_id
),

log_base AS (
    SELECT
        *,

        LOG(1 + accepted_friend_count) AS log_friend_count,
        LOG(1 + vote_received_count) AS log_vote_received_count,
        LOG(1 + initial_open_count) AS log_initial_open_count

    FROM base
),

minmax AS (
    SELECT
        MIN(log_friend_count) AS min_friend,
        MAX(log_friend_count) AS max_friend,

        MIN(log_vote_received_count) AS min_vote_received,
        MAX(log_vote_received_count) AS max_vote_received,

        MIN(log_initial_open_count) AS min_initial_open,
        MAX(log_initial_open_count) AS max_initial_open

    FROM log_base
),

score AS (
    SELECT
        l.user_id,

        l.accepted_friend_count,
        l.vote_received_count,
        l.initial_open_count,

        (l.log_friend_count - m.min_friend)
            / NULLIF(m.max_friend - m.min_friend, 0) AS norm_friend_count,

        (l.log_vote_received_count - m.min_vote_received)
            / NULLIF(m.max_vote_received - m.min_vote_received, 0) AS norm_vote_received_count,

        (l.log_initial_open_count - m.min_initial_open)
            / NULLIF(m.max_initial_open - m.min_initial_open, 0) AS norm_initial_open_count

    FROM log_base l
    CROSS JOIN minmax m
)

SELECT
    *,

    (
        COALESCE(norm_friend_count, 0) * 1
        + COALESCE(norm_vote_received_count, 0) * 3
        + COALESCE(norm_initial_open_count, 0) * 3
    ) AS socialhub_score

FROM score;

#2. 점수 높은 유저 확인

SELECT
    user_id,
    accepted_friend_count,
    vote_received_count,
    initial_open_count,

    ROUND(norm_friend_count, 4) AS norm_friend_count,
    ROUND(norm_vote_received_count, 4) AS norm_vote_received_count,
    ROUND(norm_initial_open_count, 4) AS norm_initial_open_count,

    ROUND(socialhub_score, 4) AS socialhub_score

FROM ys_socialhub_initial_score_01
ORDER BY socialhub_score DESC
LIMIT 100;

#3. 점수 상위 10% 핵심 유저 테이블 만들기

CREATE TABLE ys_socialhub_initial_rank_01 AS
WITH ranked AS (
    SELECT
        s.*,
        NTILE(100) OVER (ORDER BY socialhub_score DESC) AS score_percentile_group
    FROM ys_socialhub_initial_score_01 s
)

SELECT
    *,

    CASE
        WHEN score_percentile_group <= 10 THEN 1
        ELSE 0
    END AS is_core_user_top10

FROM ranked;

#4. 핵심 유저 수 확인

SELECT
    COUNT(*) AS total_user_count,
    SUM(is_core_user_top10) AS core_user_count,
    ROUND(SUM(is_core_user_top10) * 100.0 / COUNT(*), 2) AS core_user_ratio_percent
FROM ys_socialhub_initial_rank_01;

#5. 상위 10% 기준 점수 확인

SELECT
    MIN(socialhub_score) AS top10_cutoff_score,
    ROUND(MIN(socialhub_score), 4) AS top10_cutoff_score_round
FROM ys_socialhub_initial_rank_01
WHERE is_core_user_top10 = 1;

#6. 핵심 유저 안에 I 반응이 있는지 확인

SELECT
    COUNT(*) AS core_user_count,

    SUM(vote_received_count > 0) AS vote_received_user_count,
    ROUND(SUM(vote_received_count > 0) * 100.0 / COUNT(*), 2) AS vote_received_user_ratio_percent,

    SUM(initial_open_count > 0) AS initial_open_user_count,
    ROUND(SUM(initial_open_count > 0) * 100.0 / COUNT(*), 2) AS initial_open_user_ratio_percent,

    SUM(vote_received_count > 0 OR initial_open_count > 0) AS vote_related_user_count,
    ROUND(SUM(vote_received_count > 0 OR initial_open_count > 0) * 100.0 / COUNT(*), 2) AS vote_related_user_ratio_percent,

    SUM(vote_received_count = 0 AND initial_open_count = 0) AS only_friend_based_user_count,
    ROUND(SUM(vote_received_count = 0 AND initial_open_count = 0) * 100.0 / COUNT(*), 2) AS only_friend_based_user_ratio_percent

FROM ys_socialhub_initial_rank_01
WHERE is_core_user_top10 = 1;

#7. 핵심 유저 vs 그 외 유저 비교

SELECT
    CASE
        WHEN r.is_core_user_top10 = 1 THEN '핵심 유저 상위 10%'
        ELSE '그 외 유저'
    END AS user_group,

    COUNT(*) AS user_count,

    ROUND(AVG(r.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(r.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(r.initial_open_count), 2) AS avg_initial_open_count,
    ROUND(AVG(r.socialhub_score), 4) AS avg_socialhub_score,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.payment_count), 2) AS avg_payment_count,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.point_used_count), 2) AS avg_point_used_count,
    ROUND(AVG(m.attendance_count), 2) AS avg_attendance_count,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_initial_rank_01 r
JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id

GROUP BY user_group;

#8. 점수 구간별로 보기
SELECT
    CASE
        WHEN r.score_percentile_group <= 10 THEN '상위 10%'
        WHEN r.score_percentile_group <= 20 THEN '상위 11~20%'
        WHEN r.score_percentile_group <= 30 THEN '상위 21~30%'
        WHEN r.score_percentile_group <= 40 THEN '상위 31~40%'
        WHEN r.score_percentile_group <= 50 THEN '상위 41~50%'
        ELSE '하위 50%'
    END AS score_group,

    COUNT(*) AS user_count,

    ROUND(AVG(r.socialhub_score), 4) AS avg_socialhub_score,
    ROUND(AVG(r.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(r.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(r.initial_open_count), 2) AS avg_initial_open_count,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_initial_rank_01 r
JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id

GROUP BY score_group

ORDER BY
    CASE score_group
        WHEN '상위 10%' THEN 1
        WHEN '상위 11~20%' THEN 2
        WHEN '상위 21~30%' THEN 3
        WHEN '상위 31~40%' THEN 4
        WHEN '상위 41~50%' THEN 5
        WHEN '하위 50%' THEN 6
    END;
DROP TABLE IF EXISTS ys_socialhub_weight_compare_final_01;

CREATE TABLE ys_socialhub_weight_compare_final_01 AS
WITH score_base AS (
    SELECT
        user_id,

        accepted_friend_count,
        vote_received_count,
        initial_open_count,

        COALESCE(norm_friend_count, 0) AS norm_friend_count,
        COALESCE(norm_vote_received_count, 0) AS norm_vote_received_count,
        COALESCE(norm_initial_open_count, 0) AS norm_initial_open_count,

        -- 현재 기준: 친구 1, 받은 투표 3, 초성 열림 3
        (
            COALESCE(norm_friend_count, 0) * 1
            + COALESCE(norm_vote_received_count, 0) * 3
            + COALESCE(norm_initial_open_count, 0) * 3
        ) AS score_1_3_3,

        -- 비교 기준 1: 모두 동일 가중치
        (
            COALESCE(norm_friend_count, 0) * 1
            + COALESCE(norm_vote_received_count, 0) * 1
            + COALESCE(norm_initial_open_count, 0) * 1
        ) AS score_1_1_1,

        -- 비교 기준 2: 친구 수 중요도만 조금 올림
        (
            COALESCE(norm_friend_count, 0) * 2
            + COALESCE(norm_vote_received_count, 0) * 3
            + COALESCE(norm_initial_open_count, 0) * 3
        ) AS score_2_3_3

    FROM ys_socialhub_score_final_01
),

ranked AS (
    SELECT
        *,

        NTILE(100) OVER (ORDER BY score_1_3_3 DESC) AS pct_1_3_3,
        NTILE(100) OVER (ORDER BY score_1_1_1 DESC) AS pct_1_1_1,
        NTILE(100) OVER (ORDER BY score_2_3_3 DESC) AS pct_2_3_3

    FROM score_base
)

SELECT
    *,

    CASE WHEN pct_1_3_3 <= 10 THEN 1 ELSE 0 END AS is_top10_1_3_3,
    CASE WHEN pct_1_1_1 <= 10 THEN 1 ELSE 0 END AS is_top10_1_1_1,
    CASE WHEN pct_2_3_3 <= 10 THEN 1 ELSE 0 END AS is_top10_2_3_3

FROM ranked;

#2. 가중치별 핵심 유저가 얼마나 겹치는지 보기

SELECT
    SUM(is_top10_1_3_3) AS top10_1_3_3_count,
    SUM(is_top10_1_1_1) AS top10_1_1_1_count,
    SUM(is_top10_2_3_3) AS top10_2_3_3_count,

    SUM(CASE WHEN is_top10_1_3_3 = 1 AND is_top10_1_1_1 = 1 THEN 1 ELSE 0 END) AS overlap_1_3_3_and_1_1_1_count,
    ROUND(
        SUM(CASE WHEN is_top10_1_3_3 = 1 AND is_top10_1_1_1 = 1 THEN 1 ELSE 0 END)
        * 100.0 / SUM(is_top10_1_3_3)
    , 2) AS overlap_1_3_3_and_1_1_1_ratio_percent,

    SUM(CASE WHEN is_top10_1_3_3 = 1 AND is_top10_2_3_3 = 1 THEN 1 ELSE 0 END) AS overlap_1_3_3_and_2_3_3_count,
    ROUND(
        SUM(CASE WHEN is_top10_1_3_3 = 1 AND is_top10_2_3_3 = 1 THEN 1 ELSE 0 END)
        * 100.0 / SUM(is_top10_1_3_3)
    , 2) AS overlap_1_3_3_and_2_3_3_ratio_percent

FROM ys_socialhub_weight_compare_final_01;
|
#기준별 핵심유저 특징 비교
SELECT
    '1:3:3 현재 기준' AS weight_type,

    COUNT(*) AS core_user_count,

    ROUND(AVG(w.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(w.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(w.initial_open_count), 2) AS avg_initial_open_count,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_weight_compare_final_01 w
JOIN ys_socialhub_master_01 m
    ON w.user_id = m.user_id
WHERE w.is_top10_1_3_3 = 1

UNION ALL

SELECT
    '1:1:1 동일 가중치' AS weight_type,

    COUNT(*) AS core_user_count,

    ROUND(AVG(w.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(w.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(w.initial_open_count), 2) AS avg_initial_open_count,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_weight_compare_final_01 w
JOIN ys_socialhub_master_01 m
    ON w.user_id = m.user_id
WHERE w.is_top10_1_1_1 = 1

UNION ALL

SELECT
    '2:3:3 친구 가중치 상향' AS weight_type,

    COUNT(*) AS core_user_count,

    ROUND(AVG(w.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(w.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(w.initial_open_count), 2) AS avg_initial_open_count,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_weight_compare_final_01 w
JOIN ys_socialhub_master_01 m
    ON w.user_id = m.user_id
WHERE w.is_top10_2_3_3 = 1;


-- =========================================================
-- 핵심 유저 내부 유형별 특징 비교
-- =========================================================

SELECT
    CASE
        WHEN r.initial_open_count > 0 THEN '적극 반응형'
        WHEN r.vote_received_count > 0 THEN '투표 수신형'
        ELSE '네트워크형'
    END AS core_user_type,

    COUNT(*) AS user_count,

    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS user_ratio_percent,

    ROUND(AVG(r.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(r.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(r.initial_open_count), 2) AS avg_initial_open_count,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,

    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_rank_final_01 r
JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id

WHERE r.is_core_user_top10 = 1

GROUP BY core_user_type

ORDER BY
    CASE core_user_type
        WHEN '네트워크형' THEN 1
        WHEN '투표 수신형' THEN 2
        WHEN '적극 반응형' THEN 3
    END;

-- =========================================================
-- 영선_소셜허브_핵심유저_정의및중요도분석
--
-- 목적:
-- 친구 수, 받은 투표 수, 초성 열림 수를 기반으로
-- 소셜허브 점수를 계산하고,
-- 상위 10% 핵심 유저의 중요도와 유형을 분석한다.
--
-- 최종 계산 방식:
-- 원래 값 → Min-Max 정규화 → 1:3:3 가중치 적용
-- =========================================================

-- =========================================================
-- 1. 로그 변환 없는 최종 소셜허브 점수 테이블 생성
--
-- 최종 계산 방식:
-- 원래 값 → Min-Max 정규화 → 1:3:3 가중치 적용
--
-- 사용 지표:
-- accepted_friend_count = 친구 수
-- vote_received_count = 받은 투표 수
-- initial_open_count = 초성 열림 수, status = 'I'
-- =========================================================

CREATE TABLE ys_socialhub_score_final_01 AS
SELECT *
FROM (
    WITH initial_open AS (
        SELECT
            chosen_user_id AS user_id,
            SUM(status = 'I') AS initial_open_count
        FROM accounts_userquestionrecord
        GROUP BY chosen_user_id
    ),

    base AS (
        SELECT
            m.user_id,

            COALESCE(m.accepted_friend_count, 0) AS accepted_friend_count,
            COALESCE(m.vote_received_count, 0) AS vote_received_count,
            COALESCE(i.initial_open_count, 0) AS initial_open_count

        FROM ys_socialhub_master_01 m
        LEFT JOIN initial_open i
            ON m.user_id = i.user_id
    ),

    minmax AS (
        SELECT
            MIN(accepted_friend_count) AS min_friend,
            MAX(accepted_friend_count) AS max_friend,

            MIN(vote_received_count) AS min_vote_received,
            MAX(vote_received_count) AS max_vote_received,

            MIN(initial_open_count) AS min_initial_open,
            MAX(initial_open_count) AS max_initial_open
        FROM base
    ),

    score AS (
        SELECT
            b.user_id,

            b.accepted_friend_count,
            b.vote_received_count,
            b.initial_open_count,

            COALESCE(
                (b.accepted_friend_count - mm.min_friend)
                / NULLIF(mm.max_friend - mm.min_friend, 0),
                0
            ) AS norm_friend_count,

            COALESCE(
                (b.vote_received_count - mm.min_vote_received)
                / NULLIF(mm.max_vote_received - mm.min_vote_received, 0),
                0
            ) AS norm_vote_received_count,

            COALESCE(
                (b.initial_open_count - mm.min_initial_open)
                / NULLIF(mm.max_initial_open - mm.min_initial_open, 0),
                0
            ) AS norm_initial_open_count

        FROM base b
        CROSS JOIN minmax mm
    )

    SELECT
        *,

        (
            norm_friend_count * 1
            + norm_vote_received_count * 3
            + norm_initial_open_count * 3
        ) AS socialhub_score

    FROM score
) AS final_result;

-- =========================================================
-- 2. 점수 테이블 정상 생성 확인
-- row_count와 distinct_user_count가 같으면 정상
-- =========================================================

SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT user_id) AS distinct_user_count
FROM ys_socialhub_score_final_01;

-- =========================================================
-- 3. 소셜허브 점수 기준 상위 10% 핵심 유저 선정
-- =========================================================

CREATE TABLE ys_socialhub_rank_final_01 AS
SELECT *
FROM (
    WITH ranked AS (
        SELECT
            s.*,
            NTILE(100) OVER (ORDER BY socialhub_score DESC) AS score_percentile_group
        FROM ys_socialhub_score_final_01 s
    )

    SELECT
        *,

        CASE
            WHEN score_percentile_group <= 10 THEN 1
            ELSE 0
        END AS is_core_user_top10

    FROM ranked
) AS final_result;

-- =========================================================
-- 4. 핵심 유저 수 확인
-- =========================================================

SELECT
    COUNT(*) AS total_user_count,
    SUM(is_core_user_top10) AS core_user_count,
    ROUND(SUM(is_core_user_top10) * 100.0 / COUNT(*), 2) AS core_user_ratio_percent
FROM ys_socialhub_rank_final_01;

-- =========================================================
-- 5. 상위 10% 기준 점수 확인
-- =========================================================

SELECT
    MIN(socialhub_score) AS top10_cutoff_score,
    ROUND(MIN(socialhub_score), 4) AS top10_cutoff_score_round
FROM ys_socialhub_rank_final_01
WHERE is_core_user_top10 = 1;

-- =========================================================
-- 6. 핵심 유저 vs 그 외 유저 비교
-- =========================================================

SELECT
    CASE
        WHEN r.is_core_user_top10 = 1 THEN '핵심 유저 상위 10%'
        ELSE '그 외 유저'
    END AS user_group,

    COUNT(*) AS user_count,

    ROUND(AVG(r.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(r.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(r.initial_open_count), 2) AS avg_initial_open_count,
    ROUND(AVG(r.socialhub_score), 4) AS avg_socialhub_score,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.payment_count), 2) AS avg_payment_count,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.point_used_count), 2) AS avg_point_used_count,
    ROUND(AVG(m.attendance_count), 2) AS avg_attendance_count,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM ys_socialhub_rank_final_01 r
JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id

GROUP BY user_group;

-- =========================================================
-- 7. 핵심 유저가 전체 성과에서 차지하는 비중
-- =========================================================

SELECT
    CASE
        WHEN r.is_core_user_top10 = 1 THEN '핵심 유저 상위 10%'
        ELSE '그 외 유저'
    END AS user_group,

    COUNT(*) AS user_count,

    ROUND(COUNT(*) * 100.0 / MAX(t.total_user_count), 2) AS user_ratio_percent,

    SUM(m.is_paid_user) AS paid_user_count,
    ROUND(SUM(m.is_paid_user) * 100.0 / NULLIF(MAX(t.total_paid_user_count), 0), 2) AS paid_user_share_percent,

    SUM(m.payment_count) AS total_payment_count,
    ROUND(SUM(m.payment_count) * 100.0 / NULLIF(MAX(t.total_payment_count), 0), 2) AS payment_count_share_percent,

    ROUND(SUM(m.point_used_total), 2) AS total_point_used,
    ROUND(SUM(m.point_used_total) * 100.0 / NULLIF(MAX(t.total_point_used), 0), 2) AS point_used_share_percent,

    SUM(m.point_used_count) AS total_point_used_count,
    ROUND(SUM(m.point_used_count) * 100.0 / NULLIF(MAX(t.total_point_used_count), 0), 2) AS point_used_count_share_percent,

    SUM(m.result_open_count) AS total_result_open_count,
    ROUND(SUM(m.result_open_count) * 100.0 / NULLIF(MAX(t.total_result_open_count), 0), 2) AS result_open_share_percent,

    SUM(r.vote_received_count) AS total_vote_received_count,
    ROUND(SUM(r.vote_received_count) * 100.0 / NULLIF(MAX(t.total_vote_received_count), 0), 2) AS vote_received_share_percent,

    SUM(r.initial_open_count) AS total_initial_open_count,
    ROUND(SUM(r.initial_open_count) * 100.0 / NULLIF(MAX(t.total_initial_open_count), 0), 2) AS initial_open_share_percent

FROM ys_socialhub_rank_final_01 r
JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id
CROSS JOIN (
    SELECT
        COUNT(*) AS total_user_count,
        SUM(m2.is_paid_user) AS total_paid_user_count,
        SUM(m2.payment_count) AS total_payment_count,
        SUM(m2.point_used_total) AS total_point_used,
        SUM(m2.point_used_count) AS total_point_used_count,
        SUM(m2.result_open_count) AS total_result_open_count,
        SUM(r2.vote_received_count) AS total_vote_received_count,
        SUM(r2.initial_open_count) AS total_initial_open_count
    FROM ys_socialhub_rank_final_01 r2
    JOIN ys_socialhub_master_01 m2
        ON r2.user_id = m2.user_id
) t

GROUP BY user_group;

-- =========================================================
-- 8. 핵심 유저 내부 유형 분석
--
-- 1. 네트워크형:
--    받은 투표 수 = 0, 초성 열림 수 = 0
--
-- 2. 투표 수신형:
--    받은 투표 수 > 0, 초성 열림 수 = 0
--
-- 3. 적극 반응형:
--    초성 열림 수 > 0
-- =========================================================

SELECT
    CASE
        WHEN r.initial_open_count > 0 THEN '3. 적극 반응형'
        WHEN r.vote_received_count > 0 THEN '2. 투표 수신형'
        ELSE '1. 네트워크형'
    END AS core_user_type,

    COUNT(*) AS user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS user_ratio_percent,

    ROUND(AVG(r.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(r.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(r.initial_open_count), 2) AS avg_initial_open_count,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.payment_count), 2) AS avg_payment_count,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.point_used_count), 2) AS avg_point_used_count,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count,
    ROUND(AVG(m.attendance_count), 2) AS avg_attendance_count

FROM ys_socialhub_rank_final_01 r
JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id

WHERE r.is_core_user_top10 = 1

GROUP BY core_user_type

ORDER BY core_user_type;

-- =========================================================
-- 9. 소셜허브 점수 상위 기준별 유저 특성 비교
--
-- 상위 5%, 10%, 15%, 20% 구간별로 비교해서
-- 상위 10% 기준이 적절한지 확인한다.
-- =========================================================

SELECT
    top_group,

    COUNT(*) AS user_count,

    ROUND(AVG(r.socialhub_score), 4) AS avg_socialhub_score,

    ROUND(AVG(r.accepted_friend_count), 2) AS avg_friend_count,
    ROUND(AVG(r.vote_received_count), 2) AS avg_vote_received_count,
    ROUND(AVG(r.initial_open_count), 2) AS avg_initial_open_count,

    ROUND(SUM(m.is_paid_user) * 100.0 / COUNT(*), 2) AS paid_user_ratio_percent,
    ROUND(AVG(m.point_used_total), 2) AS avg_point_used_total,
    ROUND(AVG(m.result_open_count), 2) AS avg_result_open_count

FROM (
    SELECT
        *,
        '상위 5%' AS top_group
    FROM ys_socialhub_rank_final_01
    WHERE score_percentile_group <= 5

    UNION ALL

    SELECT
        *,
        '상위 10%' AS top_group
    FROM ys_socialhub_rank_final_01
    WHERE score_percentile_group <= 10

    UNION ALL

    SELECT
        *,
        '상위 15%' AS top_group
    FROM ys_socialhub_rank_final_01
    WHERE score_percentile_group <= 15

    UNION ALL

    SELECT
        *,
        '상위 20%' AS top_group
    FROM ys_socialhub_rank_final_01
    WHERE score_percentile_group <= 20
) r

JOIN ys_socialhub_master_01 m
    ON r.user_id = m.user_id

GROUP BY top_group

ORDER BY
    CASE top_group
        WHEN '상위 5%' THEN 1
        WHEN '상위 10%' THEN 2
        WHEN '상위 15%' THEN 3
        WHEN '상위 20%' THEN 4
    END;

-- =========================================================
-- 10. 가중치 안정성 확인용 테이블 생성
--
-- 현재 기준 1:3:3과
-- 비교 기준 1:1:1, 2:3:3을 비교한다.
-- =========================================================

CREATE TABLE ys_socialhub_weight_compare_final_01 AS
SELECT *
FROM (
    WITH score_base AS (
        SELECT
            user_id,

            accepted_friend_count,
            vote_received_count,
            initial_open_count,

            norm_friend_count,
            norm_vote_received_count,
            norm_initial_open_count,

            (
                norm_friend_count * 1
                + norm_vote_received_count * 3
                + norm_initial_open_count * 3
            ) AS score_1_3_3,

            (
                norm_friend_count * 1
                + norm_vote_received_count * 1
                + norm_initial_open_count * 1
            ) AS score_1_1_1,

            (
                norm_friend_count * 2
                + norm_vote_received_count * 3
                + norm_initial_open_count * 3
            ) AS score_2_3_3

        FROM ys_socialhub_score_final_01
    ),

    ranked AS (
        SELECT
            score_base.*,

            NTILE(100) OVER (ORDER BY score_1_3_3 DESC) AS pct_1_3_3,
            NTILE(100) OVER (ORDER BY score_1_1_1 DESC) AS pct_1_1_1,
            NTILE(100) OVER (ORDER BY score_2_3_3 DESC) AS pct_2_3_3

        FROM score_base
    )

    SELECT
        *,

        CASE WHEN pct_1_3_3 <= 10 THEN 1 ELSE 0 END AS is_top10_1_3_3,
        CASE WHEN pct_1_1_1 <= 10 THEN 1 ELSE 0 END AS is_top10_1_1_1,
        CASE WHEN pct_2_3_3 <= 10 THEN 1 ELSE 0 END AS is_top10_2_3_3

    FROM ranked
) AS final_result;

-- =========================================================
-- 11. 가중치 기준별 핵심 유저 겹침 확인
-- =========================================================

SELECT
    SUM(is_top10_1_3_3) AS top10_1_3_3_count,
    SUM(is_top10_1_1_1) AS top10_1_1_1_count,
    SUM(is_top10_2_3_3) AS top10_2_3_3_count,

    SUM(CASE WHEN is_top10_1_3_3 = 1 AND is_top10_1_1_1 = 1 THEN 1 ELSE 0 END) AS overlap_1_3_3_and_1_1_1_count,
    ROUND(
        SUM(CASE WHEN is_top10_1_3_3 = 1 AND is_top10_1_1_1 = 1 THEN 1 ELSE 0 END)
        * 100.0 / SUM(is_top10_1_3_3)
    , 2) AS overlap_1_3_3_and_1_1_1_ratio_percent,

    SUM(CASE WHEN is_top10_1_3_3 = 1 AND is_top10_2_3_3 = 1 THEN 1 ELSE 0 END) AS overlap_1_3_3_and_2_3_3_count,
    ROUND(
        SUM(CASE WHEN is_top10_1_3_3 = 1 AND is_top10_2_3_3 = 1 THEN 1 ELSE 0 END)
        * 100.0 / SUM(is_top10_1_3_3)
    , 2) AS overlap_1_3_3_and_2_3_3_ratio_percent

FROM ys_socialhub_weight_compare_final_01;