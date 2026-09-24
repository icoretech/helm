#!/usr/bin/env python3
"""Assert that the pull-request and main-push validation workflow still gates.

`ct-retry-test.sh` proves the retry helper propagates a failure. That is only
half of "chart-testing failures fail validation": the other half is that the
workflow still *runs* chart-testing on pull requests and main pushes, and that
nothing in the file quietly turns the result into a pass.

Two earlier versions of this guard read parts of the file — two step bodies, a
grep for one key, a list of forbidden environment names — and each time the gate
was turned off through a part they did not read. So this version reads the whole
job and pins it: the trigger, the workflow's own keys, the job's keys, the
ordered list of steps, and for every step its `uses`, its `with`, its `if`, its
`env` and its exact command. Anything that differs fails here. Turning the gate
off still requires an edit — it just has to be an edit to this file too, which
is visible in review rather than silent.

`--self-test` re-applies the known defeats to the real workflow in memory and
requires each of them to fail, so the guard cannot rot into agreeing with
everything.

WHAT THIS DOES NOT READ, and therefore does not protect (an honest list, because
the last two versions each claimed a class was closed and it was not):

  * the contents of the scripts it names. `ct-retry.sh` has its own contract
    test; `lint-ci.sh`, `check-chart-docs.sh`, `assert-no-chart-changed.sh`,
    `validate-rendered-topology.sh` and `apply-ct-fixtures.sh` do not. Editing
    one of them is an ordinary code change that only review catches.
  * the behaviour of the actions behind the immutable `uses:` commits. The
    source cannot move, but the runner and network it executes on still can.
  * the other workflows in the repository, beyond refusing a second workflow
    that declares a job with the required check's name. `release.yml` and
    `sync-gh-pages.yml` are not part of this gate and are not checked.
  * anything on the GitHub side: which contexts branch protection requires,
    whether `enforce_admins` is on, whether a review is required, or how GitHub
    resolves two check runs with the same name.
  * the runner image, the network, and the registries the pinned tools are
    pulled from.
  * its own deletion. A change that removes the step that runs this file also
    removes the run that would report it; nothing inside a workflow survives
    that. Release publication now requires a successful validation workflow,
    but branch protection and review remain the external control for changes to
    both workflows together.

Usage: verify-ci-gate.py [workflow-path] [--self-test]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

WORKFLOW = ".github/workflows/test.yml"
REQUIRED_CHECK = "lint-test"

TARGET_REF = "${{ github.event_name == 'push' && 'validation-base' || github.event.repository.default_branch }}"
TARGET_REF_ENV = {"TARGET_REF": TARGET_REF}
IF_CHANGED = "steps.list-changed.outputs.changed == 'true'"
IF_NOT_CHANGED = "steps.list-changed.outputs.changed != 'true'"
CHANGED_CHARTS_ENV = {"CHANGED_CHARTS": "${{ steps.list-changed.outputs.charts }}"}

EXPECTED_TOP = {
    "name": "Lint and Test Charts",
    "on": {"pull_request": {}, "push": {"branches": "main"}},
    "permissions": {"contents": "read"},
}
EXPECTED_JOB_KEYS = {"runs-on", "timeout-minutes", "steps"}
# `concurrency` can only cancel or queue a run, never turn a failure green, so
# it is allowed at the top level without a pinned value.
OPTIONAL_TOP_KEYS = {"concurrency"}
EXPECTED_JOB = {"runs-on": "ubuntu-latest", "timeout-minutes": "30"}

CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
SETUP_HELM_ACTION = "azure/setup-helm@9bc31f4ebc9c6b171d7bfbaa5d006ae7abdb4310"
SETUP_PYTHON_ACTION = "actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97"
CHART_TESTING_ACTION = "helm/chart-testing-action@6ec842c01de15ebb84c8627d2744a0c2f2755c9f"
KIND_ACTION = "helm/kind-action@06c1ae10762d3b9c1644e7fe69596ae519e015a2"

# Keys a step may carry at all. `shell` is absent on purpose: a custom shell
# (`shell: bash -c "exit 0" {0}`) turns every `run:` in its scope into a no-op
# that succeeds. `continue-on-error` is allowed only as the explicit safe value.
ALLOWED_STEP_KEYS = {"name", "id", "uses", "with", "run", "if", "env", "continue-on-error"}


def for_each_changed_chart(script: str) -> list[str]:
    return ['readarray -t charts <<< "$CHANGED_CHARTS"', f'{script} "${{charts[@]}}"']


# The gate, step by step. Every field is pinned: `None` means "must be absent",
# and `run` is the list of logical commands (continuations joined, comments
# dropped, whitespace collapsed) the step must run — no step is exempt, because
# an unpinned body can shadow `ct`, `helm` or `helm-docs` for every step after it.
EXPECTED_STEPS: list[dict] = [
    {
        "name": "Checkout",
        "uses": CHECKOUT_ACTION,
        # `ref:` here would check out the base commit: the runner would then
        # validate a tree without the pull request's chart changes, and both
        # halves of the change detection would honestly agree that nothing
        # changed.
        "with": {"fetch-depth": "0"},
    },
    # Renovate updates this exact pin with the workflows; an omitted version
    # would make `azure/setup-helm` install whatever is latest at check time.
    {"name": "Set up Helm", "uses": SETUP_HELM_ACTION, "with": {"version": "v4.3.0"}},
    {
        "name": None,
        "uses": SETUP_PYTHON_ACTION,
        "with": {"python-version": "3.14", "check-latest": "true"},
    },
    # `with: {version: …}` here would change which ct the pinned commands invoke.
    {"name": "Set up chart-testing", "uses": CHART_TESTING_ACTION},
    {"name": "Lint the CI definition", "run": [".github/scripts/lint-ci.sh"]},
    {
        "name": "Verify CI retry helper",
        "run": [
            ".github/scripts/ct-retry-test.sh",
            ".github/scripts/verify-ci-gate.py",
            ".github/scripts/verify-ci-gate.py --self-test",
        ],
    },
    {
        "name": "Run chart-testing (list-changed)",
        "id": "list-changed",
        "env": TARGET_REF_ENV,
        "run": [
            "if [[ \"${{ github.event_name }}\" == 'push' ]]; then",
            'git update-ref "refs/remotes/origin/$TARGET_REF" "${{ github.event.before }}"',
            "fi",
            'changed=$(ct list-changed --target-branch "$TARGET_REF")',
            'if [[ -n "$changed" ]]; then',
            'echo "changed=true" >> "$GITHUB_OUTPUT"',
            "fi",
            "{",
            'echo "charts<<CHANGED_CHARTS_EOF"',
            'echo "$changed"',
            'echo "CHANGED_CHARTS_EOF"',
            '} >> "$GITHUB_OUTPUT"',
        ],
    },
    {
        "name": "Verify chart change detection",
        "if": IF_NOT_CHANGED,
        "env": TARGET_REF_ENV,
        "run": ['.github/scripts/assert-no-chart-changed.sh "$TARGET_REF"'],
    },
    {
        "name": "Run chart-testing (lint)",
        "if": IF_CHANGED,
        "env": TARGET_REF_ENV,
        "run": ['.github/scripts/ct-retry.sh ct lint --target-branch "$TARGET_REF"'],
    },
    {
        "name": "Check chart documentation is regenerated",
        "if": IF_CHANGED,
        "env": CHANGED_CHARTS_ENV,
        "run": for_each_changed_chart(".github/scripts/check-chart-docs.sh"),
    },
    {
        "name": "Run chart schema contracts",
        "if": IF_CHANGED,
        "env": CHANGED_CHARTS_ENV,
        "run": [
            'readarray -t charts <<< "$CHANGED_CHARTS"',
            'for chart in "${charts[@]}"; do',
            '[[ -n "$chart" ]] || continue',
            'if [[ -f "$chart/scripts/test-schema.sh" ]]; then',
            'echo "==> schema contract $chart"',
            'bash "$chart/scripts/test-schema.sh"',
            "fi",
            "done",
        ],
    },
    {
        "name": "Set up helm-unittest",
        "if": IF_CHANGED,
        "run": [
            "helm plugin install https://github.com/helm-unittest/helm-unittest"
            " --version v0.5.1 --verify=false"
        ],
    },
    {
        "name": "Run helm unittest (changed charts only)",
        "if": IF_CHANGED,
        "env": CHANGED_CHARTS_ENV,
        "run": [
            "status=0",
            "while IFS= read -r chart; do",
            '[[ -n "$chart" ]] || continue',
            'if [[ ! -d "$chart/tests" ]]; then',
            'echo "::notice::skipping $chart (no tests directory)"',
            "continue",
            "fi",
            'echo "==> helm unittest $chart"',
            'if ! helm unittest "$chart"; then',
            'echo "::error::helm unittest failed for $chart"',
            "status=1",
            "fi",
            'done <<< "$CHANGED_CHARTS"',
            'exit "$status"',
        ],
    },
    {"name": "Create kind cluster", "if": IF_CHANGED, "uses": KIND_ACTION},
    {
        "name": "Validate the rendered topology against the API server",
        "if": IF_CHANGED,
        "env": CHANGED_CHARTS_ENV,
        "run": for_each_changed_chart(".github/scripts/validate-rendered-topology.sh"),
    },
    {
        "name": "Apply chart-testing cluster fixtures",
        "if": IF_CHANGED,
        "env": CHANGED_CHARTS_ENV,
        "run": for_each_changed_chart(".github/scripts/apply-ct-fixtures.sh"),
    },
    {
        "name": "Run chart-testing (install)",
        "if": IF_CHANGED,
        "env": TARGET_REF_ENV,
        "run": [
            '.github/scripts/ct-retry.sh ct install --target-branch "$TARGET_REF"'
            " --helm-extra-args '--timeout 600s'"
        ],
    },
]


class GateError(Exception):
    pass


# --------------------------------------------------------------------------
# a small, strict YAML subset — anything it does not understand is an error
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
            self.lines[self.index] = " " * (indent + 2) + stripped[2:]
            items.append(self.parse_block(indent + 2))

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


def other_workflows_claiming_the_check(workflow_path: Path) -> list[str]:
    """Other workflow files that declare a job with the required check's name.

    Branch protection requires a context name, not a file. A second workflow
    with a job called `lint-test` produces a second check run with that name,
    which this guard would otherwise never see.
    """
    offenders: list[str] = []
    directory = workflow_path.parent
    if not directory.is_dir():
        return offenders
    # Deliberately blunt: GitHub names a check run after `jobs.<id>.name` when it
    # is set and after the id otherwise, and both can be written at any
    # indentation, quoted, or in flow style. An indent-and-id heuristic missed
    # all three variants while printing an ok line, so any other workflow that
    # so much as mentions the required check's name is reported here.
    for candidate in sorted(directory.glob("*.y*ml")):
        if candidate.resolve() == workflow_path.resolve():
            continue
        if REQUIRED_CHECK in candidate.read_text():
            offenders.append(candidate.name)
    return offenders


def chart_testing_configs(repo_root: Path) -> list[str]:
    """chart-testing config files in the repository root.

    `ct` resolves its configuration with viper, so `ct.yml`, `ct.json` and
    `ct.toml` are honoured exactly like `ct.yaml`, and a config can exclude a
    chart from every ct command. That defeat needs no change under `.github/`
    at all, which is why it is checked here — in the step that always runs —
    rather than only in the cross-check step, which cannot run in the branch
    where the config succeeded.
    """
    names = []
    for stem in ("ct", ".ct", "chart_testing"):
        for extension in ("yaml", "yml", "json", "toml", "hcl", "ini", "properties", "env"):
            candidate = repo_root / f"{stem}.{extension}"
            if candidate.exists():
                names.append(candidate.name)
    return names


def check(workflow_path: Path, quiet: bool = False) -> list[str]:
    failures: list[str] = []

    def fail(message: str) -> None:
        failures.append(message)
        if not quiet:
            print(f"FAIL - {message}", file=sys.stderr)

    def ok(message: str) -> None:
        if not quiet:
            print(f"ok   - {message}")

    document = Parser(workflow_path.read_text()).parse_block(0)

    extra_top = set(document) - (set(EXPECTED_TOP) | OPTIONAL_TOP_KEYS | {"jobs"})
    if extra_top:
        fail(f"the workflow declares {sorted(extra_top)} at the top level (a `defaults:` or `env:` here reaches every step)")
    for key, value in EXPECTED_TOP.items():
        if document.get(key) != value:
            fail(f"the workflow's {key} is {document.get(key)!r}, expected {value!r}")
    if not failures:
        ok("the workflow runs on pull requests and main pushes, read-only, with no defaults or env")

    jobs = document.get("jobs")
    if not isinstance(jobs, dict) or list(jobs) != [REQUIRED_CHECK]:
        fail(f"the required check is job {REQUIRED_CHECK}; the workflow declares {list(jobs) if isinstance(jobs, dict) else jobs}")
        return failures
    job = jobs[REQUIRED_CHECK]

    extra_job = set(job) - EXPECTED_JOB_KEYS
    if extra_job:
        # `if` skips the job and GitHub reports that as success; `uses` replaces
        # the body while keeping the context name green.
        fail(f"job {REQUIRED_CHECK} declares {sorted(extra_job)}; only {sorted(EXPECTED_JOB_KEYS)} are allowed")
    for key, value in EXPECTED_JOB.items():
        if job.get(key) != value:
            fail(f"job {REQUIRED_CHECK} has {key}: {job.get(key)!r}, expected {value!r}")
    if not extra_job:
        ok(f"job {REQUIRED_CHECK} has no condition, no defaults and no reusable-workflow body")

    configs = chart_testing_configs(workflow_path.parent.parent.parent)
    if configs:
        fail(f"chart-testing configuration in the repository root: {configs}. It can exclude a chart from every ct command without touching this workflow")
    else:
        ok("no chart-testing configuration can redirect or exclude a chart")

    offenders = other_workflows_claiming_the_check(workflow_path)
    if offenders:
        fail(f"another workflow mentions {REQUIRED_CHECK}, and a job id or display name there produces a second check run with the required name: {offenders}")
    else:
        ok(f"no other workflow produces a {REQUIRED_CHECK} check run")

    steps = job.get("steps")
    if not isinstance(steps, list):
        fail(f"job {REQUIRED_CHECK} has no steps")
        return failures

    identity = [(s.get("name"), s.get("uses")) for s in steps]
    expected_identity = [(e.get("name"), e.get("uses")) for e in EXPECTED_STEPS]
    if identity != expected_identity:
        fail(f"the steps of {REQUIRED_CHECK} changed.\n    expected: {expected_identity}\n    found:    {identity}")
        return failures
    ok(f"{REQUIRED_CHECK} runs the expected {len(steps)} steps, in order")

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

        for key in ("if", "id", "with", "env"):
            if step.get(key) != expected.get(key):
                fail(f"step {label!r} has {key}: {step.get(key)!r}, expected {expected.get(key)!r}")

        body = step.get("run")
        if body is None and expected.get("run") is None:
            continue
        if not isinstance(body, str):
            fail(f"step {label!r} has no run body, expected {expected.get('run')!r}")
            continue
        if expected.get("run") is None:
            fail(f"step {label!r} runs a command and should not: {logical_commands(body)!r}")
            continue
        found = logical_commands(body)
        if found != expected["run"]:
            fail(f"step {label!r} runs:\n      {found}\n    expected:\n      {expected['run']}")

    if not failures:
        ok("every step runs exactly the command it is supposed to run")
    return failures


# --------------------------------------------------------------------------
# self-test: the guard must still reject the known defeats
# --------------------------------------------------------------------------

MUTATIONS: list[tuple[str, tuple[str, str]]] = [
    (
        "an if: on the job, which GitHub reports as a successful skip",
        ("  lint-test:\n    runs-on:", "  lint-test:\n    if: github.event.pull_request.number == 0\n    runs-on:"),
    ),
    (
        "a workflow-level custom shell, which makes every run a no-op",
        (
            "permissions:\n  contents: read\n",
            'defaults:\n  run:\n    shell: bash -c "exit 0" {0}\n\npermissions:\n  contents: read\n',
        ),
    ),
    (
        "a step-level custom shell",
        ("      - name: Run chart-testing (install)\n", '      - name: Run chart-testing (install)\n        shell: bash -c "exit 0" {0}\n'),
    ),
    (
        "a quoted continue-on-error key",
        ("      - name: Run chart-testing (lint)\n", '      - name: Run chart-testing (lint)\n        "continue-on-error": true\n'),
    ),
    (
        "a quoted if key on the guard step",
        ("      - name: Verify CI retry helper\n", '      - name: Verify CI retry helper\n        "if": ${{ false }}\n'),
    ),
    (
        "an extra ct flag that excludes the chart",
        ("ct-retry.sh ct lint \\", "ct-retry.sh ct lint --excluded-charts codex-pooler \\"),
    ),
    (
        "CT_EXCLUDED_CHARTS in a step env, which turns ct off without touching its command",
        (
            "      - name: Run chart-testing (lint)\n        if: steps.list-changed.outputs.changed == 'true'\n        env:\n          TARGET_REF:",
            "      - name: Run chart-testing (lint)\n        if: steps.list-changed.outputs.changed == 'true'\n        env:\n          CT_EXCLUDED_CHARTS: codex-pooler\n          TARGET_REF:",
        ),
    ),
    (
        "a workflow-level env override of a script's own knobs",
        (
            "permissions:\n  contents: read\n",
            "env:\n  CHART_SEARCH_ROOT: /tmp\n\npermissions:\n  contents: read\n",
        ),
    ),
    (
        "an inserted step that shadows ct on PATH",
        (
            "      - name: Run chart-testing (list-changed)\n",
            '      - name: Cache warmup\n        run: echo /tmp/bin >> "$GITHUB_PATH"\n\n      - name: Run chart-testing (list-changed)\n',
        ),
    ),
    (
        "the job replaced by a reusable workflow, keeping the required context name",
        ("    runs-on: ubuntu-latest\n    timeout-minutes: 30\n", "    uses: ./.github/workflows/ct-reusable.yml\n"),
    ),
    (
        "checkout pinned to the base commit, so the runner validates the base tree",
        (
            "        with:\n          fetch-depth: 0\n",
            "        with:\n          fetch-depth: 0\n          ref: ${{ github.event.pull_request.base.sha }}\n",
        ),
    ),
    (
        "a different chart-testing version behind the pinned commands",
        (
            f"      - name: Set up chart-testing\n        uses: {CHART_TESTING_ACTION}\n",
            f"      - name: Set up chart-testing\n        uses: {CHART_TESTING_ACTION}\n        with:\n          version: v3.7.1\n",
        ),
    ),
    (
        "the unit suite turned into a no-op inside an unpinned body",
        ('if ! helm unittest "$chart"; then', "if ! true; then"),
    ),
    (
        "an unpinned body overwriting a tool the later steps run",
        (
            '          changed=$(ct list-changed',
            '          printf "exit 0" > /usr/local/bin/ct\n          changed=$(ct list-changed',
        ),
    ),
    (
        "an or-true after the helper",
        (
            "          .github/scripts/ct-retry.sh ct lint \\\n            --target-branch \"$TARGET_REF\"",
            "          .github/scripts/ct-retry.sh ct lint \\\n            --target-branch \"$TARGET_REF\" || true",
        ),
    ),
    (
        "the main-push validation trigger deleted",
        ("  push:\n    branches: main\n", ""),
    ),
    (
        "the change-detection cross-check inverted so it never runs",
        (
            "      - name: Verify chart change detection\n        if: steps.list-changed.outputs.changed != 'true'",
            "      - name: Verify chart change detection\n        if: steps.list-changed.outputs.changed == 'true'",
        ),
    ),
    (
        "the guard step deleted",
        (
            "      - name: Verify CI retry helper\n        run: |\n          .github/scripts/ct-retry-test.sh\n          .github/scripts/verify-ci-gate.py\n          .github/scripts/verify-ci-gate.py --self-test\n\n",
            "",
        ),
    ),
]


def self_test(workflow_path: Path) -> int:
    import tempfile

    source = workflow_path.read_text()
    failures = 0
    rejected = 0
    accepted = 0

    if check(workflow_path, quiet=True):
        print("FAIL - the unmutated workflow does not pass its own contract", file=sys.stderr)
        failures += 1
    else:
        print("ok   - the unmutated workflow passes")

    with tempfile.TemporaryDirectory() as directory:
        for description, (old, new) in MUTATIONS:
            if old not in source:
                print(f"FAIL - the workflow no longer contains the text this case mutates: {description}", file=sys.stderr)
                failures += 1
                continue
            mutated = Path(directory) / "test.yml"
            mutated.write_text(source.replace(old, new, 1))
            try:
                detected = bool(check(mutated, quiet=True))
            except GateError as error:
                # Rejecting a mutation because the parser choked on it proves
                # nothing about the contract, so it counts as a self-test
                # failure rather than as a catch.
                print(f"FAIL - parse error, not a contract failure: {description} ({error})", file=sys.stderr)
                failures += 1
                continue
            if detected:
                rejected += 1
                print(f"ok   - rejected: {description}")
            else:
                print(f"FAIL - accepted: {description}", file=sys.stderr)
                failures += 1

        # These cases need a directory, not a single file.
        shadow_dir = Path(directory) / "workflows"
        shadow_dir.mkdir()
        (shadow_dir / "test.yml").write_text(source)
        shadows = {
            "a second workflow whose job id is the required check": (
                "name: Shadow\non: pull_request\n\njobs:\n  lint-test:\n    runs-on: ubuntu-latest\n"
                "    steps:\n      - name: Nothing\n        run: 'true'\n"
            ),
            "a second workflow whose job display name is the required check": (
                "name: Shadow\non: pull_request\n\njobs:\n  shadow:\n    name: lint-test\n"
                "    runs-on: ubuntu-latest\n    steps:\n      - name: Nothing\n        run: 'true'\n"
            ),
            "a second workflow declaring the job id at four-space indent": (
                "name: Shadow\non: pull_request\njobs:\n    lint-test:\n        runs-on: ubuntu-latest\n"
                "        steps:\n          - name: Nothing\n            run: 'true'\n"
            ),
            "a second workflow declaring the job in flow style": (
                "name: Shadow\non: pull_request\njobs: {lint-test: {runs-on: ubuntu-latest, "
                "steps: [{name: Nothing, run: 'true'}]}}\n"
            ),
        }
        for description, body in shadows.items():
            (shadow_dir / "zz-shadow.yml").write_text(body)
            if check(shadow_dir / "test.yml", quiet=True):
                rejected += 1
                print(f"ok   - rejected: {description}")
            else:
                print(f"FAIL - accepted: {description}", file=sys.stderr)
                failures += 1
        (shadow_dir / "zz-shadow.yml").unlink()

        # Hardening the guard must accept, or it gets worked around. Action refs
        # are already exact immutable commits; workflow-level concurrency is a
        # safe scheduling control rather than a validation bypass.
        hardening = {
            "a workflow-level concurrency group": (
                "permissions:\n  contents: read\n",
                "concurrency:\n  group: ${{ github.workflow }}-${{ github.ref }}\n\npermissions:\n  contents: read\n",
            ),
        }
        for description, (old, new) in hardening.items():
            hardened = Path(directory) / "test.yml"
            hardened.write_text(source.replace(old, new, 1))
            if check(hardened, quiet=True):
                print(f"FAIL - blocked: {description}", file=sys.stderr)
                failures += 1
            else:
                accepted += 1
                print(f"ok   - accepted: {description}")

        # A chart-testing config in the repository root needs the real layout:
        # <root>/.github/workflows/test.yml.
        root = Path(directory) / "repo"
        (root / ".github" / "workflows").mkdir(parents=True)
        (root / ".github" / "workflows" / "test.yml").write_text(source)
        for name in ("ct.yaml", "ct.yml", "ct.json", "ct.toml"):
            config = root / name
            config.write_text("excluded-charts: [codex-pooler]\n")
            if check(root / ".github" / "workflows" / "test.yml", quiet=True):
                rejected += 1
                print(f"ok   - rejected: a repository-root {name} that can exclude a chart from every ct command")
            else:
                print(f"FAIL - accepted: a repository-root {name}", file=sys.stderr)
                failures += 1
            config.unlink()

    if failures:
        print(f"{failures} self-test case(s) failed", file=sys.stderr)
        return 1
    print(f"self-test passed: {rejected} defeats rejected, {accepted} hardening changes accepted")
    return 0


def main() -> int:
    arguments = [argument for argument in sys.argv[1:] if argument != "--self-test"]
    workflow_path = Path(arguments[0] if arguments else WORKFLOW)
    if not workflow_path.is_file():
        print(f"FAIL - {workflow_path} does not exist", file=sys.stderr)
        return 1
    try:
        if "--self-test" in sys.argv[1:]:
            return self_test(workflow_path)
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
