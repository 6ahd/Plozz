import argparse
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("performance", ROOT / "tools/performance.py")
performance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(performance)


def report(name="sync-unchanged", value=10):
    return {
        "schema": 1, "scenario": name, "warmups": 1,
        "samples": [{
            "iteration": index, "wallMilliseconds": value, "cpuMilliseconds": value,
            "residentBytes": 100_000, "residentDeltaBytes": -100,
            "counters": {key: 0 for key in performance.expected_reports([name])[name]["counters"]},
        } for index in range(5)],
    }


def run(value=10):
    return {
        "schema": 1, "status": "passed", "evidenceKind": "simulator",
        "scenarios": ["sync-unchanged"], "reports": {"sync-unchanged": report(value=value)},
        "environment": {**dict.fromkeys(("runtime", "runtimeBuild", "deviceType", "platform", "architecture",
                                        "runnerHash", "xcode", "sdk", "macOS", "hardware"), "fixture"),
                        "flags": performance.FLAGS},
        "fixtures": {"fixture.swift": "one"}, "source": {"head": "a" * 40, "files": {"source.swift": "one"}},
    }


def summary(count=1):
    return dict(result="Passed", passedTests=count, totalTestCount=count, failedTests=0,
                skippedTests=0, expectedFailures=0, testFailures=[])


class EvidenceTests(unittest.TestCase):
    def test_selection_is_explicit_and_narrow_by_default(self):
        self.assertEqual(len(performance.select(None, None)), 3)
        self.assertEqual(performance.select("matrix", None), ["runtime-matrix"])
        self.assertEqual(len(performance.expected_reports(["runtime-matrix"])), 16)
        for suite, names in [("core", ["sync-unchanged"]), (None, ["unknown"]),
                             (None, ["sync-unchanged", "sync-unchanged"])]:
            with self.assertRaises(performance.Failure):
                performance.select(suite, names)

    def test_measurement_contract_rejects_missing_nonfinite_and_duplicate_samples(self):
        original = report()
        spec = performance.SCENARIOS["sync-unchanged"]
        performance.validate_report(original, spec)
        mutations = [
            lambda r: r["samples"].pop(),
            lambda r: r["samples"][1].update(iteration=0),
            lambda r: r["samples"][0].update(cpuMilliseconds=float("nan")),
            lambda r: r["samples"][0].update(cpuMilliseconds=float("inf")),
            lambda r: r["samples"][0].update(cpuMilliseconds=-1),
            lambda r: r["samples"][0].update(cpuMilliseconds=True),
            lambda r: r["samples"][0]["counters"].pop("checks"),
            lambda r: r["samples"][0]["counters"].update(checks=-1),
            lambda r: r.update(warmups=True),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                candidate = copy.deepcopy(original)
                mutate(candidate)
                with self.assertRaises(performance.Failure):
                    performance.validate_report(candidate, spec)

    def test_only_complete_no_skip_summary_passes(self):
        performance.verify_summary(summary(), 1)
        for change in [
            {"result": "Failed"}, {"passedTests": 0}, {"skippedTests": 1},
            {"expectedFailures": 1}, {"failedTests": 1}, {"totalTestCount": 2},
            {"passedTests": True}, {"testFailures": [{"targetName": "Crash"}]},
        ]:
            with self.subTest(change=change), self.assertRaises(performance.Failure):
                performance.verify_summary(dict(summary(), **change), 1)

    def test_attachment_reader_checks_expected_set_and_paths(self):
        with tempfile.TemporaryDirectory() as path:
            folder = Path(path)
            performance.write_json(folder / "report.json", report())
            attachment = {"suggestedHumanReadableName": "plozz-performance-sync-unchanged.json",
                          "exportedFileName": "report.json"}
            def manifest(entries):
                performance.write_json(folder / "manifest.json", [{"attachments": entries}])
            manifest([attachment])
            expected = performance.expected_reports(["sync-unchanged"])
            self.assertEqual(set(performance.read_attachments(folder, expected)), {"sync-unchanged"})
            for entries in [[], [attachment, attachment],
                            [dict(attachment, exportedFileName="../report.json")]]:
                manifest(entries)
                with self.assertRaises(performance.Failure):
                    performance.read_attachments(folder, expected)

    def test_simulator_validation_never_accepts_hardware_or_wrong_platform(self):
        data = {"devices": {"com.apple.CoreSimulator.SimRuntime.tvOS-26-2": [
            {"udid": "owned", "isAvailable": True, "state": "Shutdown", "deviceTypeIdentifier": "AppleTV"},
        ]}}
        runtimes = {"runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.tvOS-26-2", "buildversion": "23K51"}]}
        info, state = performance.simulator_info(data, runtimes, "owned", "tvOS")
        self.assertEqual(state, "Shutdown")
        self.assertEqual(info["runtimeBuild"], "23K51")
        for device, platform in [("physical", "tvOS"), ("owned", "iOS")]:
            with self.assertRaises(performance.Failure):
                performance.simulator_info(data, runtimes, device, platform)

    def test_scheme_has_opt_in_without_debugger_or_coverage(self):
        tree = performance.package_scheme({"FeatureSyncCloudTests"})
        test = tree.getroot().find("TestAction")
        self.assertEqual(test.get("buildConfiguration"), "Debug")
        self.assertEqual(test.get("selectedDebuggerIdentifier"), "")
        self.assertEqual(test.get("codeCoverageEnabled"), "NO")
        variable = test.find("EnvironmentVariables/EnvironmentVariable")
        self.assertEqual(variable.get("key"), "PLOZZ_PERFORMANCE")
        self.assertEqual(variable.get("value"), "1")
        self.assertIn("SWIFT_OPTIMIZATION_LEVEL=-O", performance.FLAGS)

    def test_compare_retains_noise_and_does_not_call_within_budget_improvement(self):
        self.assertEqual(performance.compare(run(), run(11), 15)["verdict"], "within-budget")
        self.assertEqual(performance.compare(run(), run(14), 15)["verdict"], "regression")
        self.assertEqual(performance.compare(run(), run(5), 15)["verdict"], "within-budget")
        noisy = run()
        for sample, value in zip(noisy["reports"]["sync-unchanged"]["samples"], [1, 5, 10, 15, 20]):
            sample["cpuMilliseconds"] = value
        self.assertEqual(performance.compare(run(), noisy, 15)["verdict"], "inconclusive")

    def test_comparison_rejects_mismatched_fixture_platform_flags_or_selection(self):
        for key in ("fixtures", "environment", "scenarios"):
            candidate = run()
            candidate[key] = {"different": True}
            with self.assertRaises(performance.Failure):
                performance.compare(run(), candidate, 15)
        for tolerance in (-1, 101, float("nan")):
            with self.assertRaises(performance.Failure):
                performance.compare(run(), run(), tolerance)

    def test_failed_or_partial_run_cannot_become_a_baseline(self):
        with tempfile.TemporaryDirectory() as path:
            file = Path(path) / "result.json"
            performance.write_json(file, run())
            self.assertEqual(performance.read_run(file)["status"], "passed")
            for mutate in [
                lambda r: r.update(status="failed"),
                lambda r: r.update(evidenceKind="device"),
                lambda r: r["reports"].clear(),
                lambda r: r["environment"].clear(),
                lambda r: r["environment"].pop("sdk"),
                lambda r: r["source"].clear(),
                lambda r: r.update(scenarios=[]),
                lambda r: r["reports"]["sync-unchanged"].update(scenario="other"),
            ]:
                candidate = run()
                mutate(candidate)
                performance.write_json(file, candidate)
                with self.assertRaises(performance.Failure):
                    performance.read_run(file)

    def test_comparison_does_not_mutate_evidence(self):
        before, after = run(), run(15)
        original = copy.deepcopy((before, after))
        performance.compare(before, after, 15)
        self.assertEqual((before, after), original)

    def test_report_is_compact_and_preserves_units_and_counter_ranges(self):
        result = performance.summarize(run())
        self.assertNotIn("source", result)
        self.assertNotIn("fixtures", result)
        self.assertEqual(result["scenarios"]["sync-unchanged"]["metrics"]["cpuMilliseconds"]["median"], 10)
        self.assertEqual(result["scenarios"]["sync-unchanged"]["counters"]["checks"], {"min": 0, "max": 0})


class RunnerFailureTests(unittest.TestCase):
    def test_source_identity_includes_vendor_and_untracked_code_but_not_docs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("Sources/New.swift", "Vendor/decoder.c", "docs/guide.md"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture")
            args = argparse.Namespace(platform="tvOS", sim_id="owned", timeout=120, names=["sync-unchanged"])
            lane = performance.Lane(root, args, ())
            files = "Sources/New.swift\0Vendor/decoder.c\0Sources/Deleted.swift\0docs/guide.md\0"
            with patch.object(lane, "command", return_value=(0, files)):
                hashes = lane.fingerprint("source")
                (root / "Vendor/decoder.c").write_text("changed")
                changed = lane.fingerprint("changed")
            self.assertEqual(set(hashes), {"Sources/New.swift", "Vendor/decoder.c", "Sources/Deleted.swift"})
            self.assertEqual(hashes["Sources/Deleted.swift"], "deleted")
            self.assertNotEqual(hashes["Vendor/decoder.c"], changed["Vendor/decoder.c"])

    def test_timeout_stops_only_the_owned_command_and_retains_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(platform="tvOS", sim_id="owned", timeout=120, names=["sync-unchanged"])
            lane = performance.Lane(Path(directory), args, ())
            with patch.object(performance.subprocess, "Popen") as spawn, \
                    patch.object(performance, "stop_owned") as stop:
                spawn.return_value.wait.side_effect = subprocess.TimeoutExpired("owned", 1)
                with self.assertRaises(subprocess.TimeoutExpired):
                    lane.command("test", ["owned"], timeout=1)
                stop.assert_called_once_with(spawn.return_value)
                self.assertTrue((lane.output / "01-test.log").exists())
                self.assertTrue(spawn.call_args.kwargs["start_new_session"])

    def test_expired_lane_never_starts_another_process(self):
        with tempfile.TemporaryDirectory() as directory:
            args = argparse.Namespace(platform="tvOS", sim_id="owned", timeout=120, names=["sync-unchanged"])
            lane = performance.Lane(Path(directory), args, ())
            lane.deadline = 0
            with patch.object(performance.subprocess, "Popen") as spawn:
                with self.assertRaisesRegex(performance.Failure, "deadline"):
                    lane.command("test", ["owned"])
                spawn.assert_not_called()

    def test_source_change_fails_and_only_newly_booted_simulator_is_shutdown(self):
        for state in ("Shutdown", "Booted"):
            with self.subTest(state=state), tempfile.TemporaryDirectory() as directory:
                args = argparse.Namespace(platform="tvOS", sim_id="owned", timeout=120, names=["sync-unchanged"])
                lane = performance.Lane(Path(directory), args, ())
                labels = []
                def command(label, *_args, **_kwargs):
                    labels.append(label)
                    text = {
                        "simulators": "{}", "runtimes": "{}",
                        "package-options": "-clonedSourcePackagesDirPath\0private\0",
                        "source-head": "a" * 40,
                    }.get(label, "fixture")
                    return 0, text
                sources = {"tools/performance.py": "one", "Tests/fixture.swift": "one"}
                with patch.object(lane, "command", side_effect=command), \
                        patch.object(lane, "fingerprint", side_effect=[sources, dict(sources, changed="two")]), \
                        patch.object(lane, "run_group", return_value={"sync-unchanged": report()}), \
                        patch.object(performance, "simulator_info", return_value=({}, state)):
                    with self.assertRaisesRegex(performance.Failure, "Source changed"):
                        lane.execute()
                result = json.loads((lane.output / "result.json").read_text())
                self.assertEqual(result["status"], "failed")
                self.assertEqual("simulator-shutdown" in labels, state == "Shutdown")

    def test_build_failure_restores_project_and_retains_scheme(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "Plozz.xcodeproj"
            project.mkdir()
            (project / "original").write_text("keep")
            args = argparse.Namespace(platform="tvOS", sim_id="owned", timeout=120, names=["sync-unchanged"])
            lane = performance.Lane(root, args, ())
            with patch.object(lane, "command", side_effect=performance.Failure("build failed")):
                with self.assertRaisesRegex(performance.Failure, "build failed"):
                    lane.run_group(args.names, ["-clonedSourcePackagesDirPath", "private"], False)
            self.assertEqual((project / "original").read_text(), "keep")
            self.assertEqual(len(list((lane.output / "core").glob("*.xcscheme"))), 1)

    def test_restoration_conflict_preserves_both_projects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "Plozz.xcodeproj"
            project.mkdir()
            (project / "original").write_text("keep")
            args = argparse.Namespace(platform="tvOS", sim_id="owned", timeout=120, names=["sync-unchanged"])
            lane = performance.Lane(root, args, ())
            def conflicting_writer(*_args, **_kwargs):
                project.mkdir()
                (project / "concurrent").write_text("keep too")
                raise performance.Failure("writer")
            with patch.object(lane, "command", side_effect=conflicting_writer):
                with self.assertRaisesRegex(performance.Failure, "restoration conflict"):
                    lane.run_group(args.names, [], False)
            self.assertEqual((project / "concurrent").read_text(), "keep too")
            self.assertEqual((lane.output / "Plozz.xcodeproj/original").read_text(), "keep")

    def test_nonzero_test_driver_exit_cannot_be_overridden_by_passing_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = argparse.Namespace(platform="tvOS", sim_id="owned", timeout=120, names=["sync-unchanged"])
            lane = performance.Lane(root, args, ())
            def command(label, *_args, **_kwargs):
                return (65, "") if label.endswith("-test") else (0, json.dumps(summary()))
            with patch.object(lane, "command", side_effect=command):
                with self.assertRaisesRegex(performance.Failure, "passing summary"):
                    lane.run_group(args.names, [], False)


if __name__ == "__main__":
    unittest.main()
