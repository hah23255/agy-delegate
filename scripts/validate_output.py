"""Extract and validate an agy agent's final JSON output against a JSON schema.

Usage (CLI added in a later task):
    python3 validate_output.py LOG_FILE SCHEMA_FILE --out PARTIAL_JSON
Exit codes: 0 valid, 1 invalid, 2 partial salvaged, 3 nothing extractable.
"""

import json
import re


def _repair(s):
    """Mechanical repair only: strip code fences, remove trailing commas."""
    s = s.strip()
    s = re.sub(r",\s*([}\]])", r"\1", s)
    return s


def _try_parse(s):
    try:
        return json.loads(_repair(s))
    except (json.JSONDecodeError, ValueError):
        return None


def extract_json(text):
    """Return the LAST parseable JSON value in text, else None."""
    # Preference 1: fenced ``` blocks, last first.
    fences = re.findall(r"```(?:json)?\s*\n(.*?)```", text, re.S)
    for block in reversed(fences):
        parsed = _try_parse(block)
        if parsed is not None:
            return parsed
    # Preference 2: bare values. Scan a consistently repaired copy so parse
    # spans and indices live in the same string (repairing per-slice desyncs
    # raw_decode's end offset from the original text).
    scan_text = _repair(text)
    decoder = json.JSONDecoder()
    last = None
    last_end = 0
    for i, ch in enumerate(scan_text):
        if ch not in "{[" or i < last_end:
            continue
        try:
            parsed, end = decoder.raw_decode(scan_text[i:])
            last = parsed
            last_end = i + end
        except (json.JSONDecodeError, ValueError):
            continue
    return last
