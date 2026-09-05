"""Exercise the production switch script with isolated external commands."""

import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
RUN_ROOT = PROJECT_ROOT / ".artifacts/scratch/tests" / (
    datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    + f"-environment-switch-{os.getpid()}"
)
DEBUG = "com.axiomace.ecmenu.debug.finderext"
RELEASE = "com.axiomace.ecmenu.finderext"

COMMAND_STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import signal
import sys

root = Path(os.environ["ECMENU_SCRIPT_TEST_DIRECTORY"])
mode = os.environ["ECMENU_SCRIPT_TEST_FAILURE"]
state_path = root / "states.json"
states = json.loads(state_path.read_text())
debug = "com.axiomace.ecmenu.debug.finderext"
release = "com.axiomace.ecmenu.finderext"

def event(value):
    with (root / "events.log").open("a") as stream:
        stream.write(value + "\n")

command = Path(sys.argv[0]).name
if command == "xcodebuild":
    if "-showBuildSettings" in sys.argv:
        event("build settings")
        print("Build settings for action build and target ECMenu:")
        print("    FULL_PRODUCT_NAME = ECMenu(Debug).app")
    else:
        event("build")
    sys.exit(0)
if command == "codesign":
    if "--verify" in sys.argv:
        event("verify signature")
        sys.exit(1 if mode == "signature" else 0)
    identifier = debug if sys.argv[-1].endswith(".appex") else debug.removesuffix(".finderext")
    print("Identifier=" + identifier, file=sys.stderr)
    print("TeamIdentifier=FixtureTeam", file=sys.stderr)
    sys.exit(0)

if Path(sys.argv[0]).name == "run-debug.sh":
    if sys.argv[1:] == ["--build-only"]:
        event("prepare")
        sys.exit(1 if mode == "prepare" else 0)
    assert sys.argv[1:] == ["--no-build", "--refresh-finder"]
    event("activate")
    assert states[release] != "enabled", "Both identities would be enabled"
    states[debug] = "enabled"
    state_path.write_text(json.dumps(states))
    if mode == "signal":
        os.kill(os.getppid(), signal.SIGTERM)
        sys.exit(143)
    sys.exit(1 if mode in ["activate", "rollback"] else 0)

arguments = sys.argv[1:]
identifier = arguments[arguments.index("-i") + 1]
name = "debug" if identifier == debug else "release"
if "-m" in arguments:
    event("query " + name)
    if mode == "query" and identifier == release:
        sys.exit(2)
    state = states[identifier]
    if state != "unregistered":
        marker = "+" if state == "enabled" else "-"
        print(marker + " " + identifier + "(1.0.0)")
        print("    Path = /fixture/" + name + ".appex")
elif "-e" in arguments:
    election = arguments[arguments.index("-e") + 1]
    event("set " + name + " " + election)
    if mode == "rollback" and identifier == debug and election == "ignore":
        sys.exit(2)
    states[identifier] = "enabled" if election == "use" else "disabled"
    state_path.write_text(json.dumps(states))
else:
    raise AssertionError(arguments)
'''


class EnvironmentSwitchTests(unittest.TestCase):
    def setUp(self):
        self.directory = RUN_ROOT / self._testMethodName
        script_directory = self.directory / "scripts"
        library_directory = script_directory / "lib"
        library_directory.mkdir(parents=True)
        for filename in [
            "product-paths.sh", "user-focus.sh", "code-signing.sh",
            "finder-environment.sh",
        ]:
            shutil.copy2(PROJECT_ROOT / "scripts/lib" / filename, library_directory)
        shutil.copy2(PROJECT_ROOT / "scripts/activate-environment.sh", script_directory)
        (library_directory / "process-lifecycle.sh").write_text(
            'restart_gui_launch_service() {\n'
            '    print "restart Finder" >>"$ECMENU_SCRIPT_TEST_DIRECTORY/events.log"\n'
            '}\n'
        )
        (self.directory / "bin").mkdir()
        (self.directory / "bin/python3").symlink_to(sys.executable)
        for executable in [
            script_directory / "run-debug.sh", self.directory / "bin/pluginkit",
            self.directory / "bin/xcodebuild", self.directory / "bin/codesign",
        ]:
            executable.write_text(COMMAND_STUB)
            executable.chmod(0o755)
        self.initial_states = {DEBUG: "disabled", RELEASE: "enabled"}

    def run_switch(self, failure="", command=None):
        (self.directory / "states.json").write_text(json.dumps(self.initial_states))
        environment = os.environ | {
            "PATH": str(self.directory / "bin") + os.pathsep + "/usr/bin:/bin:/usr/sbin:/sbin",
            "ECMENU_USER_FOCUS_SESSION": "isolated-script-tests",
            "ECMENU_SCRIPT_TEST_DIRECTORY": str(self.directory),
            "ECMENU_SCRIPT_TEST_FAILURE": failure,
        }
        result = subprocess.run(
            command or ["/bin/zsh", str(self.directory / "scripts/activate-environment.sh"), "debug"],
            env=environment, capture_output=True, text=True, timeout=15,
        )
        (self.directory / "stdout.log").write_text(result.stdout)
        (self.directory / "stderr.log").write_text(result.stderr)
        self.events = (self.directory / "events.log").read_text().splitlines()
        self.states = json.loads((self.directory / "states.json").read_text())
        return result

    def testPreparationFailurePreservesWorkingEnvironment(self):
        result = self.run_switch("prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.states, self.initial_states)
        self.assertEqual(self.events, ["prepare"])

    def testStateQueryFailureDoesNotBeginSwitch(self):
        result = self.run_switch("query")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.states, self.initial_states)
        self.assertFalse(any(event.startswith("set ") for event in self.events))
        self.assertNotIn("activate", self.events)

    def testActivationFailureRestoresPreviousStatesInSafeOrder(self):
        result = self.run_switch("activate")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.states, self.initial_states)
        self.assertLess(self.events.index("prepare"), self.events.index("set release ignore"))
        self.assertLess(self.events.index("set debug ignore"), self.events.index("set release use"))
        self.assertEqual(self.events[-1], "restart Finder")

    def testSignalRestoresPreviousStates(self):
        result = self.run_switch("signal")
        self.assertEqual(result.returncode, 143)
        self.assertEqual(self.states, self.initial_states)

    def testSameIdentityActivationFailurePreservesEnablement(self):
        self.initial_states = {DEBUG: "enabled", RELEASE: "disabled"}
        result = self.run_switch("activate")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.states, self.initial_states)

    def testPreviouslyUnregisteredTargetIsDisabledAfterFailure(self):
        self.initial_states[DEBUG] = "unregistered"
        result = self.run_switch("activate")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.states, {DEBUG: "disabled", RELEASE: "enabled"})

    def testRollbackFailureDoesNotEnableSecondIdentity(self):
        result = self.run_switch("rollback")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("set release use", self.events)
        self.assertEqual(self.states, {DEBUG: "enabled", RELEASE: "disabled"})
        self.assertIn("Could not restore", result.stderr)

    def testSuccessKeepsTargetEnabled(self):
        result = self.run_switch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.states, {DEBUG: "enabled", RELEASE: "disabled"})
        self.assertNotIn("set release use", self.events)
        self.assertNotIn("restart Finder", self.events)

    def run_build_only(self, failure=""):
        script = self.directory / "scripts/run-debug.sh"
        shutil.copy2(PROJECT_ROOT / "scripts/run-debug.sh", script)
        with (self.directory / "scripts/lib/product-paths.sh").open("a") as stream:
            stream.write('''
ecmenu_resolve_product_paths() {
    ECMENU_PRODUCT_APP_PATH="$project_root/ECMenu(Debug).app"
    ECMENU_PRODUCT_EXTENSION_PATH="$ECMENU_PRODUCT_APP_PATH/Contents/PlugIns/ECMenuFinderExtension.appex"
    ECMENU_PRODUCT_MAIN_EXECUTABLE_PATH="$ECMENU_PRODUCT_APP_PATH/Contents/MacOS/ECMenu(Debug)"
    ECMENU_PRODUCT_EXTENSION_EXECUTABLE_PATH="$ECMENU_PRODUCT_EXTENSION_PATH/Contents/MacOS/ECMenuFinderExtension"
    ECMENU_PRODUCT_APPLICATION_BUNDLE_IDENTIFIER=com.axiomace.ecmenu.debug
    ECMENU_PRODUCT_EXTENSION_BUNDLE_IDENTIFIER=com.axiomace.ecmenu.debug.finderext
    ECMENU_PRODUCT_APPLICATION_GROUP_IDENTIFIER=FixtureTeam.ecmenu.debug
}
''')
        return self.run_switch(failure, ["/bin/zsh", str(script), "--build-only"])

    def testBuildOnlyVerifiesSignaturesWithoutChangingEnvironment(self):
        result = self.run_build_only()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.states, self.initial_states)
        self.assertEqual(self.events, ["build", "build settings", "verify signature", "verify signature"])

    def testBuildOnlyRejectsInvalidSignatureWithoutChangingEnvironment(self):
        result = self.run_build_only("signature")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.states, self.initial_states)
        self.assertEqual(self.events, ["build", "build settings", "verify signature"])


if __name__ == "__main__":
    unittest.main()
