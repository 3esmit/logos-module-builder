#!/usr/bin/env python3
"""Stage CI-only specs against the exact GitHub source under test."""

import argparse
import json
import os
from pathlib import Path
import re


TEMPLATE_URL = "github:logos-co/logos-module-builder{release}"
BUILDER_URL = re.compile(r"github:[A-Za-z0-9_.-]+/logos-module-builder(?=[/{#?\s\"'\\]|$)")


def source_ref(event_name, event, repository, sha):
    if event_name == "pull_request":
        head = event["pull_request"]["head"]
        # repo.fork describes the repository, not whether this is a cross-repo
        # PR. A missing/deleted head is an error, never permission to test main.
        repository = head["repo"]["full_name"]
        sha = head["sha"]
    elif event_name not in {"push", "workflow_dispatch"}:
        raise ValueError(f"unsupported event: {event_name}")
    if not isinstance(repository, str) or not re.fullmatch(
        r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repository
    ):
        raise ValueError("source repository must be owner/name")
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", sha) or set(sha) == {"0"}:
        raise ValueError("source revision must be a nonzero full commit SHA")
    return f"github:{repository}/{sha.lower()}"


def pin_spec(text, ref):
    matches = list(BUILDER_URL.finditer(text))
    if not matches:
        raise ValueError("spec has no builder source URL")
    for match in matches:
        if not text.startswith(TEMPLATE_URL, match.start()):
            raise ValueError("builder URL must use the canonical {release} template")
    return text.replace(TEMPLATE_URL, ref), len(matches)


def prepare_specs(spec_dir, output_root, ref):
    # Validate every spec before creating output. The current specs are
    # self-contained; their relative doctests/ paths stay unchanged for the
    # workflow and the workspace's spec-list discovery.
    prepared = {}
    counts = {}
    for path in sorted(spec_dir.glob("*.test.yaml")):
        prepared[path.name], counts[path.name] = pin_spec(path.read_text(encoding="utf-8"), ref)
    if not prepared:
        raise ValueError("no doc-test specs found")
    output_root.mkdir(parents=True, exist_ok=False)
    destination = output_root / "doctests"
    destination.mkdir()
    for name, text in prepared.items():
        (destination / name).write_text(text, encoding="utf-8")
    (output_root / "source.json").write_text(
        json.dumps({"builder": ref, "replacements": counts}, indent=2) + "\n", encoding="utf-8"
    )
    return len(prepared)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec-dir", type=Path, default=Path("doctests"))
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
        ref = source_ref(
            os.environ["GITHUB_EVENT_NAME"], event,
            os.environ.get("GITHUB_REPOSITORY"), os.environ.get("GITHUB_SHA"),
        )
        count = prepare_specs(args.spec_dir, args.output_root, ref)
    except (KeyError, TypeError, ValueError, OSError) as error:
        parser.exit(1, f"Cannot prepare exact-source doc-tests: {error}\n")
    print(f"Prepared {count} doc-tests against {ref}")


if __name__ == "__main__":
    main()
