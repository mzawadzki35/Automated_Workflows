-- Lab 03 diagnostic queries for the five new tables.
-- Run each query against the right database:
--   main archive:  state/catalogue.sqlite
--   Case A:        cases/network/state/catalogue.sqlite
--   Case B:        cases/missing/state/catalogue.sqlite  (optional: cases/corrupt/..., cases/interrupted/...)
-- In DB Browser, run PRAGMA foreign_keys = ON; before testing any INSERT/UPDATE.

-------------------------------------------------------------------------------
-- 0. Worked example (supplied): attempt -> run -> request -> source band
-------------------------------------------------------------------------------
SELECT r.run_id,r.command,a.item_id,a.asset_key,s.aoi_key,d.status,d.stage,
       d.network_bytes,d.http_status,d.error_code,d.error_message
FROM download_attempts d JOIN runs r ON r.run_id=d.run_id
JOIN subset_requests s ON s.subset_id=d.subset_id
JOIN assets a ON a.asset_id=s.asset_id
ORDER BY d.started_at,d.attempt_id;

-------------------------------------------------------------------------------
-- 1. Saved paths, hashes, location state, and HTTP bytes vs. file size
--    HTTP bytes come from a correlated subquery over succeeded attempts, so
--    the one-to-many artifact_locations join cannot duplicate attempt rows.
-------------------------------------------------------------------------------
SELECT a.asset_key, s.aoi_key, f.artifact_id, f.sha256, f.size_bytes,
       l.local_path, l.status AS location_status, l.checked_at,
       (SELECT SUM(d.network_bytes) FROM download_attempts d
         WHERE d.subset_id = s.subset_id AND d.status = 'succeeded') AS http_bytes
FROM subset_requests s
JOIN assets a ON a.asset_id = s.asset_id
JOIN artifacts f ON f.artifact_id = s.latest_artifact_id
JOIN artifact_locations l ON l.artifact_id = f.artifact_id
ORDER BY a.asset_key, l.checked_at DESC;

-------------------------------------------------------------------------------
-- Case A: one band succeeded, then the connection failed  (cases/network)
-------------------------------------------------------------------------------

-- A1. Failed run, failed band, failure stage and bytes received.
SELECT r.run_id, r.command, r.status AS run_status, r.error AS run_error,
       a.asset_key, d.attempt_id, d.status AS attempt_status, d.stage,
       d.network_bytes, d.http_status, d.error_code, d.error_message
FROM download_attempts d
JOIN runs r ON r.run_id = d.run_id
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
WHERE d.status = 'failed'
ORDER BY d.started_at, d.attempt_id;

-- A2. Which band has an artifact and which has none (LEFT JOINs keep the empty one).
SELECT a.asset_key, s.status AS request_status, s.latest_artifact_id,
       f.size_bytes, l.local_path, l.status AS location_status
FROM subset_requests s
JOIN assets a ON a.asset_id = s.asset_id
LEFT JOIN artifacts f ON f.artifact_id = s.latest_artifact_id
LEFT JOIN artifact_locations l ON l.artifact_id = f.artifact_id
ORDER BY a.asset_key;

-- A3. Why an INNER JOIN to artifacts can hide the failed attempt.
--     Query 1 lists every attempt; query 2 joins artifacts with INNER JOIN and
--     silently loses attempts whose artifact_id is NULL (the failed band).
SELECT a.asset_key, d.attempt_id, d.status, d.stage, d.artifact_id
FROM download_attempts d
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
ORDER BY d.started_at;

SELECT a.asset_key, d.attempt_id, d.status, d.stage, f.artifact_id
FROM download_attempts d
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
JOIN artifacts f ON f.artifact_id = d.artifact_id
ORDER BY d.started_at;

-- A4. Discovery watermark vs. stored bands: the watermark says nothing about
--     whether a band file was stored; subset_requests/artifacts do.
SELECT st.stream_key, st.watermark FROM streams st;

SELECT a.asset_key, s.status, s.latest_artifact_id IS NOT NULL AS has_artifact
FROM subset_requests s JOIN assets a ON a.asset_id = s.asset_id;

-- A5. Before/after table (run it before and after recovery):
--     run, band, attempt status, stage and artifact identity, in time order.
SELECT r.run_id, r.command, r.status AS run_status, a.asset_key,
       d.status AS attempt_status, d.stage, d.error_code, d.artifact_id, d.started_at
FROM download_attempts d
JOIN runs r ON r.run_id = d.run_id
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
ORDER BY d.started_at, d.attempt_id;

-------------------------------------------------------------------------------
-- Case B: recorded success, missing/corrupt file  (cases/missing, cases/corrupt)
-------------------------------------------------------------------------------

-- B1. Historical successful acquisitions (the bytes that existed once).
SELECT a.asset_key, d.attempt_id, d.status, d.stage, d.network_bytes,
       d.artifact_id, d.started_at, d.finished_at
FROM download_attempts d
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
WHERE d.status = 'succeeded'
ORDER BY d.started_at;

-- B2. Later operation that detected the loss (FILE_MISSING / FILE_CORRUPT).
SELECT a.asset_key, d.attempt_id, d.run_id, d.status, d.stage,
       d.error_code, d.error_message, d.artifact_id, d.started_at
FROM download_attempts d
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
WHERE d.error_code IN ('FILE_MISSING','FILE_CORRUPT','FILE_INVALID')
ORDER BY d.started_at;

-- B3. Current availability (artifact_locations) vs. recorded bytes (artifacts).
SELECT a.asset_key, s.status AS request_status,
       f.artifact_id, f.sha256, f.size_bytes,
       l.local_path, l.status AS location_status, l.checked_at
FROM subset_requests s
JOIN assets a ON a.asset_id = s.asset_id
JOIN artifacts f ON f.artifact_id = s.latest_artifact_id
LEFT JOIN artifact_locations l ON l.artifact_id = f.artifact_id
ORDER BY a.asset_key;

-- B4. Full history per band: success first, failed verification later,
--     then (after recovery) a new successful attempt for the same artifact.
SELECT a.asset_key, d.started_at, d.status, d.stage, d.error_code, d.artifact_id
FROM download_attempts d
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
ORDER BY a.asset_key, d.started_at, d.attempt_id;

-- B5. After recovery: which attempt first registered each artifact.
SELECT a.asset_key, f.artifact_id, f.created_by_attempt_id, f.created_at,
       (SELECT COUNT(*) FROM download_attempts d
         WHERE d.artifact_id = f.artifact_id AND d.status = 'succeeded') AS succeeded_attempts
FROM artifacts f
JOIN subset_requests s ON s.subset_id = f.subset_id
JOIN assets a ON a.asset_id = s.asset_id
ORDER BY a.asset_key;

-------------------------------------------------------------------------------
-- AOI identity: one source band, separate requests for two AOIs
--   (run after: acquire --config config/alternate_aoi.json)
-------------------------------------------------------------------------------

-- I1. Source band -> its requests -> the output each request points to.
SELECT a.asset_id, a.asset_key, s.subset_id, s.aoi_key, s.aoi_json,
       s.status, s.latest_artifact_id, l.local_path
FROM subset_requests s
JOIN assets a ON a.asset_id = s.asset_id
LEFT JOIN artifact_locations l ON l.artifact_id = s.latest_artifact_id
ORDER BY a.asset_key, s.aoi_key;

-- I2. Assets that have more than one AOI request.
SELECT a.asset_id, a.asset_key, COUNT(*) AS requests
FROM subset_requests s JOIN assets a ON a.asset_id = s.asset_id
GROUP BY a.asset_id HAVING COUNT(*) > 1;

-- I3. Every latest artifact belongs to its own request (expect 1 on all rows).
SELECT s.subset_id, f.subset_id = s.subset_id AS artifact_belongs_to_request
FROM subset_requests s JOIN artifacts f ON f.artifact_id = s.latest_artifact_id;
