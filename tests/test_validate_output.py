import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from validate_output import extract_json


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
