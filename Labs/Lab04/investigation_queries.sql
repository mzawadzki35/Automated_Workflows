-- Write and retain your diagnostic queries here. Use the notebook questions.
-- Enable enforcement when opening your own SQLite session:
PRAGMA foreign_keys = ON;

-- Q1. List requests with their number of attempts, grouped by outcome.
SELECT request_id,
       status,
       COUNT(*) AS attempts
FROM processing_attempts
GROUP BY request_id, status
ORDER BY request_id, status;

-- Q2. Starting from an NDVI artifact ID, find its successful producing attempt,
-- normalized request, each input role, original Lab 3 subset, scene, band and AOI.
-- The CTE picks the most recently produced NDVI artifact; to trace another one,
-- replace the SELECT in `target` with:  SELECT 'YOUR_ARTIFACT_ID'
WITH target(artifact_id) AS (
    SELECT o.artifact_id
    FROM processing_outputs o
    JOIN processing_attempts a USING (attempt_id)
    WHERE o.role = 'ndvi' AND a.status = 'succeeded'
    ORDER BY a.started_at DESC
    LIMIT 1
)
SELECT t.artifact_id           AS ndvi_artifact,
       p.attempt_id            AS producing_attempt,
       p.status                AS attempt_status,
       r.request_id,
       r.fingerprint,
       i.role                  AS input_role,
       i.artifact_id           AS input_artifact,
       pa.source_artifact_id   AS lab3_artifact,
       s.subset_id,
       s.aoi_key,
       s.aoi_json,
       s.recipe_version,
       asx.asset_key           AS band,
       asx.collection,
       asx.item_id,
       sc.acquired_at
FROM target t
JOIN processing_outputs o   ON o.artifact_id = t.artifact_id AND o.role = 'ndvi'
JOIN processing_attempts p  ON p.attempt_id = o.attempt_id AND p.status = 'succeeded'
JOIN processing_requests r  ON r.request_id = p.request_id
JOIN processing_inputs i    ON i.request_id = r.request_id
JOIN processing_artifacts pa ON pa.artifact_id = i.artifact_id
JOIN artifacts x            ON x.artifact_id = pa.source_artifact_id
JOIN subset_requests s      ON s.subset_id = x.subset_id
JOIN assets asx             ON asx.asset_id = s.asset_id
JOIN scenes sc              ON sc.collection = asx.collection AND sc.item_id = asx.item_id
ORDER BY i.role;

-- Q3. Find failed/interrupted attempts with stage and error; retain recovery rows.
-- The LEFT JOIN keeps the failed/interrupted row and adds any LATER attempt of the
-- same request that succeeded or was reused (the recovery). No recovery -> NULLs.
SELECT f.attempt_id        AS broken_attempt,
       f.request_id,
       f.status            AS broken_status,
       f.stage,
       f.error_code,
       f.error_message,
       f.finished_at,
       r.attempt_id        AS recovery_attempt,
       r.status            AS recovery_status,
       r.started_at        AS recovery_started
FROM processing_attempts f
LEFT JOIN processing_attempts r
       ON r.request_id = f.request_id
      AND r.started_at > f.started_at
      AND r.status IN ('succeeded', 'reused')
WHERE f.status IN ('failed', 'interrupted')
ORDER BY f.started_at, r.started_at;

-- Q4. Find succeeded attempts whose returned artifact has no available location.
-- Explain why SQL alone cannot prove current filesystem availability.
SELECT a.attempt_id,
       a.request_id,
       o.artifact_id,
       (SELECT group_concat(l.local_path || ' [' || l.status || ', checked ' || l.checked_at || ']', '; ')
          FROM processing_artifact_locations l
         WHERE l.artifact_id = o.artifact_id) AS known_locations
FROM processing_attempts a
JOIN processing_outputs o USING (attempt_id)
WHERE a.status = 'succeeded'
  AND NOT EXISTS (SELECT 1
                    FROM processing_artifact_locations l
                   WHERE l.artifact_id = o.artifact_id
                     AND l.status = 'available');
-- Why SQL alone is not enough: `status` is only the result of the LAST check
-- (see checked_at). The database cannot look at the disk, so a row marked
-- 'available' may be stale (file deleted or changed later), and a row marked
-- 'missing' may be stale too (file restored). Only Python (verified_location)
-- checks existence, size and SHA-256 at the moment of use. Also, the historical
-- 'succeeded' status of the producing attempt is never rewritten by this.

-- Q5. Find running attempts and inspect temp/final path, receipt and output links.
SELECT a.attempt_id,
       a.request_id,
       a.stage,
       a.started_at,
       a.temp_path,
       a.final_path,
       a.receipt_json IS NOT NULL AS has_receipt,
       (SELECT COUNT(*) FROM processing_outputs o
         WHERE o.attempt_id = a.attempt_id) AS output_links
FROM processing_attempts a
WHERE a.status = 'running'
ORDER BY a.started_at;
-- SQL shows the receipt and the absence of an output link, but whether the temp
-- or final file exists must be checked on disk, and whether the process is still
-- alive must be established outside the database before reconciling.

-- Q6. Compare original calibration metadata with the reviewed configuration.
SELECT r.request_id,
       i.role,
       json_extract(a.raster_json, '$.scale')   AS original_scale,
       json_extract(a.raster_json, '$.offset')  AS original_offset,
       json_extract(r.normalized_json, '$.settings.scaling') AS scaling_policy,
       json_extract(r.normalized_json, '$.settings.calibration.' || i.role || '.scale')  AS reviewed_scale,
       json_extract(r.normalized_json, '$.settings.calibration.' || i.role || '.offset') AS reviewed_offset,
       json_extract(r.normalized_json, '$.settings.calibration.' || i.role || '.evidence') AS evidence
FROM processing_requests r
JOIN processing_inputs i    ON i.request_id = r.request_id
JOIN processing_artifacts a ON a.artifact_id = i.artifact_id
ORDER BY r.created_at, i.role;
