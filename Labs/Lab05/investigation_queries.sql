-- Lab 05 investigation queries (SQLite). Run with PRAGMA foreign_keys=ON.
-- Each entry: question, parameters, expected columns, empty-result interpretation, next check.

-- 1. Which expected members have never reached an application attempt?
-- Parameters: none (all batches). Add "AND m.batch_id = :batch_id" to restrict to one batch.
-- Columns: member_id, planned_request_id.
-- Join on planned_request_id: request_id stays NULL until the coordinator registers the request,
-- so it cannot identify work that has not started. The LEFT JOIN keeps members with no attempt.
-- Empty result: every expected member has at least one attempt row. Before the first run this
-- query lists the whole batch; after a run, an empty result is the expected outcome.
-- Next check: for a listed member, read its latest batch_observations row (blocked or ready?).
SELECT m.member_id, m.planned_request_id
FROM batch_members m
LEFT JOIN processing_attempts a ON a.request_id = m.planned_request_id
WHERE a.attempt_id IS NULL
ORDER BY m.member_id;

-- 2. Which request failed or stopped and later produced a verified result?
-- Parameters: :batch_id (the frozen batch identity).
-- Columns: member_id, request_id, earlier_attempt_id, earlier_status, earlier_error_code,
--          producing_attempt_id, artifact_id.
-- "Later" is decided by started_at, with attempt_id as a tie-breaker. The producing attempt must
-- have succeeded and linked an ndvi output. This query shows catalogue links only; verified bytes
-- come from the adapter's file checks, so confirm with a refresh/plan before claiming delivery.
-- Empty result: no request in this batch has recovered from a failed or interrupted attempt.
-- Counting attempts would overstate delivered work: one request yields one product however many
-- attempts it needed.
-- Next check: inspect the earlier attempt's error_code and the producing attempt's receipt.
SELECT m.member_id, m.planned_request_id AS request_id,
       bad.attempt_id AS earlier_attempt_id, bad.status AS earlier_status,
       bad.error_code AS earlier_error_code,
       good.attempt_id AS producing_attempt_id, o.artifact_id
FROM batch_members m
JOIN processing_attempts bad ON bad.request_id = m.planned_request_id
                            AND bad.status IN ('failed','interrupted')
JOIN processing_attempts good ON good.request_id = bad.request_id
                             AND good.status = 'succeeded'
                             AND (good.started_at > bad.started_at
                                  OR (good.started_at = bad.started_at AND good.attempt_id > bad.attempt_id))
JOIN processing_outputs o ON o.attempt_id = good.attempt_id AND o.role = 'ndvi'
WHERE m.batch_id = :batch_id
ORDER BY m.member_id, bad.started_at;

-- 3. Which succeeded products have no location recorded as available?
-- Parameters: none.
-- Columns: attempt_id, request_id, artifact_id, recorded_locations.
-- Empty result: every succeeded product has at least one location whose recorded status is
-- 'available'. That is a statement about the last catalogue check, not about the filesystem now:
-- a file may have been moved or corrupted since checked_at, and only a new check (refresh, or the
-- adapter's hashing) establishes present state. A row here means the catalogue lists no usable copy.
-- Next check: compare processing_artifact_locations.checked_at with the time of the question and
-- re-check the file bytes before trusting either answer.
SELECT a.attempt_id, a.request_id, o.artifact_id,
       (SELECT COUNT(*) FROM processing_artifact_locations l
         WHERE l.artifact_id = o.artifact_id) AS recorded_locations
FROM processing_attempts a
JOIN processing_outputs o ON o.attempt_id = a.attempt_id AND o.role = 'ndvi'
WHERE a.status = 'succeeded'
  AND NOT EXISTS (SELECT 1 FROM processing_artifact_locations l
                  WHERE l.artifact_id = o.artifact_id AND l.status = 'available')
ORDER BY a.request_id, a.attempt_id;

-- 4. Which members rely on old observations?
-- Parameters: :batch_id and :before (UTC text such as '2026-11-10T00:00:00Z').
-- Columns: member_id, state, observed_at, observation_id.
-- Uses each member's newest observation (largest observation_id, not the largest timestamp) and
-- compares its observed_at with :before. Both are ISO UTC strings, so text order is time order.
-- Members never observed have no row here; query 1 and the report's 'unobserved' label cover them.
-- Empty result: every member has an observation at or after :before.
-- Next check: run refresh for the listed members so their file evidence is current.
SELECT o.member_id, o.state, o.observed_at, o.observation_id
FROM batch_observations o
WHERE o.batch_id = :batch_id
  AND o.observation_id = (SELECT MAX(x.observation_id) FROM batch_observations x
                          WHERE x.batch_id = o.batch_id AND x.member_id = o.member_id)
  AND o.observed_at < :before
ORDER BY o.observed_at, o.member_id;

-- 5. (Section 6 diagnosis) Which member is blocked, on which input role, and had it started any work?
-- Parameters: none. Run it against the missing-input case catalogue (cases/missing).
-- Columns: observation_id, member_id, state, reason, missing_roles, missing_paths,
--          attempts_before_observation, observed_at.
-- Reads the append-only observations, so it still shows the blocked state after the input is
-- restored. attempts_before_observation counts attempts for the member's planned request that
-- started no later than the observation: 0 means the work never started (blocked is not failed).
-- Empty result: no member was ever observed as blocked in this catalogue.
-- Next check: confirm the listed path is really absent, restore it and run again.
SELECT o.observation_id, o.member_id, o.state, o.reason,
       json_extract(o.evidence_json,'$.context.missing_inputs') AS missing_roles,
       (SELECT group_concat(json_extract(j.value,'$.path'),'; ')
          FROM json_each(o.evidence_json,'$.location_checks') j
         WHERE json_extract(j.value,'$.status')='missing') AS missing_paths,
       (SELECT COUNT(*) FROM processing_attempts a
         WHERE a.request_id = m.planned_request_id AND a.started_at <= o.observed_at) AS attempts_before_observation,
       o.observed_at
FROM batch_observations o
JOIN batch_members m USING (batch_id, member_id)
WHERE o.state = 'blocked'
ORDER BY o.observation_id;
