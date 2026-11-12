#!/usr/bin/env python3
"""Generates PRIME.xcodeproj from the folders on disk.

Every .swift file under PRIME/ joins the app target, every .swift file under
PRIMETests/ joins the test target, and the JSON resources plus the asset catalog
are bundled. Re-run after adding or removing files:  python3 tools/gen_xcodeproj.py
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "PRIME"
TESTS = "PRIMETests"
BUNDLE_ID = "com.savonstudios.prime"
DEPLOYMENT = "17.0"


def uid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def q(value):
    value = str(value)
    if value and all(c.isalnum() or c in "._/$" for c in value) and not value[0].isdigit():
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def settings(d, indent):
    pad = "\t" * indent
    lines = []
    for key in sorted(d):
        value = d[key]
        if isinstance(value, list):
            inner = "".join(f"\n{pad}\t{q(v)}," for v in value)
            lines.append(f"{pad}{key} = ({inner}\n{pad});")
        else:
            lines.append(f"{pad}{key} = {q(value)};")
    return "\n".join(lines)


class Project:
    def __init__(self):
        self.objects = {}  # id -> (isa, body)

    def add(self, isa, oid, body):
        self.objects[oid] = (isa, body)
        return oid


def build():
    p = Project()
    files = {"app_src": [], "app_res": [], "test_src": []}

    # Collect files
    for path in sorted((ROOT / APP).rglob("*")):
        rel = path.relative_to(ROOT)
        if any(part.endswith(".xcassets") for part in rel.parts[:-1]):
            continue
        if path.is_dir() and path.suffix == ".xcassets":
            files["app_res"].append(rel)
        elif path.is_file() and path.suffix == ".swift":
            files["app_src"].append(rel)
        elif path.is_file() and path.suffix == ".json" and "Resources" in rel.parts:
            files["app_res"].append(rel)
    for path in sorted((ROOT / TESTS).rglob("*.swift")):
        files["test_src"].append(path.relative_to(ROOT))

    # Groups: one per directory, nested
    group_children = {}
    group_ids = {}

    def ensure_group(rel_dir: Path):
        key = rel_dir.as_posix()
        if key in group_ids:
            return group_ids[key]
        gid = uid("group", key)
        group_ids[key] = gid
        group_children[key] = []
        if rel_dir.parent.as_posix() != ".":
            ensure_group(rel_dir.parent)
            group_children[rel_dir.parent.as_posix()].append(gid)
        return gid

    file_refs = {}
    for rel in files["app_src"] + files["app_res"] + files["test_src"]:
        ensure_group(rel.parent)
        fid = uid("file", rel.as_posix())
        file_refs[rel.as_posix()] = fid
        group_children[rel.parent.as_posix()].append(fid)
        if rel.suffix == ".swift":
            ftype = "sourcecode.swift"
        elif rel.suffix == ".json":
            ftype = "text.json"
        else:
            ftype = "folder.assetcatalog"
        p.add("PBXFileReference", fid, f"isa = PBXFileReference; lastKnownFileType = {ftype}; path = {q(rel.name)}; sourceTree = \"<group>\";")

    for key, gid in group_ids.items():
        children = "".join(f"\n\t\t\t\t{c}," for c in group_children[key])
        name = Path(key).name
        p.add("PBXGroup", gid, f"isa = PBXGroup; children = ({children}\n\t\t\t); path = {q(name)}; sourceTree = \"<group>\";")

    app_product = uid("product", APP)
    test_product = uid("product", TESTS)
    p.add("PBXFileReference", app_product, f"isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR;")
    p.add("PBXFileReference", test_product, f"isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TESTS}.xctest; sourceTree = BUILT_PRODUCTS_DIR;")
    products_group = uid("group", "Products")
    p.add("PBXGroup", products_group, f"isa = PBXGroup; children = (\n\t\t\t\t{app_product},\n\t\t\t\t{test_product},\n\t\t\t); name = Products; sourceTree = \"<group>\";")
    main_group = uid("group", "main")
    tops = [group_ids[APP], group_ids[TESTS], products_group]
    p.add("PBXGroup", main_group, "isa = PBXGroup; children = (" + "".join(f"\n\t\t\t\t{t}," for t in tops) + "\n\t\t\t); sourceTree = \"<group>\";")

    def build_files(rels, phase):
        ids = []
        for rel in rels:
            bid = uid("build", phase, rel.as_posix())
            p.add("PBXBuildFile", bid, f"isa = PBXBuildFile; fileRef = {file_refs[rel.as_posix()]};")
            ids.append(bid)
        return ids

    def phase(isa, key, ids):
        pid = uid("phase", key)
        body = f"isa = {isa}; buildActionMask = 2147483647; files = (" + "".join(f"\n\t\t\t\t{i}," for i in ids) + "\n\t\t\t); runOnlyForDeploymentPostprocessing = 0;"
        p.add(isa, pid, body)
        return pid

    app_sources = phase("PBXSourcesBuildPhase", "app-src", build_files(files["app_src"], "app-src"))
    app_resources = phase("PBXResourcesBuildPhase", "app-res", build_files(files["app_res"], "app-res"))
    app_frameworks = phase("PBXFrameworksBuildPhase", "app-fw", [])
    test_sources = phase("PBXSourcesBuildPhase", "test-src", build_files(files["test_src"], "test-src"))
    test_resources = phase("PBXResourcesBuildPhase", "test-res", [])
    test_frameworks = phase("PBXFrameworksBuildPhase", "test-fw", [])

    project_id = uid("project")
    app_target = uid("target", APP)
    test_target = uid("target", TESTS)

    common_debug = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES", "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20", "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES", "COPY_PHASE_STRIP": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_TESTABILITY": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_DYNAMIC_NO_PIC": "NO", "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0", "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT, "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE", "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": "iphoneos", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    common_release = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES", "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20", "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES", "COPY_PHASE_STRIP": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO", "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_NO_COMMON_BLOCKS": "YES", "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
        "MTL_ENABLE_DEBUG_INFO": "NO", "SDKROOT": "iphoneos", "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O", "VALIDATE_PRODUCT": "YES",
    }
    app_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "3", "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_CFBundleDisplayName": "PRIME",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.healthcare-fitness",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UIStatusBarStyle": "UIStatusBarStyleLightContent",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
        "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "MARKETING_VERSION": "2.1", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID, "PRODUCT_NAME": "$(TARGET_NAME)",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES", "SWIFT_VERSION": "5.0", "TARGETED_DEVICE_FAMILY": "1",
    }
    test_settings = {
        "BUNDLE_LOADER": "$(TEST_HOST)", "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "3",
        "GENERATE_INFOPLIST_FILE": "YES", "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT, "MARKETING_VERSION": "2.1",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + "Tests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "NO", "SWIFT_VERSION": "5.0", "TARGETED_DEVICE_FAMILY": "1",
        "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP}",
    }

    def config_list(key, debug, release):
        d = uid("config", key, "Debug")
        r = uid("config", key, "Release")
        p.add("XCBuildConfiguration", d, f"isa = XCBuildConfiguration; buildSettings = {{\n{settings(debug, 4)}\n\t\t\t}}; name = Debug;")
        p.add("XCBuildConfiguration", r, f"isa = XCBuildConfiguration; buildSettings = {{\n{settings(release, 4)}\n\t\t\t}}; name = Release;")
        lid = uid("configlist", key)
        p.add("XCConfigurationList", lid, f"isa = XCConfigurationList; buildConfigurations = (\n\t\t\t\t{d},\n\t\t\t\t{r},\n\t\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
        return lid

    project_configs = config_list("project", common_debug, common_release)
    app_configs = config_list("app", app_settings, app_settings)
    test_configs = config_list("tests", test_settings, test_settings)

    proxy = uid("proxy")
    p.add("PBXContainerItemProxy", proxy, f"isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = {APP};")
    dependency = uid("dependency")
    p.add("PBXTargetDependency", dependency, f"isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};")

    p.add("PBXNativeTarget", app_target,
          f"isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = (\n\t\t\t\t{app_sources},\n\t\t\t\t{app_frameworks},\n\t\t\t\t{app_resources},\n\t\t\t); "
          f"buildRules = (\n\t\t\t); dependencies = (\n\t\t\t); name = {APP}; productName = {APP}; productReference = {app_product}; productType = \"com.apple.product-type.application\";")
    p.add("PBXNativeTarget", test_target,
          f"isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = (\n\t\t\t\t{test_sources},\n\t\t\t\t{test_frameworks},\n\t\t\t\t{test_resources},\n\t\t\t); "
          f"buildRules = (\n\t\t\t); dependencies = (\n\t\t\t\t{dependency},\n\t\t\t); name = {TESTS}; productName = {TESTS}; productReference = {test_product}; productType = \"com.apple.product-type.bundle.unit-test\";")

    p.add("PBXProject", project_id,
          "isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; "
          f"TargetAttributes = {{ {app_target} = {{ CreatedOnToolsVersion = 16.0; }}; {test_target} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {app_target}; }}; }}; }}; "
          f"buildConfigurationList = {project_configs}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; "
          f"knownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t); mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = \"\"; projectRoot = \"\"; "
          f"targets = (\n\t\t\t\t{app_target},\n\t\t\t\t{test_target},\n\t\t\t);")

    # Serialise grouped by isa, like Xcode
    out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
    for isa in sorted({isa for isa, _ in p.objects.values()}):
        out.append(f"\n/* Begin {isa} section */")
        for oid in sorted(k for k, (i, _) in p.objects.items() if i == isa):
            out.append(f"\t\t{oid} = {{{p.objects[oid][1]}}};")
        out.append(f"/* End {isa} section */")
    out += ["\t};", f"\trootObject = {project_id};", "}", ""]

    proj = ROOT / f"{APP}.xcodeproj"
    (proj / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
    (proj / "project.pbxproj").write_text("\n".join(out))
    (proj / "project.xcworkspace" / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n')
    schemes = proj / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    ref = lambda tid, name, product: (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tid}" '
                                      f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:{APP}.xcodeproj"></BuildableReference>')
    app_ref = ref(app_target, APP, f"{APP}.app")
    test_ref = ref(test_target, TESTS, f"{TESTS}.xctest")
    (schemes / f"{APP}.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "NO">
            {test_ref}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
''')
    print(f"{len(files['app_src'])} app sources, {len(files['app_res'])} resources, {len(files['test_src'])} test files")


if __name__ == "__main__":
    build()
