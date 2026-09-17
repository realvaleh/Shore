#!/usr/bin/env python3
"""Generate Shore.xcodeproj/project.pbxproj for a macOS 14+ SwiftUI app."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Shore.xcodeproj" / "project.pbxproj"

SWIFT = [
    ("ShoreApp.swift", "Shore/App/ShoreApp.swift"),
    ("ShoreAppDelegate.swift", "Shore/App/ShoreAppDelegate.swift"),
    ("ShoreRuntime.swift", "Shore/App/ShoreRuntime.swift"),
    ("ShoreSettings.swift", "Shore/App/ShoreSettings.swift"),
    ("ShoreTheme.swift", "Shore/Design/ShoreTheme.swift"),
    ("IslandModule.swift", "Shore/Island/IslandModule.swift"),
    ("IslandViews.swift", "Shore/Island/IslandViews.swift"),
    ("NowPlaying.swift", "Shore/Island/NowPlaying.swift"),
    ("LiveChips.swift", "Shore/Island/LiveChips.swift"),
    ("FileShelf.swift", "Shore/Island/FileShelf.swift"),
    ("DockModule.swift", "Shore/Dock/DockModule.swift"),
    ("SettingsView.swift", "Shore/Settings/SettingsView.swift"),
    ("OverlayPanel.swift", "Shore/Support/OverlayPanel.swift"),
    ("ScreenGeometry.swift", "Shore/Support/ScreenGeometry.swift"),
]

FRAMEWORKS = ["IOKit", "CoreAudio", "AudioToolbox"]


def hid(n: int) -> str:
    return f"8A01{n:020X}"


PROJECT_ID = hid(1)
TARGET_ID = hid(2)
PRODUCT_ID = hid(3)
PHASE_SOURCES = hid(4)
PHASE_RESOURCES = hid(5)
PHASE_FRAMEWORKS = hid(6)
GROUP_MAIN = hid(7)
GROUP_PRODUCTS = hid(8)
GROUP_SHORE = hid(9)
GROUP_APP = hid(10)
GROUP_DESIGN = hid(11)
GROUP_ISLAND = hid(12)
GROUP_DOCK = hid(13)
GROUP_SETTINGS = hid(14)
GROUP_SUPPORT = hid(15)
GROUP_FRAMEWORKS = hid(16)
CONFLIST_PROJECT = hid(20)
CONFLIST_TARGET = hid(21)
CONF_PROJECT_DEBUG = hid(22)
CONF_PROJECT_RELEASE = hid(23)
CONF_TARGET_DEBUG = hid(24)
CONF_TARGET_RELEASE = hid(25)
ASSETS_REF = hid(40)
ASSETS_BUILD = hid(41)
ENTITLEMENTS_REF = hid(42)
INFOPLIST_REF = hid(43)

file_refs = {name: hid(100 + i) for i, (name, _) in enumerate(SWIFT)}
build_files = {name: hid(200 + i) for i, (name, _) in enumerate(SWIFT)}
fw_refs = {name: hid(300 + i) for i, name in enumerate(FRAMEWORKS)}
fw_builds = {name: hid(320 + i) for i, name in enumerate(FRAMEWORKS)}


def settings_block(lines: dict) -> str:
    inner = "\n".join(f"\t\t\t\t{k} = {v};" for k, v in lines.items())
    return inner


shared_project = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEAD_CODE_STRIPPING": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SDKROOT": "macosx",
}

debug_extra = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)", )',
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}

release_extra = {
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
    "VALIDATE_PRODUCT": "YES",
}

target_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Shore/Shore.entitlements",
    "CODE_SIGN_IDENTITY": '"-"',
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Shore/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Shore",
    "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.utilities"',
    "INFOPLIST_KEY_LSUIElement": "YES",
    "INFOPLIST_KEY_NSHighResolutionCapable": "YES",
    "INFOPLIST_KEY_NSHumanReadableCopyright": '"Copyright © 2026 Valeh"',
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", )',
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.valeh.Shore",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SDKROOT": "macosx",
    "SUPPORTED_PLATFORMS": "macosx",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_VERSION": "6.0",
}

objects = []

# File refs — Swift
for name, path in SWIFT:
    objects.append(
        f"\t\t{file_refs[name]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
    )

objects.append(
    f'\t\t{ASSETS_REF} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};'
)
objects.append(
    f'\t\t{ENTITLEMENTS_REF} /* Shore.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Shore.entitlements; sourceTree = "<group>"; }};'
)
objects.append(
    f'\t\t{INFOPLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};'
)
objects.append(
    f'\t\t{PRODUCT_ID} /* Shore.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Shore.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
)

for name in FRAMEWORKS:
    objects.append(
        f'\t\t{fw_refs[name]} /* {name}.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {name}.framework; path = System/Library/Frameworks/{name}.framework; sourceTree = SDKROOT; }};'
    )

# Build files
for name, _ in SWIFT:
    objects.append(
        f"\t\t{build_files[name]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[name]} /* {name} */; }};"
    )
objects.append(
    f"\t\t{ASSETS_BUILD} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSETS_REF} /* Assets.xcassets */; }};"
)
for name in FRAMEWORKS:
    objects.append(
        f"\t\t{fw_builds[name]} /* {name}.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {fw_refs[name]} /* {name}.framework */; }};"
    )

# Frameworks phase
fw_list = "\n".join(
    f"\t\t\t\t{fw_builds[name]} /* {name}.framework in Frameworks */," for name in FRAMEWORKS
)
objects.append(
    f"""\t\t{PHASE_FRAMEWORKS} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
{fw_list}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};"""
)

# Groups
app_children = "\n".join(
    f"\t\t\t\t{file_refs[n]} /* {n} */,"
    for n in ["ShoreApp.swift", "ShoreAppDelegate.swift", "ShoreRuntime.swift", "ShoreSettings.swift"]
)
design_children = f"\t\t\t\t{file_refs['ShoreTheme.swift']} /* ShoreTheme.swift */,"
island_children = "\n".join(
    f"\t\t\t\t{file_refs[n]} /* {n} */,"
    for n in ["IslandModule.swift", "IslandViews.swift", "NowPlaying.swift", "LiveChips.swift", "FileShelf.swift"]
)
dock_children = f"\t\t\t\t{file_refs['DockModule.swift']} /* DockModule.swift */,"
settings_children = f"\t\t\t\t{file_refs['SettingsView.swift']} /* SettingsView.swift */,"
support_children = "\n".join(
    f"\t\t\t\t{file_refs[n]} /* {n} */,"
    for n in ["OverlayPanel.swift", "ScreenGeometry.swift"]
)

objects += [
    f"""\t\t{GROUP_APP} /* App */ = {{
			isa = PBXGroup;
			children = (
{app_children}
			);
			path = App;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_DESIGN} /* Design */ = {{
			isa = PBXGroup;
			children = (
{design_children}
			);
			path = Design;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_ISLAND} /* Island */ = {{
			isa = PBXGroup;
			children = (
{island_children}
			);
			path = Island;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_DOCK} /* Dock */ = {{
			isa = PBXGroup;
			children = (
{dock_children}
			);
			path = Dock;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_SETTINGS} /* Settings */ = {{
			isa = PBXGroup;
			children = (
{settings_children}
			);
			path = Settings;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_SUPPORT} /* Support */ = {{
			isa = PBXGroup;
			children = (
{support_children}
			);
			path = Support;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_SHORE} /* Shore */ = {{
			isa = PBXGroup;
			children = (
				{GROUP_APP} /* App */,
				{GROUP_DESIGN} /* Design */,
				{GROUP_ISLAND} /* Island */,
				{GROUP_DOCK} /* Dock */,
				{GROUP_SETTINGS} /* Settings */,
				{GROUP_SUPPORT} /* Support */,
				{ASSETS_REF} /* Assets.xcassets */,
				{ENTITLEMENTS_REF} /* Shore.entitlements */,
				{INFOPLIST_REF} /* Info.plist */,
			);
			path = Shore;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_FRAMEWORKS} /* Frameworks */ = {{
			isa = PBXGroup;
			children = (
				{fw_refs['IOKit']} /* IOKit.framework */,
				{fw_refs['CoreAudio']} /* CoreAudio.framework */,
				{fw_refs['AudioToolbox']} /* AudioToolbox.framework */,
			);
			name = Frameworks;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_PRODUCTS} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{PRODUCT_ID} /* Shore.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};""",
    f"""\t\t{GROUP_MAIN} = {{
			isa = PBXGroup;
			children = (
				{GROUP_SHORE} /* Shore */,
				{GROUP_PRODUCTS} /* Products */,
				{GROUP_FRAMEWORKS} /* Frameworks */,
			);
			sourceTree = "<group>";
		}};""",
]

src_list = "\n".join(
    f"\t\t\t\t{build_files[name]} /* {name} in Sources */," for name, _ in SWIFT
)
objects.append(
    f"""\t\t{PHASE_SOURCES} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{src_list}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};"""
)
objects.append(
    f"""\t\t{PHASE_RESOURCES} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ASSETS_BUILD} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};"""
)

objects.append(
    f"""\t\t{TARGET_ID} /* Shore */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {CONFLIST_TARGET} /* Build configuration list for PBXNativeTarget "Shore" */;
			buildPhases = (
				{PHASE_SOURCES} /* Sources */,
				{PHASE_FRAMEWORKS} /* Frameworks */,
				{PHASE_RESOURCES} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Shore;
			productName = Shore;
			productReference = {PRODUCT_ID} /* Shore.app */;
			productType = "com.apple.product-type.application";
		}};"""
)

objects.append(
    f"""\t\t{PROJECT_ID} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				ORGANIZATIONNAME = Valeh;
				TargetAttributes = {{
					{TARGET_ID} = {{
						CreatedOnToolsVersion = 15.0;
					}};
				}};
			}};
			buildConfigurationList = {CONFLIST_PROJECT} /* Build configuration list for PBXProject "Shore" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {GROUP_MAIN};
			productRefGroup = {GROUP_PRODUCTS} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{TARGET_ID} /* Shore */,
			);
		}};"""
)


def xcconfig(oid, name, extra):
    merged = {**shared_project, **extra}
    body = "\n".join(f"\t\t\t\t{k} = {v};" for k, v in merged.items())
    return f"""\t\t{oid} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{body}
			}};
			name = {name};
		}};"""


def xcconfig_target(oid, name):
    body = "\n".join(f"\t\t\t\t{k} = {v};" for k, v in target_settings.items())
    return f"""\t\t{oid} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{body}
			}};
			name = {name};
		}};"""


objects.append(xcconfig(CONF_PROJECT_DEBUG, "Debug", debug_extra))
objects.append(xcconfig(CONF_PROJECT_RELEASE, "Release", release_extra))
objects.append(xcconfig_target(CONF_TARGET_DEBUG, "Debug"))
objects.append(xcconfig_target(CONF_TARGET_RELEASE, "Release"))

objects.append(
    f"""\t\t{CONFLIST_PROJECT} /* Build configuration list for PBXProject "Shore" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{CONF_PROJECT_DEBUG} /* Debug */,
				{CONF_PROJECT_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};"""
)
objects.append(
    f"""\t\t{CONFLIST_TARGET} /* Build configuration list for PBXNativeTarget "Shore" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{CONF_TARGET_DEBUG} /* Debug */,
				{CONF_TARGET_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};"""
)

pbx = """// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {
""" + "\n".join(objects) + f"""
	}};
	rootObject = {PROJECT_ID} /* Project object */;
}}
"""

PROJECT.parent.mkdir(parents=True, exist_ok=True)
PROJECT.write_text(pbx)
print(f"Wrote {PROJECT} ({len(SWIFT)} sources)")
