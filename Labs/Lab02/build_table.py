"""Builds the Lab 02 observation table from a real report (week_report.json).
Usage:  python build_table.py week_report.json [> table.md]
Only reads the report; the 'Observation' column is left for your own words.
"""
import json
import sys
from datetime import datetime, timezone

def load(path):
    raw = open(path, 'rb').read()
    for enc in ('utf-8-sig', 'utf-16'):  # utf-16: PowerShell 5 redirect
        try:
            return json.loads(raw.decode(enc))
        except (UnicodeError, json.JSONDecodeError):
            continue
    raise SystemExit('Cannot read the report as JSON (UTF-8 or UTF-16).')

def parse(text):
    return datetime.fromisoformat(text.replace('Z', '+00:00')).astimezone(timezone.utc)

def short(text):
    return parse(text).strftime('%Y-%m-%d %H:%M') if text else '-'

def main(path):
    report = load(path)
    runs = report['runs']
    lines = ['| Run time (UTC) | Outcome | Search interval | Sightings | Newly discovered scenes | Newest acquisition | Observation |',
             '|---|---|---|---|---|---|---|']
    for run in runs:
        outcome = run['status']
        if run.get('error'):
            outcome += f" ({run['error'].split(':')[0]})"
        interval = f"{short(run['search_start'])} → {short(run['search_until'])}"
        lines.append(f"| {short(run['started_at'])} | {outcome} | {interval} | {run['sightings']} | "
                     f"{run['new_scenes']} | {short(run['latest_acquired'])} | |")
    print('\n'.join(lines))
    print('\nGaps between run starts (hours):')
    for before, after in zip(runs, runs[1:]):
        gap = (parse(after['started_at']) - parse(before['started_at'])).total_seconds() / 3600
        print(f"  run {runs.index(before)+1} -> run {runs.index(after)+1}: {gap:.1f} h")
    print(f"\nRuns: {len(runs)} | unique scenes: {report['unique_scenes']} | "
          f"newest acquisition age: {report['latest_age_hours']} h | watermark: {report['watermark']}")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python build_table.py week_report.json')
    main(sys.argv[1])
