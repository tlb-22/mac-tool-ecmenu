#!/usr/bin/env python3

"""核对中英文 README 总览图的文件名、引用与 Xcode 工程版本，供本地和 CI 使用。"""

import json
from pathlib import Path
import re
import subprocess


def project_version(project_root: Path) -> str:
    project = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-",
        str(project_root / "ECMenu.xcodeproj/project.pbxproj"),
    ]))
    versions = {
        item["buildSettings"]["MARKETING_VERSION"]
        for item in project["objects"].values()
        if item.get("isa") == "XCBuildConfiguration"
        and "MARKETING_VERSION" in item["buildSettings"]
    }
    if len(versions) != 1:
        raise ValueError(f"Expected one project MARKETING_VERSION, found: {sorted(versions)}")
    return versions.pop()


def check_images(project_root: Path, version: str) -> None:
    for readme_name, language in [("README.md", "en"), ("README.zh-Hans.md", "zh-Hans")]:
        expected = f".docs/images/overview-v{version}-{language}.png"
        readme = (project_root / readme_name).read_text(encoding="utf-8")
        references = re.findall(r"\.docs/images/overview-[^\s\"')/]+\.png", readme)
        if references != [expected]:
            raise ValueError(
                f"{readme_name}: expected {expected}, found {references}. "
                "Run ./scripts/capture-readme-images.sh after updating the version."
            )
        image = project_root / expected
        if not image.is_file() or image.stat().st_size == 0:
            raise ValueError(f"README screenshot is missing or empty: {expected}")


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    try:
        version = project_version(root)
        check_images(root, version)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"README image check failed: {error}")
    print(f"README image filenames and references match project version {version}.")
