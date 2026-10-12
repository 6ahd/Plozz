#!/usr/bin/env python3
"""Device-free Plozz performance lab: list, run, report, compare. No hardware installs."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import signal
import statistics
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 1
SAMPLES = 5
FLAGS = [
    "SWIFT_OPTIMIZATION_LEVEL=-O", "GCC_OPTIMIZATION_LEVEL=s",
    "COMPILER_INDEX_STORE_ENABLE=NO", "DEBUG_INFORMATION_FORMAT=dwarf",
    "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO",
]
METRICS = ("wallMilliseconds", "cpuMilliseconds", "residentBytes", "residentDeltaBytes")
SCENARIOS = {
    "sync-unchanged": {
        "suite": "core", "target": "FeatureSyncCloudTests",
        "test": "CloudSyncPersistenceStateTests/testPerformanceUnchangedLedger",
        "file": "Tests/FeatureSyncCloudTests/CloudSyncPersistenceStateTests.swift",
        "description": "1,000 unchanged persistence checks over 10,000 records; then a real edit.",
        "counters": ["checks", "records", "persistenceCalls"],
    },
    "library-unchanged": {
        "suite": "core", "target": "ProviderShareTests",
        "test": "ShareScannerIncrementalTests/testPerformanceUnchangedLibrary",
        "file": "Tests/ProviderShareTests/ShareScannerIncrementalTests.swift",
        "description": "Warm incremental scan of 1,000 films; then verify a newly added file.",
        "counters": ["directoryListings", "assets", "inventoryUpdates"],
    },
    "catalog-import": {
        "suite": "core", "target": "ProviderIPTVTests",
        "test": "IPTVPerformanceProbeTests/testPerformanceCatalogImport",
        "file": "Tests/ProviderIPTVTests/IPTVPerformanceProbeTests.swift",
        "description": "Fresh local SQLite import of 10,000 generated records per sample.",
        "counters": ["records"],
    },
    "cards-idle": {
        "suite": "ui", "test": "CardPerformanceTests/testPerformanceIdle",
        "file": "Tests/PerformancePresentationSupport/CardPerformanceTests.swift",
        "description": "Settled production media rows, 500 ms idle windows; not whole-app idle.",
        "counters": ["cardInputBuilds"], "timing": ["cpuMilliseconds"],
    },
    "cards-scroll": {
        "suite": "ui", "test": "CardPerformanceTests/testPerformanceScroll",
        "file": "Tests/PerformancePresentationSupport/CardPerformanceTests.swift",
        "description": "Programmatic traversal of mounted production media rows; not hardware frame pacing.",
        "counters": ["scrolls"],
    },
    "cards-lifecycle": {
        "suite": "ui", "test": "CardPerformanceTests/testPerformanceLifecycle",
        "file": "Tests/PerformancePresentationSupport/CardPerformanceTests.swift",
        "description": "Repeated mount/unmount; weak host and view checks must release.",
        "counters": ["cycles", "survivingHosts"],
    },
    "runtime-matrix": {
        "suite": "matrix", "target": "AppRuntimeTests",
        "test": "LiveTVAutomaticChannelsRuntimeTests/testPerformanceConfigurationMatrix",
        "file": "Tests/AppRuntimeTests/LiveTVAutomaticChannelsRuntimeTests.swift",
        "description": "16 combinations: 1/4 providers x Plozz Channels x Live TV data x local cloud-sync processing.",
        "counters": ["providers", "automaticChannels", "liveTV", "cloudSync", "refreshes",
                     "providerRequests", "portableRecords", "persistenceCalls"],
        "reports": [f"runtime-p{p}-c{c}-l{l}-s{s}"
                    for p in (1, 4) for c in (0, 1) for l in (0, 1) for s in (0, 1)],
    },
}


class Failure(RuntimeError):
    pass


def load_module(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")


def select(suite, names):
    if names:
        if suite:
            raise Failure("Choose --suite or --scenario, not both.")
        if len(names) != len(set(names)) or not set(names) <= SCENARIOS.keys():
            raise Failure("Unknown or duplicate scenario. Run 'list' for supported names.")
        return sorted(names)
    return [name for name, spec in SCENARIOS.items() if suite == "all" or spec["suite"] == (suite or "core")]


def expected_reports(names):
    return {report: spec for name in names for spec in [SCENARIOS[name]]
            for report in spec.get("reports", [name])}


def validate_report(report, spec):
    if (type(report.get("schema")) is not int or report["schema"] != SCHEMA
            or type(report.get("warmups")) is not int or report["warmups"] != 1):
        raise Failure("Invalid performance report schema/warmup count.")
    samples = report.get("samples")
    if not isinstance(samples, list) or len(samples) != SAMPLES:
        raise Failure(f"Expected exactly {SAMPLES} measured samples.")
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict) or type(sample.get("iteration")) is not int or sample["iteration"] != index:
            raise Failure("Missing, duplicated or unordered measurement.")
        for key in METRICS:
            value = sample.get(key)
            if type(value) not in (int, float) or not math.isfinite(value):
                raise Failure(f"Missing/non-finite measurement: {key}.")
            if key != "residentDeltaBytes" and value < 0:
                raise Failure(f"Negative measurement: {key}.")
        counters = sample.get("counters")
        if not isinstance(counters, dict) or set(counters) != set(spec["counters"]):
            raise Failure("Missing or unexpected workload counters.")
        if any(type(value) is not int or value < 0 for value in counters.values()):
            raise Failure("Workload counters must be non-negative integers.")


def read_attachments(folder, expected):
    reports = {}
    for test in json.loads((folder / "manifest.json").read_text()):
        for attachment in test["attachments"]:
            name = attachment.get("suggestedHumanReadableName", "")
            if not name.startswith("plozz-performance-"):
                continue
            path = (folder / attachment["exportedFileName"]).resolve()
            if path.parent != folder.resolve():
                raise Failure("Attachment path escaped the run directory.")
            report = json.loads(path.read_text())
            scenario = report.get("scenario")
            if scenario not in expected or scenario in reports:
                raise Failure("Unexpected or duplicate scenario attachment.")
            validate_report(report, expected[scenario])
            reports[scenario] = report
    if set(reports) != set(expected):
        raise Failure(f"Incomplete performance evidence: expected {sorted(expected)}, got {sorted(reports)}.")
    return reports


def verify_summary(summary, count):
    fields = ("passedTests", "totalTestCount", "failedTests", "skippedTests", "expectedFailures")
    if not (all(type(summary.get(key)) is int for key in fields)
            and summary.get("result") == "Passed" and summary.get("passedTests") == count
            and summary.get("totalTestCount") == count
            and all(summary.get(key) == 0 for key in ("failedTests", "skippedTests", "expectedFailures"))
            and summary.get("testFailures") == []):
        raise Failure("XCTest did not pass exactly the selected tests, without skips or retries.")


def configure_scheme(tree):
    action = tree.getroot().find("TestAction")
    if action is None:
        raise Failure("Generated scheme has no TestAction.")
    action.set("buildConfiguration", "Debug")
    action.set("shouldUseLaunchSchemeArgsEnv", "NO")
    action.set("selectedDebuggerIdentifier", "")
    action.set("selectedLauncherIdentifier", "Xcode.IDEFoundation.Launcher.PosixSpawn")
    action.set("codeCoverageEnabled", "NO")
    old = action.find("EnvironmentVariables")
    if old is not None:
        action.remove(old)
    variables = ET.SubElement(action, "EnvironmentVariables")
    ET.SubElement(variables, "EnvironmentVariable", key="PLOZZ_PERFORMANCE", value="1", isEnabled="YES")
    return tree


def package_scheme(targets):
    root = ET.Element("Scheme", version="1.7")
    entries = ET.SubElement(ET.SubElement(root, "BuildAction", buildImplicitDependencies="YES"), "BuildActionEntries")
    tests = ET.SubElement(ET.SubElement(root, "TestAction"), "Testables")
    for target in sorted(targets):
        build = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="NO",
                              buildForProfiling="NO", buildForArchiving="NO", buildForAnalyzing="NO")
        test = ET.SubElement(tests, "TestableReference", skipped="NO")
        for parent in (build, test):
            ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary",
                          BlueprintIdentifier=target, BuildableName=target, BlueprintName=target,
                          ReferencedContainer="container:")
    return configure_scheme(ET.ElementTree(root))


def simulator_info(data, runtime_data, sim_id, platform):
    matches = [(runtime, device) for runtime, devices in data["devices"].items()
               for device in devices if device["udid"] == sim_id]
    if len(matches) != 1:
        raise Failure("The explicit UUID is not a local simulator; physical targets are prohibited.")
    runtime, device = matches[0]
    if not device.get("isAvailable") or not runtime.startswith(f"com.apple.CoreSimulator.SimRuntime.{platform}-"):
        raise Failure("Simulator is unavailable or does not match --platform.")
    runtimes = [row for row in runtime_data["runtimes"] if row["identifier"] == runtime]
    if len(runtimes) != 1 or not runtimes[0].get("buildversion") or not device.get("deviceTypeIdentifier"):
        raise Failure("Simulator runtime build/device type cannot be verified.")
    return {
        "runtime": runtime, "runtimeBuild": runtimes[0]["buildversion"],
        "deviceType": device["deviceTypeIdentifier"],
    }, device["state"]


def stop_owned(process):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass


class Lane:
    def __init__(self, root, args, fds):
        self.root, self.args, self.fds = root, args, fds
        self.output = root / ".build/performance/runs" / uuid.uuid4().hex
        self.output.mkdir(parents=True, mode=0o700)
        self.deadline = time.monotonic() + args.timeout
        self.env = dict(os.environ, GIT_CONFIG_PARAMETERS="'safe.bareRepository=all'", PYTHONDONTWRITEBYTECODE="1")
        self.booted = False
        self.record = {"schema": SCHEMA, "status": "failed", "evidenceKind": "simulator",
                       "scenarios": args.names, "simulatorID": args.sim_id, "reports": {}}
        self.sequence = 0
        print(f"Performance evidence: {self.output}", flush=True)

    def command(self, label, argv, timeout=120, check=True, cleanup=False):
        budget = timeout if cleanup else min(timeout, self.deadline - time.monotonic())
        if budget <= 0:
            raise Failure("Whole-run deadline reached; no automatic retry or cleanup of build outputs.")
        self.sequence += 1
        stem = f"{self.sequence:02}-{label}"
        print(f"  {label}", flush=True)
        write_json(self.output / f"{stem}.command.json", argv)
        with (self.output / f"{stem}.log").open("xb") as out, (self.output / f"{stem}.err").open("xb") as err:
            process = subprocess.Popen(argv, cwd=self.root, env=self.env, stdout=out, stderr=err,
                                       pass_fds=self.fds, start_new_session=True)
            try:
                status = process.wait(timeout=budget)
            except BaseException:
                stop_owned(process)
                raise
        text = (self.output / f"{stem}.log").read_text()
        if check and status:
            raise Failure(f"{label} failed ({status}); inspect {stem}.log and .err.")
        return status, text

    def fingerprint(self, label):
        _, tracked = self.command(label + "-files", ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"])
        hashes = {}
        for name in sorted(set(filter(None, tracked.split("\0")))):
            path = self.root / name
            if name.startswith(("Sources/", "Tests/", "tools/", "Config/", "App/", "Vendor/")) or name in ("Package.swift", "Package.resolved", "project.yml"):
                hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "deleted"
        return hashes

    def run_group(self, names, package_args, hosted):
        project = self.root / "Plozz.xcodeproj"
        saved = self.output / "Plozz.xcodeproj"
        target = "PlozzFocusTests" if self.args.platform == "tvOS" else "PlozziOSPresentationTests"
        scheme_name = "_PlozzPerformance_" + self.output.name + ("_ui" if hosted else "_core")
        if hosted:
            source = project / "xcshareddata/xcschemes" / f"{target}.xcscheme"
            tree = configure_scheme(ET.parse(source))
            scheme = source.with_name(scheme_name + ".xcscheme")
        else:
            targets = {SCENARIOS[name]["target"] for name in names}
            tree = package_scheme(targets)
            scheme = self.root / ".swiftpm/xcode/xcshareddata/xcschemes" / f"{scheme_name}.xcscheme"
        folder = self.output / ("ui" if hosted else "core")
        folder.mkdir()
        try:
            scheme.parent.mkdir(parents=True, exist_ok=True)
            with scheme.open("xb") as stream:
                tree.write(stream, encoding="utf-8", xml_declaration=True)
            if not hosted and project.exists():
                if project.is_symlink():
                    raise Failure("Refusing to move a symlinked project.")
                project.rename(saved)
            selectors = [f"-only-testing:{target if hosted else SCENARIOS[name]['target']}/{SCENARIOS[name]['test']}" for name in names]
            command = [
                "xcodebuild", *(["-project", str(project)] if hosted else []), "-scheme", scheme_name,
                "-configuration", "Debug", "-destination", f"platform={self.args.platform} Simulator,id={self.args.sim_id}",
                "-parallel-testing-enabled", "NO", "-enableCodeCoverage", "NO",
                "-enableAddressSanitizer", "NO", "-enableThreadSanitizer", "NO",
                "-enableUndefinedBehaviorSanitizer", "NO",
                "-derivedDataPath", str(self.root / ".build/performance-derived-data" / self.args.platform / folder.name),
                *package_args, *selectors, *FLAGS,
            ]
            self.command(folder.name + "-build", [*command, "build-for-testing", "-resultBundlePath", str(folder / "Build.xcresult")], self.args.timeout)
            status, _ = self.command(folder.name + "-test", [
                *command, "test-without-building", "-collect-test-diagnostics", "never",
                "-resultBundlePath", str(folder / "Test.xcresult"),
            ], self.args.timeout, check=False)
            _, raw = self.command(folder.name + "-summary", [
                "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(folder / "Test.xcresult"),
            ])
            summary = json.loads(raw)
            write_json(folder / "summary.json", summary)
            verify_summary(summary, len(names))
            if status:
                raise Failure("A passing summary cannot override xcodebuild's failed exit.")
            self.command(folder.name + "-attachments", [
                "xcrun", "xcresulttool", "export", "attachments", "--path", str(folder / "Test.xcresult"),
                "--output-path", str(folder / "attachments"),
            ])
            return read_attachments(folder / "attachments", expected_reports(names))
        finally:
            signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
            handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in signals}
            try:
                try:
                    if scheme.exists():
                        scheme.rename(folder / scheme.name)
                finally:
                    if saved.exists():
                        if os.path.lexists(project):
                            raise Failure(f"Project restoration conflict; original retained at {saved}.")
                        saved.rename(project)
            finally:
                for sig, handler in handlers.items():
                    signal.signal(sig, handler)

    def execute(self):
        try:
            self.command("architecture", [sys.executable, "tools/arch-guard.py"])
            self.command("test-hygiene", [sys.executable, "tools/test-hygiene.py"])
            _, devices = self.command("simulators", ["xcrun", "simctl", "list", "devices", "-j"])
            _, runtimes = self.command("runtimes", ["xcrun", "simctl", "list", "runtimes", "-j"])
            simulator, state = simulator_info(json.loads(devices), json.loads(runtimes), self.args.sim_id, self.args.platform)
            if state not in ("Booted", "Shutdown"):
                raise Failure("Simulator must be stably Booted or Shutdown.")
            self.booted = state == "Shutdown"
            self.command("simulator-start", ["xcrun", "simctl", "bootstatus", self.args.sim_id, "-b"], 300)
            self.command("generate-project", ["tools/generate-project.sh"])
            _, options = self.command("package-options", [
                "/bin/bash", "-ec", 'source tools/lib/swift-package-storage.sh; configure_plozz_package_resolution "$1"; '
                'printf "%s\\0" "${PACKAGE_RESOLUTION_ARGS[@]}"', "performance",
                str(self.root / ".build/package-workspaces/performance"),
            ])
            package_args = options.rstrip("\0").split("\0")
            if not package_args or package_args[0] != "-clonedSourcePackagesDirPath":
                raise Failure("Invalid package workspace arguments.")
            _, head = self.command("source-head", ["git", "rev-parse", "HEAD"])
            sources = self.fingerprint("before")
            fixture_paths = {name for name in sources if name.startswith("Tests/")}
            fixtures = {name: sources[name] for name in sorted(fixture_paths)}
            environment = dict(simulator, platform=self.args.platform, architecture=os.uname().machine,
                               flags=FLAGS, runnerHash=sources["tools/performance.py"])
            for key, command in {
                "xcode": ["xcodebuild", "-version"],
                "sdk": ["xcrun", "--sdk", "appletvsimulator" if self.args.platform == "tvOS" else "iphonesimulator", "--show-sdk-version"],
                "macOS": ["sw_vers", "-productVersion"],
                "hardware": ["sysctl", "-n", "hw.model", "hw.memsize", "hw.logicalcpu"],
            }.items():
                _, value = self.command(key, command)
                environment[key] = value.strip()
            self.record.update(environment=environment, source={"head": head.strip(), "files": sources},
                               fixtures=fixtures, startedAt=time.time(), hostLoadStart=list(os.getloadavg()))
            write_json(self.output / "result.json", self.record)
            for hosted in (False, True):
                names = [name for name in self.args.names if (SCENARIOS[name]["suite"] == "ui") == hosted]
                if names:
                    self.record["reports"].update(self.run_group(names, package_args, hosted))
            if sources != self.fingerprint("after"):
                raise Failure("Source changed during measurement; mixed-source evidence is invalid.")
            self.record["status"] = "passed"
        except (Failure, OSError, ValueError, subprocess.TimeoutExpired, ET.ParseError) as error:
            self.record["error"] = str(error)
            raise
        finally:
            try:
                if self.booted:
                    self.command("simulator-shutdown", ["xcrun", "simctl", "shutdown", self.args.sim_id], 60, cleanup=True)
            except (Failure, OSError, subprocess.TimeoutExpired) as error:
                self.record.update(status="failed", error=f"Owned simulator cleanup failed: {error}")
                raise
            finally:
                self.record.update(finishedAt=time.time(), hostLoadEnd=list(os.getloadavg()))
                write_json(self.output / "result.json", self.record)
        print(f"Measured {len(self.record['reports'])} scenarios. Compare result.json with a separate baseline.", flush=True)


def read_run(path):
    path = path / "result.json" if path.is_dir() else path
    data = json.loads(path.read_text())
    if data.get("schema") != SCHEMA or data.get("status") != "passed" or data.get("evidenceKind") != "simulator":
        raise Failure("Comparison requires complete passing simulator runs.")
    if not isinstance(data.get("scenarios"), list) or not data["scenarios"]:
        raise Failure("Missing scenario selection.")
    names = select(None, data["scenarios"])
    expected = expected_reports(names)
    if set(data["reports"]) != set(expected):
        raise Failure("Run is missing scenario evidence.")
    for name, report in data["reports"].items():
        if report.get("scenario") != name:
            raise Failure("Mismatched report identity.")
        validate_report(report, expected[name])
    for key in ("environment", "fixtures", "source"):
        if not isinstance(data.get(key), dict) or not data[key]:
            raise Failure(f"Missing run provenance: {key}.")
    for key in ("runtime", "runtimeBuild", "deviceType", "platform", "architecture",
                "runnerHash", "xcode", "sdk", "macOS", "hardware"):
        if not isinstance(data["environment"].get(key), str) or not data["environment"][key]:
            raise Failure(f"Missing environment identity: {key}.")
    if not isinstance(data["environment"].get("flags"), list) or not data["environment"]["flags"]:
        raise Failure("Missing compilation flags.")
    if not re.fullmatch(r"[0-9a-f]{40,64}", data["source"].get("head", "")) or not data["source"].get("files"):
        raise Failure("Missing exact source identity.")
    return data


def summarize(data):
    rows = {}
    for name, report in data["reports"].items():
        samples = report["samples"]
        metrics = {}
        for key in METRICS:
            values = [sample[key] for sample in samples]
            median = statistics.median(values)
            metrics[key] = {"median": median, "mad": statistics.median(abs(v - median) for v in values)}
        rows[name] = {"metrics": metrics, "counters": {
            key: {"min": min(s["counters"][key] for s in samples),
                  "max": max(s["counters"][key] for s in samples)}
            for key in samples[0]["counters"]
        }}
    return {"schema": SCHEMA, "sourceHead": data["source"]["head"], "environment": data["environment"],
            "evidenceKind": "simulator", "scenarios": rows}


def compare(before, after, tolerance):
    if not math.isfinite(tolerance) or not 0 <= tolerance <= 100:
        raise Failure("Regression tolerance must be between 0 and 100 percent.")
    for key in ("environment", "fixtures", "scenarios"):
        if before[key] != after[key]:
            raise Failure(f"Incompatible {key}; capture a separate baseline, do not compare unlike workloads.")
    rows = []
    for name, spec in expected_reports(before["scenarios"]).items():
        a, b = before["reports"][name]["samples"], after["reports"][name]["samples"]
        for metric in METRICS:
            av, bv = ([s[metric] for s in samples] for samples in (a, b))
            am, bm = statistics.median(av), statistics.median(bv)
            mad = max(statistics.median(abs(v - m) for v in values) for values, m in ((av, am), (bv, bm)))
            gated = metric in spec.get("timing", ["wallMilliseconds", "cpuMilliseconds"])
            allowance = max(abs(am) * tolerance / 100, 3 * mad, 1.0)
            noisy = gated and mad > max(abs(am) * 0.20, 1.0)
            verdict = ("inconclusive" if noisy else "regression" if bm - am > allowance else "within-budget") if gated else "informational"
            rows.append({"scenario": name, "metric": metric, "baselineMedian": am, "candidateMedian": bm,
                         "delta": bm - am, "allowance": allowance if gated else None, "verdict": verdict})
        for counter in spec["counters"]:
            am, bm = (statistics.median(s["counters"][counter] for s in samples) for samples in (a, b))
            rows.append({"scenario": name, "metric": counter, "baselineMedian": am, "candidateMedian": bm,
                         "delta": bm - am, "verdict": "work-count"})
    verdict = "regression" if any(r["verdict"] == "regression" for r in rows) else (
        "inconclusive" if any(r["verdict"] == "inconclusive" for r in rows) else "within-budget")
    return {"schema": SCHEMA, "verdict": verdict, "tolerancePercent": tolerance, "rows": rows,
            "note": "Within-budget is not proof of improvement. Memory snapshots and simulator timings are not hardware performance."}


def interrupted(signum, _frame):
    raise Failure(f"Interrupted ({signum}); partial evidence retained.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="operation", required=True)
    commands.add_parser("list", help="Print the machine-readable scenario inventory.")
    report_command = commands.add_parser("report", help="Print compact metric/counter summaries without source-file manifests.")
    report_command.add_argument("run", type=Path)
    run = commands.add_parser("run", help="Run bounded optimized tests on an explicit owned simulator.")
    run.add_argument("--platform", choices=("tvOS", "iOS"), required=True)
    run.add_argument("--sim-id", required=True)
    run.add_argument("--suite", choices=("core", "ui", "matrix", "all"))
    run.add_argument("--scenario", nargs="+")
    run.add_argument("--timeout", type=int, default=2400)
    comparison = commands.add_parser("compare", help="Compare saved runs; never updates a baseline.")
    comparison.add_argument("baseline", type=Path)
    comparison.add_argument("candidate", type=Path)
    comparison.add_argument("--tolerance-percent", type=float, default=15)
    args = parser.parse_args(argv)
    if args.operation == "list":
        print(json.dumps(SCENARIOS, indent=2))
        return 0
    if args.operation == "report":
        print(json.dumps(summarize(read_run(args.run)), indent=2, allow_nan=False))
        return 0
    if args.operation == "compare":
        result = compare(read_run(args.baseline), read_run(args.candidate), args.tolerance_percent)
        output = ROOT / ".build/performance/comparisons" / (uuid.uuid4().hex + ".json")
        output.parent.mkdir(parents=True, exist_ok=True)
        write_json(output, dict(result, baseline=str(args.baseline.resolve()), candidate=str(args.candidate.resolve())))
        print(f"Comparison: {result['verdict']}; evidence: {output}")
        for row in result["rows"]:
            print(f"{row['scenario']} {row['metric']}: {row['baselineMedian']:.3f} -> {row['candidateMedian']:.3f} [{row['verdict']}]")
        return {"within-budget": 0, "regression": 1, "inconclusive": 2}[result["verdict"]]
    args.names = select(args.suite, args.scenario)
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", args.sim_id):
        raise Failure("--sim-id must be an explicit owned simulator UUID.")
    if not 60 <= args.timeout <= 7200:
        raise Failure("--timeout must be between 60 and 7200 seconds.")
    if Path.cwd().resolve() != ROOT:
        raise Failure("Run from the active Plozz checkout root.")
    if not any(key.startswith("APPLE_BUILD_LEASE_") for key in os.environ):
        os.execv("/bin/bash", ["/bin/bash", str(ROOT / "tools/with-apple-build-lease.sh"),
                 "plozz/performance", "--", sys.executable, str(Path(__file__).resolve()),
                 *(sys.argv[1:] if argv is None else argv)])
    fds = load_module(ROOT / "tools/run-bounded.py").inherited_lease_fds()
    if not fds or os.environ.get("APPLE_BUILD_LEASE_MODE") != "shared":
        raise Failure("An authenticated shared build lease is required.")
    folder = ROOT / ".build/performance"
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / "lane.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
        handlers = {sig: signal.signal(sig, interrupted) for sig in signals}
        try:
            Lane(ROOT, args, fds).execute()
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (Failure, OSError, ValueError, KeyError, subprocess.TimeoutExpired, ET.ParseError) as error:
        print(f"performance: {error}", file=sys.stderr)
        sys.exit(1)
