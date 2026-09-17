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
        if "SWIFT_VERSION = 6.0" not in pbx:
            err("pbxproj must use Swift 6 language mode")
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
        "Shore/Island/FileShelf.swift",
        "Shore/Dock/DockModule.swift",
        "Shore/Settings/SettingsView.swift",
        "scripts/package-dmg.sh",
        "docs/screenshots/island-collapsed.png",
        "docs/screenshots/island-expanded.png",
        "docs/screenshots/cove.png",
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
        "GitHub Releases",
        "Shore-*.dmg",
        "right-click",
    ]:
        if needle.lower() not in readme.lower():
            err(f"README missing section/mention: {needle}")

    settings = read(ROOT / "Shore/App/ShoreSettings.swift")
    if "islandEnabled" not in settings:
        err("settings toggles missing")
    if "fileShelfEnabled" not in settings:
        err("file shelf settings toggle missing")
    if "@MainActor" not in settings:
        err("ShoreSettings must be MainActor-isolated")
    if "static let shared" not in settings:
        err("ShoreSettings.shared missing")
    if "dockEnabled" in settings and "Published var dockEnabled" in settings:
        err("Dock Cove toggle must be retired from ShoreSettings")

    runtime = read(ROOT / "Shore/App/ShoreRuntime.swift")
    if re.search(r"private let settings\s*=\s*ShoreSettings\.shared", runtime):
        err("ShoreRuntime must assign ShoreSettings.shared inside init, not a property default")
    if "NowPlayingStore(settings:" not in runtime:
        err("NowPlayingStore must receive ShoreSettings from a MainActor init")

    now_playing = read(ROOT / "Shore/Island/NowPlaying.swift")
    if "MediaRemote" not in now_playing or "sample" not in now_playing.lower():
        err("now-playing must include MediaRemote + sample fallback")
    if re.search(r"init\(settings:\s*ShoreSettings\s*=\s*\.shared\)", now_playing):
        err("do not use MainActor ShoreSettings.shared as a default argument")
    if re.search(r"func load\s*<", now_playing) and "init()" in now_playing:
        err("MediaRemote init must not nest load() that captures self")
    if "dlsym" not in now_playing:
        err("MediaRemote loader must resolve symbols via dlsym")

    icon_manifest = read(
        ROOT / "Shore/Assets.xcassets/AppIcon.appiconset/Contents.json"
    )
    if "AppIcon-1024.png" not in icon_manifest or "1024x1024" not in icon_manifest:
        err("AppIcon Contents.json must assign the 1024x1024 image")

    dmg = read(ROOT / "scripts/package-dmg.sh")
    if "dist" not in dmg or "xcodebuild" not in dmg or "Release" not in dmg:
        err("package-dmg.sh must build Release into dist/")
    if "Shore-" not in dmg or ".dmg" not in dmg:
        err("package-dmg.sh must write dist/Shore-*.dmg")

    island = read(ROOT / "Shore/Island/IslandViews.swift")
    if "isExpanded" not in island:
        err("island expand/collapse missing")
    if "ShoreMarquee" not in island:
        err("island titles must use marquee or equivalent instead of cheap ellipsis")
    if "ignoresSafeArea" not in island:
        err("island chrome must ignore safe-area so it can hug the hardware notch")
    if "IslandCanvas" not in island or "IslandStage" not in island:
        err("island must morph one canvas, not cross-fade two layouts")
    if "collapseExplicitly" not in island or "hoverSuspended" not in island:
        err("island must suspend hover after an explicit collapse")
    if "ChipRow(store:" not in island:
        err("island chips must be wired as interactive controls, not silent collapse targets")
    if "onDrop" not in island:
        err("island must accept file drops onto the notch chrome")
    if "VolumeHUDRow" not in island:
        err("volume HUD row missing from compact island")

    theme = read(ROOT / "Shore/Design/ShoreTheme.swift")
    if "static var defaultValue" in theme:
        err("PreferenceKey defaultValue must be a static let (Swift 6 concurrency)")
    if "IslandBlendShape" not in theme:
        err("missing IslandBlendShape notch-blend chrome")
    if "addCurve" not in theme:
        err("island chrome must be a continuous cubic path, not composited rectangles")
    if "path.addRect" in theme:
        err("collapsed island must not fill a sharp-cornered rectangle")
    if "flushTop" not in theme or "earRadius" not in theme:
        err("island silhouette must morph neck/ears/corners as one path family")
    if "static func island(" not in theme:
        err("IslandBlendShape.island factory missing")
    if "path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))" not in theme:
        err("notched island must flush a full-width top to the bezel (not a notch-width stem)")
    if "nL" in theme or "nR" in theme or "yFlare0" in theme:
        err("island path must not stem from notch width then flare (that is the T-bar)")
    if "compositingGroup" not in theme:
        err("island chrome must compositingGroup so the bezel fill does not AA into a gray halo")
    if "shoreMorph" not in theme:
        err("missing elastic shoreMorph animation")
    if "bezel" not in theme:
        err("notch chrome must use bezel black")
    if "Color(red: 0, green: 0, blue: 0)" not in theme:
        err("bezel chrome must be true black #000000")
    if ".ultraThinMaterial" in theme:
        err("island chrome must not use gray ultraThinMaterial")
    if "shoreMorph = Animation.spring" not in theme:
        err("island morph must stay a spring, not a linear/timing curve")

    geometry = read(ROOT / "Shore/Support/ScreenGeometry.swift")
    if "notchHeight" not in geometry or "notchFrame" not in geometry:
        err("screen geometry must expose notch height and frame")
    if "bezelFlushNudge" not in geometry:
        err("notched placement must flush into the bezel")

    overlay = read(ROOT / "Shore/Support/OverlayPanel.swift")
    if "ignoresMouseEvents" not in overlay:
        err("overlay panel must support click-through")
    if "animationBehavior = .none" not in overlay:
        err("overlay panel must disable system utility animation")
    if "NSTrackingArea" not in overlay:
        err("island surface must use NSTrackingArea for hover")
    if "hitTest" not in overlay:
        err("island surface must hit-test only the chrome")
    if "chromeContains" not in overlay:
        err("island hit-testing must follow the silhouette path, not a T-bounding rect")
    if "safeAreaInsets" not in overlay or "safeAreaRegions" not in overlay:
        err("island host must zero safe-area so chrome can sit flush to the bezel")

    module = read(ROOT / "Shore/Island/IslandModule.swift")
    if "mouseMoved" not in module or "addGlobalMonitorForEvents" not in module:
        err("island hover must monitor NSEvent mouseMoved globally")
    if "hoverSuspended" not in module:
        err("island module must honor hover suspend after collapse")
    if "chromeContains" not in module:
        err("island module must hit-test the organic silhouette, not the T bounding box")

    chips = read(ROOT / "Shore/Island/LiveChips.swift")
    if "toggleMute" not in chips:
        err("volume chip must be a real mute affordance")
    if "Button(action: onTap)" not in chips:
        err("live chips must be buttons so they do not collapse the island")

    shelf = read(ROOT / "Shore/Island/FileShelf.swift")
    if "onDrop" not in shelf or "onDrag" not in shelf:
        err("file shelf must support drop in and drag out")
    if "FileDropURLBox" not in shelf and "FileDropCollector" not in shelf:
        err("file drop collection must use a Sendable box (Swift 6)")

    dock = read(ROOT / "Shore/Dock/DockModule.swift")
    if "TideLine" in dock:
        err("Tide Line must stay gone")
    if "Cove" in dock or "dockVisible" in dock:
        err("Dock Cove / always-on dock tray must be removed")
    if "Basket" not in dock or "onDrop" not in dock:
        err("dock module must be a drag-time file basket")
    if "draggingFiles" not in dock:
        err("basket must appear when a file drag starts")
    if "hitTest" not in dock:
        err("basket must hit-test only its chrome so the desktop stays clickable")
    if "var revealed: Bool { draggingFiles || targeted }" not in dock and "revealed: Bool { draggingFiles" not in dock:
        err("basket must reveal only while a drag is in flight")
    ui = read(ROOT / "Shore/Settings/SettingsView.swift") + read(ROOT / "Shore/App/ShoreApp.swift")
    if "Dock Cove" in ui:
        err("settings/menu must not offer a Dock Cove toggle")

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
