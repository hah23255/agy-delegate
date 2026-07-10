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


_TYPE_MAP = {
    "string": str,
    "integer": int,
    "number": (int, float),
    "boolean": bool,
    "array": list,
    "object": dict,
}


def _type_ok(value, prop_schema):
    expected = prop_schema.get("type")
    if expected is None:
        return True
    py = _TYPE_MAP.get(expected)
    if py is None:
        return True
    if expected == "integer" and isinstance(value, bool):
        return False
    if expected in ("number", "integer") and isinstance(value, bool):
        return False
    return isinstance(value, py)


def salvage(data, schema):
    """Field-by-field check. Returns (partial, missing, invalid)."""
    partial, missing, invalid = {}, [], []
    props = schema.get("properties", {})
    required = schema.get("required", [])
    for key, prop_schema in props.items():
        if key not in data:
            if key in required:
                missing.append(key)
            continue
        if _type_ok(data[key], prop_schema):
            partial[key] = data[key]
        else:
            invalid.append(key)
    return partial, missing, invalid


def main(argv):
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("log_file")
    ap.add_argument("schema_file")
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)

    with open(args.log_file) as f:
        text = f.read()
    with open(args.schema_file) as f:
        schema = json.load(f)

    data = extract_json(text)
    if data is None or not isinstance(data, dict):
        return 3

    partial, missing, invalid = salvage(data, schema)
    if args.out:
        with open(args.out, "w") as f:
            json.dump(
                {**partial, "_missing": missing, "_invalid": invalid}, f, indent=2
            )

    if not missing and not invalid:
        return 0
    if partial:
        return 2
    return 1


if __name__ == "__main__":
    import sys as _sys

    _sys.exit(main(_sys.argv[1:]))
