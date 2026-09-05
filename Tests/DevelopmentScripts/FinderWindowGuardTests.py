"""Exercise Finder-window guard process ordering without compiling or reading GUI."""

import datetime
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
RUN_ROOT = PROJECT_ROOT / ".artifacts/scratch/tests" / (
    datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    + f"-finder-window-guard-{os.getpid()}"
)

HELPER_STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["ECMENU_SCRIPT_TEST_DIRECTORY"])
options = json.loads((root / "options.json").read_text())

def event(value):
    with (root / "events.log").open("a") as stream:
        stream.write(value + "\n")

operation = sys.argv[1]
event(operation)
if operation == "capture":
    if options.get("capture_exit", 0):
        print("FAKE CAPTURE FAILURE", file=sys.stderr)
        sys.exit(options["capture_exit"])
    snapshot = {"state": "skipped" if options.get("no_gui") else "captured"}
    Path(sys.argv[2]).write_text(json.dumps(snapshot))
    print("FAKE CAPTURE COMPLETE")
elif operation == "verify":
    before = Path(sys.argv[2])
    after = Path(sys.argv[3])
    assert before != after
    snapshot = json.loads(before.read_text())
    after.write_text(json.dumps(snapshot))
    if options.get("verify_exit", 0):
        print("FAKE WINDOW DIFFERENCE")
        sys.exit(options["verify_exit"])
    if snapshot["state"] == "skipped":
        print("SKIPPED: no GUI session; Finder windows were not compared.")
    else:
        print("FAKE WINDOW VERIFICATION PASSED")
else:
    raise AssertionError(operation)
'''

XCRUN_STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import sys

root = Path(os.environ["ECMENU_SCRIPT_TEST_DIRECTORY"])
options = json.loads((root / "options.json").read_text())
output = Path(sys.argv[sys.argv.index("-o") + 1])
helpers = {
    "FinderWindowCheck": ("compile", "fake-helper.py"),
    "UserFocusRestorer": ("compile focus", "fake-focus-helper.py"),
}
event, helper = helpers[output.name]
with (root / "events.log").open("a") as stream:
    stream.write(event + "\n")
assert sys.argv[1] == "swiftc"
if options.get("compile_exit", 0):
    print("FAKE COMPILER FAILURE", file=sys.stderr)
    sys.exit(options["compile_exit"])
assert output.is_relative_to(root)
shutil.copy2(root / helper, output)
'''

FOCUS_HELPER_STUB = r'''#!/usr/bin/env python3
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["ECMENU_SCRIPT_TEST_DIRECTORY"])

def event(value):
    with (root / "events.log").open("a") as stream:
        stream.write(value + "\n")

operation = sys.argv[1]
if operation == "capture":
    event("focus capture")
    print("fixture-front-application")
elif operation == "launch":
    event("focus launch")
    os.setsid()
    (root / "focus-child-session.pid").write_text(str(os.getpid()))
    os.execvp(sys.argv[2], sys.argv[2:])
elif operation == "restore":
    assert sys.argv[2] == "fixture-front-application"
    event("focus restore start")
    (root / "restore-started").touch()
    # Signal disposition is inherited from the production wrapper. This fake
    # must not install its own signal handler or hide a wrapper regression.
    while not (root / "allow-restore").exists():
        time.sleep(0.01)
    event("focus restore complete")
else:
    raise AssertionError(operation)
'''

CHILD_STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

root = Path(os.environ["ECMENU_SCRIPT_TEST_DIRECTORY"])
options = json.loads((root / "options.json").read_text())
mode = sys.argv[1]

def event(value):
    with (root / "events.log").open("a") as stream:
        stream.write(value + "\n")

def record_session():
    with (root / "sessions.jsonl").open("a") as stream:
        stream.write(json.dumps(os.environ.get("ECMENU_FINDER_WINDOW_SESSION")) + "\n")

record_session()
if mode == "nested":
    event("child nested start")
    result = subprocess.run([
        "/bin/zsh", str(root / "scripts/lib/with-finder-windows-checked.sh"),
        sys.executable, __file__, "leaf",
    ], check=False)
    event("child nested complete")
    sys.exit(result.returncode)
if mode == "wait-for-term":
    def terminate(signal_number, frame):
        event("child TERM")
        (root / "cleanup-started").touch()
        while not (root / "allow-cleanup").exists():
            time.sleep(0.01)
        event("child cleanup complete")
        sys.exit(23)

    signal.signal(signal.SIGTERM, terminate)
    event("child waiting")
    (root / "child-ready").touch()
    while True:
        signal.pause()

assert mode in ["normal", "leaf"]
event("child " + mode)
(root / "arguments.json").write_text(json.dumps(sys.argv[2:]))
sys.exit(options.get("child_exit", 0))
'''


class FinderWindowGuardTests(unittest.TestCase):
    def setUp(self):
        self.directory = RUN_ROOT / self._testMethodName
        library = self.directory / "scripts/lib"
        library.mkdir(parents=True)
        for name in [
            "finder-windows.sh", "with-finder-windows-checked.sh",
            "user-focus.sh", "with-user-focus-restored.sh",
        ]:
            shutil.copy2(PROJECT_ROOT / "scripts/lib" / name, library)
        (self.directory / "bin").mkdir()
        for path, content in [
            (self.directory / "fake-helper.py", HELPER_STUB),
            (self.directory / "fake-focus-helper.py", FOCUS_HELPER_STUB),
            (self.directory / "bin/xcrun", XCRUN_STUB),
            (self.directory / "child.py", CHILD_STUB),
        ]:
            path.write_text(content)
            path.chmod(0o755)
        self.wrapper = library / "with-finder-windows-checked.sh"
        self.child = self.directory / "child.py"

    def environment(self, options, existing_session=None):
        (self.directory / "options.json").write_text(json.dumps(options))
        environment = os.environ | {
            "PATH": str(self.directory / "bin") + os.pathsep + os.environ["PATH"],
            "ECMENU_SCRIPT_TEST_DIRECTORY": str(self.directory),
        }
        # test.sh itself owns a real outer session; each fixture must exercise
        # its own guard unless a test explicitly requests the nested path.
        environment.pop("ECMENU_FINDER_WINDOW_SESSION", None)
        environment.pop("ECMENU_USER_FOCUS_SESSION", None)
        if existing_session is not None:
            environment["ECMENU_FINDER_WINDOW_SESSION"] = existing_session
        return environment

    @property
    def events(self):
        path = self.directory / "events.log"
        return path.read_text().splitlines() if path.exists() else []

    @property
    def sessions(self):
        return [json.loads(line) for line in
                (self.directory / "sessions.jsonl").read_text().splitlines()]

    def save_output(self, result):
        (self.directory / "stdout.log").write_text(result.stdout)
        (self.directory / "stderr.log").write_text(result.stderr)
        return result

    def run_guard(self, options=None, mode="normal", arguments=(), existing_session=None):
        result = subprocess.run(
            ["/bin/zsh", str(self.wrapper), str(self.child), mode, *arguments],
            env=self.environment(options or {}, existing_session),
            capture_output=True, text=True, timeout=10,
        )
        return self.save_output(result)

    def testSuccessCapturesBeforeChildAndVerifiesAfterIt(self):
        arguments = ["a file with spaces", "$(not-a-command)", "*.png"]
        result = self.run_guard(arguments=arguments)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events, ["compile", "capture", "child normal", "verify"])
        self.assertIn("FAKE WINDOW VERIFICATION PASSED", result.stdout)
        self.assertEqual(json.loads((self.directory / "arguments.json").read_text()), arguments)
        self.assertRegex(self.sessions[0], r"^\d{8}-\d{6}-finder-windows-\d+$")

    def testChildFailureStillVerifiesAndPreservesItsExitCode(self):
        result = self.run_guard({"child_exit": 23})
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(self.events, ["compile", "capture", "child normal", "verify"])

    def testWindowDifferenceFailsAnOtherwiseSuccessfulChild(self):
        result = self.run_guard({"verify_exit": 42})
        self.assertEqual(result.returncode, 42)
        self.assertEqual(self.events, ["compile", "capture", "child normal", "verify"])
        self.assertIn("Finder window preservation check failed", result.stderr)
        self.assertIn("FAKE WINDOW DIFFERENCE", result.stderr)

    def testWindowDifferenceDoesNotReplaceOriginalChildFailure(self):
        result = self.run_guard({"child_exit": 23, "verify_exit": 42})
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.events[-1], "verify")
        self.assertIn("FAKE WINDOW DIFFERENCE", result.stderr)

    def testCaptureFailureDoesNotLaunchChildOrVerify(self):
        result = self.run_guard({"capture_exit": 71})
        self.assertEqual(result.returncode, 71)
        self.assertEqual(self.events, ["compile", "capture"])
        self.assertIn("Could not snapshot Finder windows", result.stderr)

    def testBuildFailureDoesNotCaptureOrLaunchChild(self):
        result = self.run_guard({"compile_exit": 65})
        self.assertEqual(result.returncode, 65)
        self.assertEqual(self.events, ["compile"])
        self.assertIn("FAKE COMPILER FAILURE", result.stderr)

    def testNestedGuardCapturesAndVerifiesOnlyOnce(self):
        result = self.run_guard(mode="nested")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events, [
            "compile", "capture", "child nested start", "child leaf",
            "child nested complete", "verify",
        ])
        self.assertEqual(len(self.sessions), 2)
        self.assertEqual(self.sessions[0], self.sessions[1])

    def testExistingSessionBypassesCaptureAndPreservesChildStatus(self):
        result = self.run_guard({"child_exit": 23}, existing_session="outer-test-session")
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.events, ["child normal"])
        self.assertEqual(self.sessions, ["outer-test-session"])

    def testWindowGuardCannotStartInsideAnExistingFocusSession(self):
        environment = self.environment({})
        environment["ECMENU_USER_FOCUS_SESSION"] = "outer-focus-session"
        result = self.save_output(subprocess.run(
            ["/bin/zsh", str(self.wrapper), str(self.child), "normal"],
            env=environment, capture_output=True, text=True, timeout=10,
        ))
        self.assertEqual(result.returncode, 64)
        self.assertEqual(self.events, [])
        self.assertIn("must start outside the focus-restoration session", result.stderr)

    def testNoGUISkipIsReportedAndChildStillRuns(self):
        result = self.run_guard({"no_gui": True})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events, ["compile", "capture", "child normal", "verify"])
        self.assertIn("SKIPPED: no GUI session; Finder windows were not compared.", result.stdout)
        self.assertNotIn("FAKE WINDOW VERIFICATION PASSED", result.stdout)

    def testLibraryReexecutionWrapsEntryPointOnce(self):
        entrypoint = self.directory / "scripts/entrypoint.sh"
        entrypoint.write_text('''#!/bin/zsh
set -euo pipefail
source "${0:A:h}/lib/finder-windows.sh"
ecmenu_reexec_checking_finder_windows "$0" "$@"
exec "$ECMENU_SCRIPT_TEST_DIRECTORY/child.py" normal "$@"
''')
        entrypoint.chmod(0o755)
        result = self.save_output(subprocess.run(
            ["/bin/zsh", str(entrypoint), "entry point argument"],
            env=self.environment({}), capture_output=True, text=True, timeout=10,
        ))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events, ["compile", "capture", "child normal", "verify"])
        self.assertEqual(json.loads((self.directory / "arguments.json").read_text()),
                         ["entry point argument"])

    def wait_for_marker(self, path, process):
        deadline = time.monotonic() + 5
        while not path.exists():
            if process.poll() is not None:
                stdout, stderr = process.communicate()
                self.fail(f"Guard exited before {path.name}: {stdout}\n{stderr}")
            if time.monotonic() >= deadline:
                self.fail(f"Timed out waiting for {path.name}; events: {self.events}")
            time.sleep(0.01)

    def clean_process_group(self, process):
        # Clean both dedicated fixture sessions if a failed assertion left the
        # inner child waiting. No process group outside this fixture is used.
        process_groups = [process.pid]
        child_session = self.directory / "focus-child-session.pid"
        if child_session.exists():
            process_groups.append(int(child_session.read_text()))
        for process_group in process_groups:
            try:
                os.killpg(process_group, signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.communicate(timeout=5)

    def testTERMWaitsForChildCleanupThenVerifiesAndReturns143(self):
        process = subprocess.Popen(
            ["/bin/zsh", str(self.wrapper), str(self.child), "wait-for-term"],
            env=self.environment({}), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True,
        )
        self.addCleanup(self.clean_process_group, process)
        self.wait_for_marker(self.directory / "child-ready", process)
        process.send_signal(signal.SIGTERM)
        self.wait_for_marker(self.directory / "cleanup-started", process)
        self.assertIsNone(process.poll())
        self.assertNotIn("verify", self.events)
        (self.directory / "allow-cleanup").touch()
        stdout, stderr = process.communicate(timeout=5)
        self.save_output(subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr))
        self.assertEqual(process.returncode, 143, stderr)
        self.assertEqual(self.events, [
            "compile", "capture", "child waiting", "child TERM",
            "child cleanup complete", "verify",
        ])

    def testGroupTERMWaitsForChildAndFocusCleanupBeforeWindowVerification(self):
        entrypoint = self.directory / "scripts/two-guards.sh"
        entrypoint.write_text('''#!/bin/zsh
set -euo pipefail
source "${0:A:h}/lib/finder-windows.sh"
source "${0:A:h}/lib/user-focus.sh"
ecmenu_reexec_checking_finder_windows "$0" "$@"
ecmenu_reexec_preserving_user_focus "$0" "$@"
exec "$ECMENU_SCRIPT_TEST_DIRECTORY/child.py" wait-for-term
''')
        entrypoint.chmod(0o755)
        process = subprocess.Popen(
            ["/bin/zsh", str(entrypoint)], env=self.environment({}),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True,
        )
        self.addCleanup(self.clean_process_group, process)
        self.wait_for_marker(self.directory / "child-ready", process)
        child_session = int((self.directory / "focus-child-session.pid").read_text())
        self.assertNotEqual(child_session, process.pid)
        self.assertEqual(os.getsid(child_session), child_session)

        # Both wrappers receive this signal; the outer wrapper also forwards it
        # to the inner wrapper, which must keep waiting for its child cleanup.
        os.killpg(process.pid, signal.SIGTERM)
        self.wait_for_marker(self.directory / "cleanup-started", process)
        self.assertNotIn("verify", self.events)
        self.assertNotIn("focus restore start", self.events)
        (self.directory / "allow-cleanup").touch()

        self.wait_for_marker(self.directory / "restore-started", process)
        self.assertNotIn("verify", self.events)
        self.assertIsNone(process.poll())
        os.killpg(process.pid, signal.SIGTERM)
        time.sleep(0.05)
        self.assertIsNone(process.poll())
        self.assertNotIn("verify", self.events)
        (self.directory / "allow-restore").touch()

        stdout, stderr = process.communicate(timeout=5)
        self.save_output(subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr))
        self.assertEqual(process.returncode, 143, stderr)
        self.assertEqual(self.events, [
            "compile", "capture", "compile focus", "focus capture", "focus launch",
            "child waiting", "child TERM", "child cleanup complete",
            "focus restore start", "focus restore complete", "verify",
        ])


if __name__ == "__main__":
    unittest.main()
