"""Repaired request identity, input-pair validation and NDVI arithmetic."""
import math
import numpy as np
import processing_store as store

ROLES = ('red', 'nir')
POLICY = 'exact_environment_v1'


def _plain(value):
    """JSON-compatible copy; numbers (not bools) become floats so 1 == 1.0."""
    if isinstance(value, dict):
        return {str(k): _plain(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(v) for v in value]
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, (int, float, np.integer, np.floating)):
        return float(value)
    return str(value)


def make_request_spec(science, inputs, environment, runtime):
    """Return (normalized_spec, fingerprint). Runtime paths are excluded."""
    settings = {k: v for k, v in science.items() if k != 'inputs'}  # ids are in 'inputs' below
    spec = {
        'stage': science['stage'],
        'equivalence_policy': POLICY,
        'settings': _plain(settings),
        'inputs': [
            {'role': role,
             'artifact_id': inputs[role]['artifact_id'],
             'sha256': inputs[role]['sha256'],
             'size_bytes': inputs[role]['size_bytes'],
             'raster': inputs[role]['raster'],
             'lineage': inputs[role]['lineage']}
            for role in ROLES],
        'environment': environment,
    }
    spec = json_roundtrip(spec)
    return spec, store.digest(spec)


def json_roundtrip(value):
    import json
    return json.loads(store.canonical(value))


def _finite_number(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value))


def validate_pair(red, nir):
    """Raise ValueError if metadata cannot justify a red/NIR calculation."""
    for record, role in ((red, 'red'), (nir, 'nir')):
        if record['lineage']['asset_key'] != role:
            raise ValueError(f'Input in role {role} is band {record["lineage"]["asset_key"]!r}')
        meta = record['raster']
        if meta.get('asset_key', role) != role:
            raise ValueError(f'Raster metadata for {role} names another band')
        if not _finite_number(meta.get('scale')) or meta['scale'] <= 0:
            raise ValueError(f'{role}: scale must be finite and positive')
        if not _finite_number(meta.get('offset')):
            raise ValueError(f'{role}: offset must be finite')
        if len(meta.get('transform', ())) != 6 or not all(_finite_number(x) for x in meta['transform']):
            raise ValueError(f'{role}: transform must contain six finite numbers')
    for key in ('collection', 'item_id', 'aoi_key', 'recipe_version'):
        if red['lineage'][key] != nir['lineage'][key]:
            raise ValueError(f'Inputs differ in lineage {key}')
    if red['lineage'].get('aoi') != nir['lineage'].get('aoi'):
        raise ValueError('Inputs differ in AOI')
    for key in ('crs', 'shape', 'transform', 'dtype', 'recipe', 'nodata'):
        a, b = red['raster'].get(key), nir['raster'].get(key)
        if list(a) != list(b) if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)) else a != b:
            raise ValueError(f'Inputs differ in raster {key}: {a!r} vs {b!r}')


def calculate_ndvi(red, nir, red_meta, nir_meta, epsilon):
    """Return float32 NDVI; invalid pixels are NaN. Inputs are stored DN."""
    if red.shape != nir.shape:
        raise ValueError('Input shapes differ')
    r = red.astype('float64') * red_meta['scale'] + red_meta['offset']
    n = nir.astype('float64') * nir_meta['scale'] + nir_meta['offset']
    valid = np.ones(red.shape, dtype=bool)
    if red_meta.get('nodata') is not None:
        valid &= red != red_meta['nodata']
    if nir_meta.get('nodata') is not None:
        valid &= nir != nir_meta['nodata']
    denominator = n + r
    valid &= np.isfinite(denominator) & (np.abs(denominator) > epsilon)
    result = np.full(red.shape, np.nan, dtype='float64')
    result[valid] = (n[valid] - r[valid]) / denominator[valid]
    return result.astype('float32')
