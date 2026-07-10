import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from validate_output import extract_json, salvage


def test_extracts_fenced_json_block():
    log = 'I did the work.\n```json\n{"a": 1, "b": "x"}\n```\nDone.'
    assert extract_json(log) == {"a": 1, "b": "x"}


def test_extracts_last_of_multiple_blocks():
    log = '```json\n{"first": true}\n```\ntext\n```json\n{"second": true}\n```'
    assert extract_json(log) == {"second": True}


def test_extracts_bare_json_object():
    log = 'Result follows:\n{"name": "zfold", "count": 3}\n'
    assert extract_json(log) == {"name": "zfold", "count": 3}


def test_repairs_trailing_comma():
    log = '```json\n{"a": 1, "b": [1, 2,],}\n```'
    assert extract_json(log) == {"a": 1, "b": [1, 2]}


def test_returns_none_when_no_json():
    assert extract_json("no structured data here at all") is None


def test_ignores_broken_json_and_finds_earlier_valid():
    log = '{"good": 1}\nlater the model wrote {broken: nope'
    assert extract_json(log) == {"good": 1}


def test_extracts_bare_json_array():
    log = 'Result follows:\n[1, 2, {"a": 3}]\n'
    assert extract_json(log) == [1, 2, {"a": 3}]


def test_span_skip_correct_with_trailing_comma_repair():
    log = '[{"a":1,},{"b":2,},{"c":3,},{}]'
    assert extract_json(log) == [{"a": 1}, {"b": 2}, {"c": 3}, {}]


def test_string_literal_with_brace_comma_not_corrupted():
    log = '{"note": "tail chars: ,}", "count": 1}'
    assert extract_json(log) == {"note": "tail chars: ,}", "count": 1}


def test_fenced_string_literal_with_bracket_comma_not_corrupted():
    log = '```json\n{"cmd": "arr = [1, 2, ]", "n": 2}\n```'
    assert extract_json(log) == {"cmd": "arr = [1, 2, ]", "n": 2}


SCHEMA = {
    "type": "object",
    "properties": {
        "name": {"type": "string"},
        "count": {"type": "integer"},
        "tags": {"type": "array"},
    },
    "required": ["name", "count"],
}


def test_salvage_full_valid():
    partial, missing, invalid = salvage({"name": "x", "count": 2, "tags": []}, SCHEMA)
    assert partial == {"name": "x", "count": 2, "tags": []}
    assert missing == [] and invalid == []


def test_salvage_missing_required_field():
    partial, missing, invalid = salvage({"name": "x"}, SCHEMA)
    assert partial == {"name": "x"}
    assert missing == ["count"] and invalid == []


def test_salvage_wrong_type_field():
    partial, missing, invalid = salvage({"name": "x", "count": "two"}, SCHEMA)
    assert partial == {"name": "x"}
    assert missing == [] and invalid == ["count"]


def _run_cli(tmp_path, log_text, schema=SCHEMA):
    log = tmp_path / "agent.log"
    log.write_text(log_text)
    sch = tmp_path / "schema.json"
    sch.write_text(json.dumps(schema))
    out = tmp_path / "partial.json"
    script = os.path.join(
        os.path.dirname(__file__), "..", "scripts", "validate_output.py"
    )
    r = subprocess.run(
        ["python3", script, str(log), str(sch), "--out", str(out)],
        capture_output=True,
        text=True,
    )
    return r.returncode, out


def test_cli_exit_0_on_valid(tmp_path):
    rc, _ = _run_cli(tmp_path, '{"name": "x", "count": 1}')
    assert rc == 0


def test_cli_exit_2_and_partial_file_on_salvage(tmp_path):
    rc, out = _run_cli(tmp_path, '{"name": "x", "count": "bad"}')
    assert rc == 2
    data = json.loads(out.read_text())
    assert data["name"] == "x"
    assert data["_invalid"] == ["count"] and data["_missing"] == []


def test_cli_exit_3_when_no_json(tmp_path):
    rc, _ = _run_cli(tmp_path, "the model rambled with no JSON")
    assert rc == 3


def test_cli_exit_1_when_nothing_salvageable(tmp_path):
    rc, _ = _run_cli(tmp_path, '{"name": 5, "count": "bad"}')
    assert rc == 1


def test_salvage_rejects_bool_for_integer_and_number():
    schema = {
        "type": "object",
        "properties": {"count": {"type": "integer"}, "score": {"type": "number"}},
        "required": [],
    }
    partial, missing, invalid = salvage({"count": True, "score": False}, schema)
    assert partial == {}
    assert missing == []
    assert sorted(invalid) == ["count", "score"]

