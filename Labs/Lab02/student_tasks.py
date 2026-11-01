"""Repair these three functions. The service and command parser are supplied."""
from datetime import datetime, timezone
from pathlib import Path
from lab01_service import utc_parse, utc_text

def resolve_paths(config, config_path):
    """Exercise 1: anchor relative paths to the configuration file's folder.
    Absolute paths stay absolute. Nothing is created, the cwd is not changed.
    """
    base = Path(config_path).resolve().parent
    # base / absolute_path returns the absolute path unchanged.
    return {key: (base / config[key]).resolve()
            for key in ('database', 'preview_directory', 'log_file')}

def choose_until(explicit_until=None, clock=None):
    """Exercise 2: explicit --until wins (normalized to UTC); otherwise capture
    the current aware UTC time exactly once. Timezone-free input is rejected.
    """
    if explicit_until is not None:
        return utc_text(utc_parse(explicit_until))  # utc_parse rejects naive timestamps
    now = clock() if clock is not None else datetime.now(timezone.utc)
    if now.tzinfo is None:
        raise ValueError('Clock must return a timezone-aware datetime')
    return utc_text(now.replace(microsecond=0))

def execute_job(job, logger):
    """Exercise 3: report the real outcome of the job."""
    try:
        return 0, job()
    except Exception as exc:
        logger.exception('Job failed')
        return 1, {'status': 'failed', 'error': f'{type(exc).__name__}: {exc}'}