---
# model: Gemini 3.1 Pro (High)     # optional — omit for default Flash
# timeout: 20m                     # optional
# schema: ../schemas/result.json   # optional — enables the output gate
---
## Goal
<one sentence: what success looks like>

## Context
<project, relevant paths, how things currently work — agent sees ONLY this file>

## Scope
<files/dirs this agent MAY create/modify — and what it must NOT touch>

## Requirements
<concrete, testable specifics: signatures, endpoints, edge cases, errors>

## Conventions
<language/version, style, libraries to use or avoid>

## Verification
<exact commands the agent must run before finishing (tests/build)>

## Done criteria
<state to leave the repo in: tests passing, summary of changes, etc.>
