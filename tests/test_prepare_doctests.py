"""Source-selection contracts; no network, credentials, or builds required."""

import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("prepare_doctests", ROOT / "scripts/prepare-doctests.py")
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)

SHA = "abc12345" * 5
REPO = "example/logos-module-builder"
REF = f"github:{REPO}/{SHA}"


class SourceSelectionTests(unittest.TestCase):
    def pr_event(self, repo=REPO, sha=SHA, fork=True):
        return {"pull_request": {"head": {"repo": {"full_name": repo, "fork": fork}, "sha": sha}}}

    def test_same_repository_pr_in_a_fork(self):
        self.assertEqual(prepare.source_ref("pull_request", self.pr_event(), REPO, "f" * 40), REF)

    def test_cross_repository_pr_uses_head_not_base_or_merge_sha(self):
        self.assertEqual(prepare.source_ref("pull_request", self.pr_event(), "logos-co/logos-module-builder", "f" * 40), REF)

    def test_nonfork_pr(self):
        self.assertEqual(prepare.source_ref("pull_request", self.pr_event(fork=False), REPO, "f" * 40), REF)

    def test_push_and_manual_dispatch(self):
        for event in ("push", "workflow_dispatch"):
            with self.subTest(event=event):
                self.assertEqual(prepare.source_ref(event, {}, REPO, SHA), REF)

    def test_renamed_fork_is_supported(self):
        self.assertEqual(prepare.source_ref("pull_request", self.pr_event(repo="someone/builder-fork"), REPO, SHA), f"github:someone/builder-fork/{SHA}")

    def test_deleted_or_missing_pr_head_does_not_fall_back(self):
        for event in ({}, {"pull_request": {"head": {"repo": None, "sha": SHA}}}):
            with self.subTest(event=event), self.assertRaises((KeyError, TypeError)):
                prepare.source_ref("pull_request", event, REPO, SHA)

    def test_privileged_or_unknown_event_is_rejected(self):
        for event in ("pull_request_target", "schedule", "unknown"):
            with self.subTest(event=event), self.assertRaises(ValueError):
                prepare.source_ref(event, {}, REPO, SHA)

    def test_invalid_repository_is_rejected(self):
        for repo in (None, "", "owner", "owner/repo/extra", "owner/repo\n", "owner/repo;echo", "$(id)/repo"):
            with self.subTest(repo=repo), self.assertRaises(ValueError):
                prepare.source_ref("push", {}, repo, SHA)

    def test_invalid_revision_is_rejected(self):
        for sha in (None, "", "main", "abc1234", "0" * 40, SHA + "\n", "g" * 40):
            with self.subTest(sha=sha), self.assertRaises(ValueError):
                prepare.source_ref("push", {}, REPO, sha)

    def test_revision_case_is_normalized(self):
        self.assertEqual(prepare.source_ref("push", {}, REPO, SHA.upper()), REF)

    def test_direct_build_and_generated_flake_use_identical_source(self):
        text = f'run: nix build "{prepare.TEMPLATE_URL}#rust-sdk-src"\nurl = "{prepare.TEMPLATE_URL}";\n'
        pinned, count = prepare.pin_spec(text, REF)
        self.assertEqual(count, 2)
        self.assertEqual(pinned, f'run: nix build "{REF}#rust-sdk-src"\nurl = "{REF}";\n')

    def test_other_releases_and_similar_repo_names_are_untouched(self):
        other = "github:logos-co/logos-protocol{release} github:logos-co/logos-module-builder-helper{release}"
        self.assertEqual(prepare.pin_spec(prepare.TEMPLATE_URL + " " + other, REF)[0], REF + " " + other)

    def test_unrecognized_builder_sources_fail_loudly(self):
        for text in ("github:logos-co/logos-module-builder", "github:other/logos-module-builder{release}", "github:logos-co/logos-module-builder/main", "no URLs"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                prepare.pin_spec(text, REF)

    def test_all_workflow_specs_are_staged_without_changing_sources(self):
        sources = {path.name: path.read_bytes() for path in (ROOT / "doctests").glob("*.test.yaml")}
        workflow = (ROOT / ".github/workflows/doctests.yml").read_text()
        listed = set(re.findall(r"doctests/([a-z0-9-]+\.test\.yaml)", workflow))
        self.assertEqual(listed, set(sources))
        self.assertEqual(len(sources), 8)
        with tempfile.TemporaryDirectory() as work:
            output = Path(work) / "prepared"
            self.assertEqual(prepare.prepare_specs(ROOT / "doctests", output, REF), 8)
            record = json.loads((output / "source.json").read_text())
            self.assertEqual(record["builder"], REF)
            for name, original in sources.items():
                staged = (output / "doctests" / name).read_text()
                self.assertEqual(staged, original.decode().replace(prepare.TEMPLATE_URL, REF))
                self.assertGreater(record["replacements"][name], 0)
                self.assertEqual((ROOT / "doctests" / name).read_bytes(), original)

    def test_existing_output_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as work:
            output = Path(work)
            marker = output / "keep"
            marker.write_text("unchanged")
            with self.assertRaises(FileExistsError):
                prepare.prepare_specs(ROOT / "doctests", output, REF)
            self.assertEqual(marker.read_text(), "unchanged")

    def test_workflow_renders_all_specs_and_uploads_source_record(self):
        workflow = (ROOT / ".github/workflows/doctests.yml").read_text()
        generation = workflow.split("- name: Verify markdown generation", 1)[1]
        generation = generation.split("do\n", 1)[0]
        for spec in (ROOT / "doctests").glob("*.test.yaml"):
            self.assertIn(spec.name.removesuffix(".test.yaml"), generation)
        upload = workflow.split("- name: Upload execution report", 1)[1]
        upload = upload.split("- name:", 1)[0]
        self.assertRegex(upload, r"(?m)^\s+path: report-out/\s*$")

    def test_invalid_or_empty_specs_create_no_output(self):
        with tempfile.TemporaryDirectory() as work:
            specs = Path(work) / "specs"
            specs.mkdir()
            output = Path(work) / "out"
            with self.assertRaises(ValueError):
                prepare.prepare_specs(specs, output, REF)
            (specs / "bad.test.yaml").write_text("github:logos-co/logos-module-builder/main")
            with self.assertRaises(ValueError):
                prepare.prepare_specs(specs, output, REF)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
