#!/usr/bin/env python3
"""Assert that the pull-request workflow still gates.

`ct-retry-test.sh` proves the retry helper propagates a failure. That is only
half of "chart-testing failures fail the pull request": the other half is that
the workflow still *runs* chart-testing, and that nothing in the file quietly
turns the result into a pass. Text greps are not enough for that — every one of
these keeps a grep-based guard green while the required `lint-test` check goes
green having validated nothing:

  * `if:` on the **job**, above `steps:` — GitHub reports a skipped job as
    success, so the required check passes and no step ever runs;
  * `shell: bash -c "exit 0" {0}`, at workflow level or on one step, which
    makes every `run:` a no-op that succeeds;
  * a quoted key (`"continue-on-error": true`, `"if": …`), which is the same
    YAML and a different string;
  * extra arguments (`ct lint --excluded-charts codex-pooler`), which lint
    nothing and exit 0;
  * an extra step that shadows `ct` on `$GITHUB_PATH`;
  * `uses:` replacing the job body while keeping the job id, so branch
    protection still sees a green `lint-test`;
  * `env:` overriding a script's own knobs (`CHART_SEARCH_ROOT`, …).

So this parses the workflow and pins its shape: which job, which steps in which
order, which conditions, and the exact command of every step that is part of the
gate. Anything else — an added step, a renamed job, a new key — fails here and
has to be reflected in this file, which makes turning the gate off a visible
edit instead of a silent one.

The parser is deliberately small and fails closed: anything it does not
understand (tabs, flow collections, anchors, a second document) is an error, not
a shrug.

Usage: verify-ci-gate.py [workflow-path]
"""

from __future__ import annotations

import sys
from pathlib import Path

WORKFLOW = ".github/workflows/test.yml"

DEFAULT_BRANCH = "${{ github.event.repository.default_branch }}"
CHANGED = "steps.list-changed.outputs.changed"
IF_CHANGED = f"{CHANGED} == 'true'"
IF_NOT_CHANGED = f"{CHANGED} != 'true'"
CHANGED_CHARTS_ENV = {"CHANGED_CHARTS": "${{ steps.list-changed.outputs.charts }}"}

# Keys a step may carry at all. `shell` is absent on purpose: a custom shell
# (`shell: bash -c "exit 0" {0}`) turns every `run:` in its scope into a no-op
# that succeeds. `continue-on-error` is allowed only as the explicit safe value,
# checked below.
ALLOWED_STEP_KEYS = {"name", "id", "uses", "with", "run", "if", "env", "continue-on-error"}
ALLOWED_JOB_KEYS = {"runs-on", "steps"}
ALLOWED_TOP_KEYS = {"name", "on", "jobs"}

# Environment names the gate's own scripts read. A workflow- or step-level
# override of any of them switches a check off without touching its command.
PROTECTED_ENV = {
    "PATH",
    "CHART_SEARCH_ROOT",
    "HELM_DOCS_IMAGE",
    "TOPOLOGY_DRY_RUN_NAMESPACE",
    "CT_FIXTURE_TIMEOUT",
}


def run_ct(step: str, *extra: str) -> str:
    return " ".join((".github/scripts/ct-retry.sh", "ct", step, "--target-branch", DEFAULT_BRANCH) + extra)


def for_each_changed_chart(script: str) -> str:
    return f'readarray -t charts <<< "$CHANGED_CHARTS" {script} "${{charts[@]}}"'


# The gate, step by step. `run` pins the exact command (whitespace normalised,
# line continuations joined); `None` means the step's body is not part of the
# gate and only its keys and condition are pinned.
EXPECTED_STEPS: list[dict[str, object]] = [
    {"name": "Checkout", "uses": "actions/checkout@v7", "if": None, "run": None},
    {"name": "Set up Helm", "uses": "azure/setup-helm@v5.0.1", "if": None, "run": None},
    {"name": None, "uses": "actions/setup-python@v7.0.0", "if": None, "run": None},
    {"name": "Set up chart-testing", "uses": "helm/chart-testing-action@v2.8.0", "if": None, "run": None},
    {
        "name": "Lint the CI definition",
        "uses": None,
        "if": None,
        "run": ".github/scripts/lint-ci.sh",
    },
    {
        "name": "Verify CI retry helper",
        "uses": None,
        "if": None,
        "run": ".github/scripts/ct-retry-test.sh .github/scripts/verify-ci-gate.py",
    },
    {"name": "Run chart-testing (list-changed)", "uses": None, "if": None, "run": None},
    {
        "name": "Verify chart change detection",
        "uses": None,
        "if": IF_NOT_CHANGED,
        "run": f".github/scripts/assert-no-chart-changed.sh {DEFAULT_BRANCH}",
    },
    {"name": "Run chart-testing (lint)", "uses": None, "if": IF_CHANGED, "run": run_ct("lint")},
    {
        "name": "Check chart documentation is regenerated",
        "uses": None,
        "if": IF_CHANGED,
        "run": for_each_changed_chart(".github/scripts/check-chart-docs.sh"),
        "env": CHANGED_CHARTS_ENV,
    },
    {"name": "Set up helm-unittest", "uses": None, "if": IF_CHANGED, "run": None},
    {"name": "Run helm unittest (changed charts only)", "uses": None, "if": IF_CHANGED, "run": None},
    {"name": "Create kind cluster", "uses": "helm/kind-action@v1.15.0", "if": IF_CHANGED, "run": None},
    {
        "name": "Validate the rendered topology against the API server",
        "uses": None,
        "if": IF_CHANGED,
        "run": for_each_changed_chart(".github/scripts/validate-rendered-topology.sh"),
        "env": CHANGED_CHARTS_ENV,
    },
    {
        "name": "Apply chart-testing cluster fixtures",
        "uses": None,
        "if": IF_CHANGED,
        "run": for_each_changed_chart(".github/scripts/apply-ct-fixtures.sh"),
        "env": CHANGED_CHARTS_ENV,
    },
    {
        "name": "Run chart-testing (install)",
        "uses": None,
        "if": IF_CHANGED,
        "run": run_ct("install", "--helm-extra-args", "'--timeout 600s'"),
    },
]


class GateError(Exception):
    pass


# --------------------------------------------------------------------------
# a small, strict YAML subset
# --------------------------------------------------------------------------


def unquote(text: str) -> str:
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    return text


def split_key(line: str) -> tuple[str, str] | None:
    """Splits `key: value`, honouring a quoted key, or returns None."""
    stripped = line.strip()
    if stripped.startswith(("\"", "'")):
        quote = stripped[0]
        end = stripped.find(quote, 1)
        if end == -1:
            raise GateError(f"unterminated quoted key: {line!r}")
        key = stripped[1:end]
        rest = stripped[end + 1 :]
        if not rest.startswith(":"):
            raise GateError(f"quoted scalar where a key was expected: {line!r}")
        return key, rest[1:].strip()
    if ":" not in stripped:
        return None
    key, _, value = stripped.partition(":")
    if " " in key.strip():
        return None
    return key.strip(), value.strip()


class Parser:
    def __init__(self, text: str) -> None:
        if "\t" in text:
            raise GateError("the workflow contains a tab")
        self.lines = text.splitlines()
        self.index = 0

    # -- helpers ---------------------------------------------------------
    def peek(self) -> tuple[int, str] | None:
        while self.index < len(self.lines):
            line = self.lines[self.index]
            if not line.strip() or line.lstrip().startswith("#"):
                self.index += 1
                continue
            if line.strip() == "---":
                raise GateError("multi-document workflows are not understood")
            return len(line) - len(line.lstrip(" ")), line
        return None

    def check_value(self, value: str) -> str:
        if value[:1] in {"&", "*"}:
            raise GateError(f"anchors and aliases are not understood: {value!r}")
        if value[:1] in {"{", "["}:
            raise GateError(f"flow collections are not understood: {value!r}")
        return unquote(value)

    # -- structure -------------------------------------------------------
    def parse_block(self, indent: int):
        head = self.peek()
        if head is None or head[0] < indent:
            return {}
        if head[1].lstrip().startswith("- "):
            return self.parse_sequence(indent)
        return self.parse_mapping(indent)

    def parse_mapping(self, indent: int) -> dict:
        mapping: dict[str, object] = {}
        while True:
            head = self.peek()
            if head is None or head[0] < indent:
                return mapping
            level, line = head
            if level > indent:
                raise GateError(f"unexpected indentation: {line!r}")
            parts = split_key(line)
            if parts is None:
                raise GateError(f"expected a mapping key: {line!r}")
            key, value = parts
            if key in mapping:
                raise GateError(f"duplicate key: {key!r}")
            self.index += 1
            if value in {"|", "|-", ">", ">-", "|+", ">+"}:
                mapping[key] = self.parse_block_scalar(indent)
            elif value == "":
                mapping[key] = self.parse_block(indent + 2)
            else:
                mapping[key] = self.check_value(value)
        return mapping

    def parse_sequence(self, indent: int) -> list:
        items: list[object] = []
        while True:
            head = self.peek()
            if head is None or head[0] < indent:
                return items
            level, line = head
            stripped = line.lstrip()
            if level != indent or not stripped.startswith("- "):
                raise GateError(f"expected a sequence item: {line!r}")
            # Rewrite the item's first line as part of a mapping at indent + 2.
            self.lines[self.index] = " " * (indent + 2) + stripped[2:]
            item = self.parse_block(indent + 2)
            items.append(item)

    def parse_block_scalar(self, indent: int) -> str:
        body: list[str] = []
        while self.index < len(self.lines):
            line = self.lines[self.index]
            if line.strip() and (len(line) - len(line.lstrip(" "))) <= indent:
                break
            body.append(line[indent + 2 :] if line.strip() else "")
            self.index += 1
        return "\n".join(body).rstrip("\n")


def logical_commands(body: str) -> list[str]:
    """Joins line continuations, drops comments, normalises whitespace."""
    commands: list[str] = []
    current = ""
    for raw in body.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            if not current:
                continue
        current += line
        if current.rstrip().endswith("\\"):
            current = current.rstrip()[:-1] + " "
            continue
        collapsed = " ".join(current.split())
        if collapsed:
            commands.append(collapsed)
        current = ""
    if current.strip():
        commands.append(" ".join(current.split()))
    return commands


# --------------------------------------------------------------------------
# the contract
# --------------------------------------------------------------------------


def check(workflow_path: Path) -> list[str]:
    failures: list[str] = []

    def fail(message: str) -> None:
        failures.append(message)
        print(f"FAIL - {message}", file=sys.stderr)

    def ok(message: str) -> None:
        print(f"ok   - {message}")

    document = Parser(workflow_path.read_text()).parse_block(0)

    extra_top = set(document) - ALLOWED_TOP_KEYS
    if extra_top:
        fail(f"the workflow declares {sorted(extra_top)} at the top level (a `defaults:` or `env:` here reaches every step)")
    else:
        ok("the workflow declares no top-level defaults or env")

    if document.get("on") != "pull_request":
        fail(f"the workflow no longer runs unconditionally on pull_request (on: {document.get('on')!r})")
    else:
        ok("the workflow runs on every pull request, with no path filter")

    jobs = document.get("jobs")
    if not isinstance(jobs, dict) or list(jobs) != ["lint-test"]:
        fail(f"the required check is job lint-test; the workflow declares {list(jobs) if isinstance(jobs, dict) else jobs}")
        return failures
    job = jobs["lint-test"]

    extra_job = set(job) - ALLOWED_JOB_KEYS
    if extra_job:
        # `if` skips the job and GitHub reports that as success; `uses` replaces
        # the body while keeping the context name green.
        fail(f"job lint-test declares {sorted(extra_job)}; only {sorted(ALLOWED_JOB_KEYS)} are allowed")
    else:
        ok("job lint-test has no condition, no defaults and no reusable-workflow body")

    steps = job.get("steps")
    if not isinstance(steps, list):
        fail("job lint-test has no steps")
        return failures

    identity = [(s.get("name"), s.get("uses")) for s in steps]
    expected_identity = [(e["name"], e["uses"]) for e in EXPECTED_STEPS]
    if identity != expected_identity:
        fail(f"the steps of lint-test changed.\n    expected: {expected_identity}\n    found:    {identity}")
        return failures
    ok(f"lint-test runs the expected {len(steps)} steps, in order")

    for step, expected in zip(steps, EXPECTED_STEPS):
        label = step.get("name") or step.get("uses")

        extra_keys = set(step) - ALLOWED_STEP_KEYS
        if extra_keys:
            fail(
                f"step {label!r} declares {sorted(extra_keys)}; only {sorted(ALLOWED_STEP_KEYS)} are allowed "
                "(a custom `shell:` makes every run a no-op that succeeds)"
            )

        continue_on_error = step.get("continue-on-error")
        if continue_on_error not in (None, "false"):
            fail(f"step {label!r} is continue-on-error: {continue_on_error!r}")

        if step.get("if") != expected["if"]:
            fail(f"step {label!r} runs under `if: {step.get('if')!r}`, expected {expected['if']!r}")

        env = step.get("env") or {}
        if not isinstance(env, dict):
            fail(f"step {label!r} has an env block this guard cannot read")
        else:
            overridden = sorted(set(env) & PROTECTED_ENV)
            if overridden:
                fail(f"step {label!r} overrides {overridden}, which the gate's own scripts read")
            if expected.get("env") is not None and env != expected["env"]:
                fail(f"step {label!r} declares env {env!r}, expected {expected['env']!r}")

        body = step.get("run")
        if body is None:
            continue
        if not isinstance(body, str):
            fail(f"step {label!r} has a run body this guard cannot read")
            continue
        if "GITHUB_PATH" in body or "GITHUB_ENV" in body:
            fail(f"step {label!r} writes to GITHUB_PATH or GITHUB_ENV, which can shadow ct for every later step")

        if expected["run"] is None:
            continue
        found = " ".join(logical_commands(body))
        if found != expected["run"]:
            fail(f"step {label!r} runs:\n      {found}\n    expected:\n      {expected['run']}")

    if not failures:
        ok("every gate step runs exactly the command it is supposed to run")
    return failures


def main() -> int:
    workflow_path = Path(sys.argv[1] if len(sys.argv) > 1 else WORKFLOW)
    if not workflow_path.is_file():
        print(f"FAIL - {workflow_path} does not exist", file=sys.stderr)
        return 1
    try:
        failures = check(workflow_path)
    except GateError as error:
        print(f"FAIL - the workflow cannot be verified: {error}", file=sys.stderr)
        return 1
    if failures:
        print(f"{len(failures)} assertion(s) failed", file=sys.stderr)
        return 1
    print("workflow gate verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
