import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AndroidRebuildTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_windows_is_removed(self) -> None:
        self.assertFalse((ROOT / "windows").exists())
        self.assertFalse((ROOT / "lib/core/windows_vpn_core.dart").exists())
        self.assertFalse((ROOT / "assets/images/app_icon.ico").exists())
        workflow = self.read(".github/workflows/build.yml")
        self.assertNotIn("windows:", workflow)
        self.assertNotIn("flutter build windows", workflow)

    def test_every_server_test_uses_a_real_temporary_tunnel(self) -> None:
        core = self.read("lib/core/android_vpn_core.dart")
        block = core.split("Future<ProbeResult> test(", 1)[1].split(
            "Future<ProbeResult> validateConnected", 1
        )[0]
        self.assertNotIn("pingProfile", block)
        self.assertIn("await connect(node, settings)", block)
        self.assertIn("await validateConnected(remaining)", block)
        self.assertIn("await disconnect()", block)

    def test_connect_is_explicit_and_separate(self) -> None:
        controller = self.read("lib/services/app_controller.dart")
        connect = controller.split("Future<void> connectNode", 1)[1].split(
            "Future<void> connectOrDisconnect", 1
        )[0]
        self.assertIn("await core.connect", connect)
        self.assertNotIn("testNode", connect)
        self.assertNotIn("latency.check", connect)

    def test_failed_profiles_require_repeated_failures(self) -> None:
        controller = self.read("lib/services/app_controller.dart")
        self.assertIn("url_test_failures", controller)
        self.assertIn("final remove = settings.autoRemoveUnavailable", controller)
        self.assertIn("hasBaseInternet", controller)
        self.assertIn("quarantineHours", controller)

    def test_warp_uses_file_import_and_real_probe(self) -> None:
        controller = self.read("lib/services/app_controller.dart")
        core = self.read("lib/core/android_vpn_core.dart")
        self.assertIn("extractSingleWgQuick", controller)
        self.assertIn("final file = await openFile();", controller)
        self.assertNotIn("generateWarpPool", controller)
        self.assertNotIn("importWarpFromWebsite", controller)
        self.assertIn("probeVpnNetwork", core)
        self.assertNotIn("latencyMs: 1", core)
        for name in ("WARP_STR8605.conf", "WARP_STR4470.conf"):
            self.assertTrue((ROOT / "assets" / "warp" / name).is_file())
        self.assertFalse((ROOT / "assets" / "warp" / "WARP_STR6230.conf").exists())

    def test_probe_mutex_warp_stats_generator_and_themes_exist(self) -> None:
        controller = self.read("lib/services/app_controller.dart")
        core = self.read("lib/core/android_vpn_core.dart")
        bridge = self.read("lib/core/amneziawg_bridge.dart")
        patcher = self.read("tools/prepare_android.py")
        generator = self.read("lib/services/warp_generator_service.dart")
        settings = self.read("lib/models/app_settings.dart")
        self.assertIn("probeInProgress", controller)
        self.assertIn("_probeInProgress", core)
        self.assertIn("_awgStatsReadInProgress", core)
        self.assertIn("_startAwgStatistics", core)
        self.assertIn("Future<AwgTrafficStats> statistics", bridge)
        self.assertIn("getStatistics(tunnel)", patcher)
        self.assertIn("warpGenerationCooldown = Duration(hours: 1)", controller)
        self.assertIn("generateOneWarp", controller)
        self.assertEqual(generator.count("/api/generate'"), 3)
        self.assertIn("enum VisualTheme", settings)
        for name in ("theme_nightmare.webp", "theme_symbiosis.webp"):
            self.assertTrue((ROOT / "assets" / "images" / name).is_file())

    def test_split_tunneling_applies_to_both_cores(self) -> None:
        settings = self.read("lib/models/app_settings.dart")
        core = self.read("lib/core/android_vpn_core.dart")
        self.assertIn("SplitTunnelMode", settings)
        self.assertIn("splitTunnelingEnabled", core)
        self.assertIn("IncludedApplications", core)
        self.assertIn("ExcludedApplications", core)

    def test_android_only_navigation_exists(self) -> None:
        shell = self.read("lib/screens/app_shell.dart")
        self.assertIn("ServersScreen", shell)
        self.assertIn("WarpScreen", shell)
        self.assertIn("NavigationBar", shell)
        self.assertNotIn("NavigationRail", shell)

    def test_version_is_094(self) -> None:
        self.assertIn("version: 0.9.4+94", self.read("pubspec.yaml"))
        self.assertIn("Поколение VPN 0.9.4", self.read("lib/screens/settings_screen.dart"))

    def test_analyzer_keeps_compile_warnings_fatal_without_style_noise(self) -> None:
        pubspec = self.read("pubspec.yaml")
        analysis = self.read("analysis_options.yaml")
        self.assertNotIn("flutter_lints", pubspec)
        self.assertNotIn("package:flutter_lints", analysis)
        self.assertIn("unused_import: error", analysis)
        self.assertIn("dead_code: error", analysis)

    def test_setup_errors_do_not_count_as_dead_server(self) -> None:
        controller = self.read("lib/services/app_controller.dart")
        connect = controller.split("Future<void> connectNode", 1)[1].split(
            "Future<void> connectOrDisconnect", 1
        )[0]
        self.assertIn("confirmedTunnelFailure: false", connect)
        failure = controller.split("Future<void> _recordConnectionFailure", 1)[1].split(
            "Future<bool> testNode", 1
        )[0]
        self.assertIn("failures = confirmedTunnelFailure", failure)
        self.assertIn("confirmedTunnelFailure &&", failure)

    def test_catalog_auto_refresh_is_real_and_configurable(self) -> None:
        settings = self.read("lib/models/app_settings.dart")
        controller = self.read("lib/services/app_controller.dart")
        self.assertIn("autoRefresh", settings)
        self.assertIn("refreshOnResume", settings)
        self.assertIn("autoTestAfterRefresh", settings)
        self.assertIn("autoTestAfterRefresh: false", settings)
        refresh = controller.split("Future<void> refreshCatalog", 1)[1].split(
            "VpnNode _preserveRuntime", 1
        )[0]
        self.assertNotIn("_testNodeQueue", refresh)
        self.assertIn("refreshCatalog({bool silent = false})", controller)
        self.assertIn("_configureTimer", controller)

    def test_hourly_catalog_is_published_and_whitelist_caps_are_separate(self) -> None:
        workflow = self.read(".github/workflows/refresh-catalog.yml")
        settings = self.read("lib/models/app_settings.dart")
        self.assertIn("contents: write", workflow)
        self.assertIn("whitelist_counts", workflow)
        self.assertIn("git push", workflow)
        self.assertIn("CTPAXlost/BPM/main/catalog/public_catalog.json", settings)

    def test_bulk_probe_keeps_ui_order_and_hides_temporary_core_states(self) -> None:
        controller = self.read("lib/services/app_controller.dart")
        core = self.read("lib/core/android_vpn_core.dart")
        self.assertIn("_testingOrder", controller)
        self.assertIn("_compareFrozenTestOrder", controller)
        self.assertIn("_silentProbe", core)

    def test_android_patcher_is_idempotent_and_private(self) -> None:
        with tempfile.TemporaryDirectory() as raw_temp:
            root = Path(raw_temp) / "project"
            (root / "tools").mkdir(parents=True)
            shutil.copy2(ROOT / "tools/prepare_android.py", root / "tools/prepare_android.py")
            (root / "android/app/src/main").mkdir(parents=True)
            (root / "android/app/src/main/AndroidManifest.xml").write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '  <application android:label="old" android:usesCleartextTraffic="true">\n'
                '    <activity android:name=".MainActivity" android:exported="true" />\n'
                '  </application>\n'
                '</manifest>\n',
                encoding="utf-8",
            )
            (root / "android/settings.gradle.kts").write_text(
                'pluginManagement {}\nplugins {\n'
                '  id("com.android.application") version "8.9.1" apply false\n'
                '}\ninclude(":app")\n',
                encoding="utf-8",
            )
            (root / "android/app/build.gradle.kts").write_text(
                'plugins { id("com.android.application") }\n'
                'android {\n'
                '  namespace = "com.example.old"\n'
                '  compileSdk = 36\n'
                '  defaultConfig { applicationId = "com.example.old"; minSdk = flutter.minSdkVersion }\n'
                '}\n',
                encoding="utf-8",
            )
            (root / "android/gradle.properties").write_text(
                "android.bundle.enableUncompressedNativeLibs=false\n",
                encoding="utf-8",
            )
            (root / "third_party/amneziawg-android/tunnel").mkdir(parents=True)
            (root / "third_party/amneziawg-android/tunnel/build.gradle.kts").write_text(
                '// replaced by patcher\n', encoding="utf-8"
            )
            (root / "assets/images").mkdir(parents=True)
            for size in (48, 72, 96, 144, 192):
                shutil.copy2(
                    ROOT / f"assets/images/launcher_{size}.png",
                    root / f"assets/images/launcher_{size}.png",
                )
            for _ in range(2):
                subprocess.run(
                    ["python", "tools/prepare_android.py"],
                    cwd=root,
                    check=True,
                    capture_output=True,
                    text=True,
                )
            manifest = (root / "android/app/src/main/AndroidManifest.xml").read_text(
                encoding="utf-8"
            )
            kotlin = (
                root
                / "android/app/src/main/kotlin/app/pokolenie/vpn/MainActivity.kt"
            ).read_text(encoding="utf-8")
            gradle = (root / "android/app/build.gradle.kts").read_text(encoding="utf-8")
            gradle_properties = (root / "android/gradle.properties").read_text(
                encoding="utf-8"
            )
            self.assertNotIn("usesCleartextTraffic", manifest)
            self.assertNotIn("QUERY_ALL_PACKAGES", manifest)
            self.assertEqual(manifest.count("WarpGenActivity"), 0)
            self.assertEqual(kotlin.count("class MainActivity"), 1)
            self.assertNotIn("WarpGenActivity", kotlin)
            self.assertEqual(kotlin.count("tunnelName = requestedName"), 1)
            self.assertEqual(gradle.count("useLegacyPackaging = true"), 1)
            self.assertNotIn("enableUncompressedNativeLibs", gradle_properties)
            self.assertEqual(gradle.count('implementation(project(":amneziawg_tunnel"))'), 1)

    def test_generated_validation_allows_flutter_workdirs_only_explicitly(self) -> None:
        validator = self.read("tools/validate_source.py")
        workflow = self.read(".github/workflows/build.yml")
        self.assertIn('"--allow-generated"', validator)
        self.assertIn("if allow_generated:", validator)
        self.assertIn("python tools/validate_source.py --allow-generated", workflow)
        self.assertGreaterEqual(workflow.count("python tools/validate_source.py"), 3)
        self.assertEqual(
            workflow.count("python tools/validate_source.py --allow-generated"), 1
        )

    def test_clean_source_validation_still_rejects_generated_garbage(self) -> None:
        validator = self.read("tools/validate_source.py")
        self.assertIn(
            'forbidden_parts = {".dart_tool", "build", ".gradle", "__pycache__", "dist"}',
            validator,
        )
        self.assertIn("allow_generated=args.allow_generated", validator)


if __name__ == "__main__":
    unittest.main()
