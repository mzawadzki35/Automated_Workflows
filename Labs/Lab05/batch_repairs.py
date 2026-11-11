"""Repaired batch decisions. See SCHEMA_CONTRACT.md for the contracts."""

def classify_member(context):
    # 1. A running attempt makes every older conclusion unsafe until it is reconciled.
    if context['active_attempt']:
        return {'state':'unresolved','reason':'Execution is still recorded as active'}
    # 2. A verified output stays complete even if inputs moved or the budget is spent.
    if context['verified_result']:
        return {'state':'complete','reason':'Output verified'}
    # 3. Validation and missing-input evidence come before execution eligibility.
    if context['validation_error']:
        return {'state':'failed','reason':'Validation failed: '+str(context['validation_error'])}
    if context['missing_inputs']:
        return {'state':'blocked','reason':'Input unavailable: '+', '.join(context['missing_inputs'])}
    # 4. Budget counts non-reused attempts across the whole catalogue.
    if context['attempts_used'] >= context['max_attempts']:
        return {'state':'failed','reason':'Attempt budget exhausted'}
    # 5. An ordinary application failure needs investigation, not a blind retry.
    last = context['last_attempt']
    if last and last['status'] == 'failed':
        return {'state':'failed','reason':'Last attempt failed; investigate before retrying'}
    # 6. Fresh work, a reconciled interruption, or a missing output within budget.
    return {'state':'ready','reason':'Inputs verified and attempt budget remains'}

def verify_result(member,evidence):
    def text(key):
        value = evidence.get(key)
        return isinstance(value,str) and bool(value.strip())
    def size(key):
        value = evidence.get(key)
        return isinstance(value,int) and not isinstance(value,bool) and value > 0
    return bool(
        evidence.get('request_id') == member['request_id']
        and text('attempt_id') and text('artifact_id')
        and text('sha256') and evidence.get('sha256') == evidence.get('actual_sha256')
        and size('size_bytes') and evidence.get('size_bytes') == evidence.get('actual_size_bytes')
        and evidence.get('catalogue_link_verified') is True
        and evidence.get('grid_verified') is True
        and evidence.get('provenance_verified') is True)

def summarize_batch(rows):
    # Keep only the newest observation per member; repeated join rows cannot multiply members.
    latest = {}
    for row in rows:
        current = latest.get(row['member_id'])
        if current is None or row['observation_id'] > current['observation_id']:
            latest[row['member_id']] = row
    counts = {s:0 for s in ('ready','complete','blocked','unresolved','failed','unobserved')}
    members = {s:[] for s in counts}
    for member_id in sorted(latest):
        state = latest[member_id]['state'] or 'unobserved'
        counts[state] += 1
        members[state].append(member_id)
    return {'expected':len(latest),'counts':counts,'members':members}
