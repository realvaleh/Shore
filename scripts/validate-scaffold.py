#!/usr/bin/env python3
"""Sanity-check the Shore source scaffold (runs on Linux; does not compile Swift)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def read(path: Path) -> str:
    if not path.exists():
        err(f"missing file: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


def main() -> int:
    pbx = read(ROOT / "Shore.xcodeproj" / "project.pbxproj")
    if pbx:
        if "MACOSX_DEPLOYMENT_TARGET = 14.0" not in pbx:
            err("pbxproj must target macOS 14.0")
        if "com.valeh.Shore" not in pbx:
            err("bundle id missing")
        if "isa = PBXNativeTarget" not in pbx:
            err("native app target missing")
        refs = re.findall(r"path = ([^;]+); sourceTree = \"<group>\";", pbx)
        for rel in refs:
            rel = rel.strip()
            if rel.endswith(".framework") or rel in {
                "App",
                "Design",
                "Island",
                "Dock",
                "Settings",
                "Support",
                "Shore",
                "Assets.xcassets",
                "Shore.entitlements",
                "Info.plist",
            }:
                continue
            # Swift files live under Shore/<group>/
            matches = list((ROOT / "Shore").rglob(rel))
            if not matches:
                err(f"pbxproj references missing file: {rel}")

    required = [
        "LICENSE",
        "README.md",
        "Shore/App/ShoreApp.swift",
        "Shore/App/ShoreSettings.swift",
        "Shore/Island/IslandModule.swift",
        "Shore/Island/NowPlaying.swift",
        "Shore/Island/LiveChips.swift",
        "Shore/Dock/DockModule.swift",
        "Shore/Settings/SettingsView.swift",
        "scripts/package-dmg.sh",
        "docs/screenshots/island-collapsed.png",
        "docs/screenshots/island-expanded.png",
        "docs/screenshots/tide-line.png",
        "docs/screenshots/settings.png",
    ]
    for rel in required:
        if not (ROOT / rel).exists():
            err(f"missing required path: {rel}")

    license_text = read(ROOT / "LICENSE")
    if license_text and "MIT License" not in license_text:
        err("LICENSE is not MIT")

    readme = read(ROOT / "README.md")
    for needle in [
        "Shore",
        "Island",
        "Dock",
        "xcodebuild",
        "Gatekeeper",
        "Notarization",
        "MediaRemote",
        "macOS 14",
        "this PR is source",
    ]:
        if needle.lower() not in readme.lower():
            err(f"README missing section/mention: {needle}")

    settings = read(ROOT / "Shore/App/ShoreSettings.swift")
    if "islandEnabled" not in settings or "dockEnabled" not in settings:
        err("settings toggles missing")

    now_playing = read(ROOT / "Shore/Island/NowPlaying.swift")
    if "MediaRemote" not in now_playing or "sample" not in now_playing.lower():
        err("now-playing must include MediaRemote + sample fallback")

    island = read(ROOT / "Shore/Island/IslandViews.swift")
    if "isExpanded" not in island:
        err("island expand/collapse missing")

    dock = read(ROOT / "Shore/Dock/DockModule.swift")
    if "ignoresMouseEvents" not in read(ROOT / "Shore/Support/OverlayPanel.swift"):
        err("overlay panel must support click-through")
    if "TideLine" not in dock:
        err("dock tide line missing")

    # Originality guardrail — we talk about peers in README, not copy them in code.
    banned = ("Atoll", "BoringNotch", "Boring Notch", "Notchy", "Droppy")
    for path in (ROOT / "Shore").rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        for word in banned:
            if word.lower() in text.lower():
                err(f"{path.relative_to(ROOT)} mentions {word}")

    if errors:
        print("Scaffold validation failed:")
        for item in errors:
            print(f"  - {item}")
        return 1
    print("Scaffold validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
