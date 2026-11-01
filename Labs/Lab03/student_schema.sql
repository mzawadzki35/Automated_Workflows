-- Lab 03 schema: five tables. Parents: scenes (Lab 02), runs (Lab 02 + 2 supplied columns).
-- Do not add BEGIN/COMMIT: the supplied initializer wraps this script in a transaction.

-- One row per band (and per metadata revision) of a scene.
CREATE TABLE assets (
    asset_id        TEXT PRIMARY KEY,
    collection      TEXT NOT NULL,
    item_id         TEXT NOT NULL,
    asset_key       TEXT NOT NULL CHECK (asset_key IN ('red','nir')),
    source_url      TEXT NOT NULL,
    metadata_json   TEXT NOT NULL CHECK (json_valid(metadata_json)),
    metadata_sha256 TEXT NOT NULL,
    created_at      TEXT NOT NULL,
    UNIQUE (collection, item_id, asset_key, metadata_sha256),
    FOREIGN KEY (collection, item_id) REFERENCES scenes (collection, item_id)
);

-- Current state of one request: which band, which AOI, which recipe.
CREATE TABLE subset_requests (
    subset_id          TEXT PRIMARY KEY,
    asset_id           TEXT NOT NULL REFERENCES assets (asset_id),
    aoi_key            TEXT NOT NULL,
    aoi_json           TEXT NOT NULL CHECK (json_valid(aoi_json)),
    recipe_version     TEXT NOT NULL,
    status             TEXT NOT NULL CHECK (status IN ('pending','ready','failed')),
    latest_artifact_id TEXT,
    updated_at         TEXT NOT NULL,
    UNIQUE (asset_id, aoi_key, recipe_version),
    CHECK (status <> 'ready' OR latest_artifact_id IS NOT NULL),
    -- Composite FK: the artifact must belong to THIS request.
    FOREIGN KEY (latest_artifact_id, subset_id) REFERENCES artifacts (artifact_id, subset_id)
);

-- History: every try, never overwritten.
CREATE TABLE download_attempts (
    attempt_id    TEXT PRIMARY KEY,
    subset_id     TEXT NOT NULL REFERENCES subset_requests (subset_id),
    run_id        TEXT NOT NULL REFERENCES runs (run_id),
    status        TEXT NOT NULL CHECK (status IN ('running','succeeded','failed','reused')),
    stage         TEXT NOT NULL,  -- free text: the supplied check script uses 'schema-check'
    started_at    TEXT NOT NULL,
    finished_at   TEXT,
    network_bytes INTEGER NOT NULL DEFAULT 0 CHECK (network_bytes >= 0),
    http_status   INTEGER,
    artifact_id   TEXT,
    error_code    TEXT,
    error_message TEXT,
    UNIQUE (attempt_id, subset_id),
    CHECK ((status = 'running') = (finished_at IS NULL)),
    CHECK (status NOT IN ('succeeded','reused') OR artifact_id IS NOT NULL),
    CHECK (status <> 'failed' OR error_code IS NOT NULL),
    FOREIGN KEY (artifact_id, subset_id) REFERENCES artifacts (artifact_id, subset_id)
);

-- Immutable identity of stored bytes (request + SHA-256).
CREATE TABLE artifacts (
    artifact_id           TEXT PRIMARY KEY,
    subset_id             TEXT NOT NULL REFERENCES subset_requests (subset_id),
    created_by_attempt_id TEXT NOT NULL,
    sha256                TEXT NOT NULL CHECK (length(sha256) = 64),
    size_bytes            INTEGER NOT NULL CHECK (size_bytes > 0),
    raster_json           TEXT NOT NULL CHECK (json_valid(raster_json)),
    created_at            TEXT NOT NULL,
    UNIQUE (artifact_id, subset_id),
    UNIQUE (subset_id, sha256),
    -- The creating attempt must belong to the same request.
    FOREIGN KEY (created_by_attempt_id, subset_id) REFERENCES download_attempts (attempt_id, subset_id)
);

-- Current availability of a file on disk (can change; artifact identity does not).
CREATE TABLE artifact_locations (
    location_id TEXT PRIMARY KEY,
    artifact_id TEXT NOT NULL REFERENCES artifacts (artifact_id),
    local_path  TEXT NOT NULL,
    status      TEXT NOT NULL CHECK (status IN ('available','missing','corrupt')),
    checked_at  TEXT NOT NULL,
    UNIQUE (local_path)
);

-- Indexes on child foreign keys (history queries by run and by request).
CREATE INDEX idx_attempts_run    ON download_attempts (run_id);
CREATE INDEX idx_attempts_subset ON download_attempts (subset_id);
CREATE INDEX idx_artifacts_subset ON artifacts (subset_id);
CREATE INDEX idx_locations_artifact ON artifact_locations (artifact_id);
