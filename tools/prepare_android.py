#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID_PACKAGE = "app.pokolenie.vpn"
AWG_PACKAGE = "org.amnezia.awg"
AWG_MODULE = "amneziawg_tunnel"
AWG_NDK = "28.2.13676358"


def _insert_after_opening_tag(text: str, tag: str, payload: str) -> str:
    pattern = re.compile(rf"(<{tag}\b[^>]*>)", re.IGNORECASE)
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"<{tag}> not found")
    return text[: match.end()] + payload + text[match.end() :]


def _patch_android_settings() -> None:
    settings_candidates = [
        ROOT / "android/settings.gradle.kts",
        ROOT / "android/settings.gradle",
    ]
    settings = next((path for path in settings_candidates if path.exists()), None)
    if settings is None:
        raise SystemExit("Android settings.gradle(.kts) not found.")

    text = settings.read_text(encoding="utf-8")
    if settings.suffix == ".kts":
        if 'id("com.android.library")' not in text:
            app_plugin = re.search(
                r'(?P<indent>\s*)id\("com\.android\.application"\)\s+version\s+"(?P<version>[^"]+)"\s+apply\s+false',
                text,
            )
            if not app_plugin:
                raise SystemExit("Could not determine Android Gradle Plugin version.")
            insertion = (
                app_plugin.group(0)
                + f'\n{app_plugin.group("indent")}id("com.android.library") version "{app_plugin.group("version")}" apply false'
            )
            text = text[: app_plugin.start()] + insertion + text[app_plugin.end() :]
        include_line = f'include(":{AWG_MODULE}")'
        project_line = (
            f'project(":{AWG_MODULE}").projectDir = '
            'file("../third_party/amneziawg-android/tunnel")'
        )
    else:
        include_line = f"include ':{AWG_MODULE}'"
        project_line = (
            f"project(':{AWG_MODULE}').projectDir = "
            "file('../third_party/amneziawg-android/tunnel')"
        )
    if include_line not in text:
        text = text.rstrip() + f"\n\n{include_line}\n{project_line}\n"
    settings.write_text(text, encoding="utf-8")


def _patch_awg_module() -> None:
    tunnel = ROOT / "third_party/amneziawg-android/tunnel"
    if not tunnel.exists():
        raise SystemExit(
            "Official AmneziaWG source is missing. Clone "
            "amnezia-vpn/amneziawg-android with submodules first."
        )
    build = tunnel / "build.gradle.kts"
    if not build.exists():
        raise SystemExit("AmneziaWG tunnel/build.gradle.kts not found.")

    build.write_text(
        f'''@file:Suppress("UnstableApiUsage")

import org.gradle.api.tasks.testing.logging.TestLogEvent

plugins {{
    id("com.android.library")
}}

android {{
    namespace = "{AWG_PACKAGE}.tunnel"
    compileSdk = 36
    ndkVersion = "{AWG_NDK}"

    defaultConfig {{
        minSdk = 24
        ndk {{
            abiFilters += "arm64-v8a"
        }}
    }}

    compileOptions {{
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }}

    externalNativeBuild {{
        cmake {{
            path("tools/CMakeLists.txt")
        }}
    }}

    testOptions.unitTests.all {{
        it.testLogging {{
            events(TestLogEvent.PASSED, TestLogEvent.SKIPPED, TestLogEvent.FAILED)
        }}
    }}

    buildTypes {{
        all {{
            externalNativeBuild {{
                cmake {{
                    targets("libwg-go.so", "libwg.so", "libwg-quick.so")
                    arguments("-DGRADLE_USER_HOME=${{project.gradle.gradleUserHomeDir}}")
                }}
            }}
        }}
        release {{
            externalNativeBuild {{
                cmake {{
                    arguments("-DANDROID_PACKAGE_NAME={AWG_PACKAGE}")
                }}
            }}
        }}
        debug {{
            externalNativeBuild {{
                cmake {{
                    arguments("-DANDROID_PACKAGE_NAME={AWG_PACKAGE}.debug")
                }}
            }}
        }}
    }}

    lint {{
        disable += "LongLogTag"
        disable += "NewApi"
    }}
}}

dependencies {{
    implementation("androidx.annotation:annotation:1.7.1")
    implementation("androidx.collection:collection:1.4.0")
    compileOnly("com.google.code.findbugs:jsr305:3.0.2")
    testImplementation("junit:junit:4.13.2")
}}
''',
        encoding="utf-8",
    )


def _insert_android_packaging(text: str, *, kotlin_dsl: bool) -> str:
    """Configure native library extraction in the app Gradle module.

    AGP 4.2+ rejects android:extractNativeLibs in an application manifest.
    The equivalent app-module DSL is jniLibs.useLegacyPackaging.
    """
    if "useLegacyPackaging" in text:
        return text
    match = re.search(r"android\s*\{", text)
    if not match:
        raise SystemExit("Android android { ... } block not found.")
    if kotlin_dsl:
        payload = (
            "\n    packaging {\n"
            "        jniLibs {\n"
            "            useLegacyPackaging = true\n"
            "        }\n"
            "    }\n"
        )
    else:
        payload = (
            "\n    packagingOptions {\n"
            "        jniLibs {\n"
            "            useLegacyPackaging true\n"
            "        }\n"
            "    }\n"
        )
    return text[: match.end()] + payload + text[match.end() :]


def _patch_android_gradle() -> None:
    gradle_candidates = [
        ROOT / "android/app/build.gradle.kts",
        ROOT / "android/app/build.gradle",
    ]
    gradle = next((path for path in gradle_candidates if path.exists()), None)
    if gradle is None:
        raise SystemExit("Android Gradle file not found. Run flutter create first.")
    text = gradle.read_text(encoding="utf-8")
    text = re.sub(r'namespace\s*=\s*"[^"]+"', f'namespace = "{ANDROID_PACKAGE}"', text)
    text = re.sub(r'applicationId\s*=\s*"[^"]+"', f'applicationId = "{ANDROID_PACKAGE}"', text)
    text = re.sub(r'applicationId\s+"[^"]+"', f'applicationId "{ANDROID_PACKAGE}"', text)
    text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")
    text = text.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 24")
    if "abiFilters" not in text:
        default_match = re.search(r"defaultConfig\s*\{", text)
        if not default_match:
            raise SystemExit("Android defaultConfig block not found.")
        if gradle.suffix == ".kts":
            abi_payload = '\n        ndk { abiFilters += "arm64-v8a" }\n'
        else:
            abi_payload = "\n        ndk { abiFilters 'arm64-v8a' }\n"
        text = text[:default_match.end()] + abi_payload + text[default_match.end():]

    if gradle.suffix == ".kts":
        if "ndkVersion =" in text:
            text = re.sub(r'ndkVersion\s*=\s*[^\n]+', f'ndkVersion = "{AWG_NDK}"', text)
        else:
            text = re.sub(
                r'(compileSdk\s*=\s*[^\n]+)',
                rf'\1\n    ndkVersion = "{AWG_NDK}"',
                text,
                count=1,
            )
        dependency = f'implementation(project(":{AWG_MODULE}"))'
        if dependency not in text:
            text = text.rstrip() + f'''\n\ndependencies {{
    {dependency}
}}\n'''
    else:
        if "ndkVersion " in text:
            text = re.sub(r'ndkVersion\s+[^\n]+', f'ndkVersion "{AWG_NDK}"', text)
        dependency = f"implementation project(':{AWG_MODULE}')"
        if dependency not in text:
            text = text.rstrip() + f'''\n\ndependencies {{
    {dependency}
}}\n'''
    text = _insert_android_packaging(text, kotlin_dsl=gradle.suffix == ".kts")
    gradle.write_text(text, encoding="utf-8")


def _patch_android_manifest() -> None:
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    text = manifest.read_text(encoding="utf-8")
    permissions = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
        "android.permission.POST_NOTIFICATIONS",
    ]
    missing = "".join(
        f'\n    <uses-permission android:name="{permission}" />'
        for permission in permissions
        if permission not in text
    )
    if missing:
        text = _insert_after_opening_tag(text, "manifest", missing)

    if "app.pokolenie.vpn.WarpGenActivity" not in text:
        activity = (
            '\n        <activity android:name="app.pokolenie.vpn.WarpGenActivity" '
            'android:exported="false" android:theme="@android:style/Theme.Material.NoActionBar" />\n'
        )
        text = text.replace("</application>", activity + "    </application>", 1)

    text = re.sub(r'android:label="[^"]*"', 'android:label="Поколение VPN"', text, count=1)
    text = re.sub(
        r'android:name="(?:\.MainActivity|[^\"]*MainActivity)"',
        f'android:name="{ANDROID_PACKAGE}.MainActivity"',
        text,
        count=1,
    )
    app_match = re.search(r"<application\b([^>]*)>", text, re.IGNORECASE)
    if not app_match:
        raise SystemExit("Android <application> element not found.")
    attrs = app_match.group(1)
    additions = ""
    # AGP 4.2+ requires native-library packaging to be configured in Gradle,
    # not through android:extractNativeLibs in the app manifest. Remove stale
    # values left by previous project versions before writing the tag back.
    attrs = re.sub(r'\s+android:extractNativeLibs="[^"]*"', "", attrs)
    attrs = re.sub(r'\s+android:usesCleartextTraffic="[^"]*"', "", attrs)
    if additions or attrs != app_match.group(1):
        replacement = f"<application{additions}{attrs}>"
        text = text[: app_match.start()] + replacement + text[app_match.end() :]
    manifest.write_text(text, encoding="utf-8")


def _write_main_activity() -> None:
    source_root = ROOT / "android/app/src/main"
    for path in list(source_root.rglob("MainActivity.kt")) + list(source_root.rglob("MainActivity.java")):
        path.unlink()

    target = source_root / "kotlin/app/pokolenie/vpn/MainActivity.kt"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        r'''package app.pokolenie.vpn

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Bundle
import android.util.Base64
import android.util.Log
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config
import org.amnezia.awg.crypto.KeyPair
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private object AwgRuntime {
    @Volatile
    private var backend: GoBackend? = null

    @Volatile
    private var tunnelName: String = "pokolenie-warp"

    private val tunnel = object : Tunnel {
        override fun getName(): String = tunnelName
        override fun onStateChange(newState: Tunnel.State) = Unit
    }

    @Synchronized
    private fun backend(context: Context): GoBackend {
        return backend ?: GoBackend(context.applicationContext).also { backend = it }
    }

    @Synchronized
    fun start(context: Context, configText: String, requestedName: String) {
        tunnelName = requestedName
        val config = Config.parse(
            ByteArrayInputStream(configText.toByteArray(Charsets.UTF_8)),
        )
        backend(context).setState(tunnel, Tunnel.State.UP, config)
    }

    @Synchronized
    fun stop() {
        backend?.setState(tunnel, Tunnel.State.DOWN, null)
    }

    @Synchronized
    fun state(): String {
        return if (backend?.getState(tunnel) == Tunnel.State.UP) "up" else "down"
    }

    @Synchronized
    fun lastHandshake(): Long = backend?.getLastHandshake(tunnel) ?: -3L
}

class MainActivity : FlutterActivity() {
    companion object {
        private const val AWG_CHANNEL = "app.pokolenie/awg"
        private const val WARPGEN_CHANNEL = "app.pokolenie/warpgen"
        private const val VPN_PERMISSION_REQUEST = 9317
        private const val WARPGEN_REQUEST = 9318
        private const val TAG = "Pokolenie/AWG"
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingWarpGenResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, AWG_CHANNEL).setMethodCallHandler(::handleAwgCall)
        MethodChannel(messenger, WARPGEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "generateKeyPair" -> {
                    try {
                        val pair = KeyPair()
                        result.success(
                            mapOf(
                                "privateKey" to pair.privateKey.toBase64(),
                                "publicKey" to pair.publicKey.toBase64(),
                            ),
                        )
                    } catch (error: Throwable) {
                        result.error(
                            "KEY_GENERATION",
                            error.message ?: error.javaClass.simpleName,
                            Log.getStackTraceString(error),
                        )
                    }
                }
                "openAndCapture" -> openWarpGen(
                    call.argument<String>("url") ?: "https://warpgen.net",
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun openWarpGen(url: String, result: MethodChannel.Result) {
        if (pendingWarpGenResult != null) {
            result.error("WARPGEN_BUSY", "WarpGen уже открыт.", null)
            return
        }
        pendingWarpGenResult = result
        startActivityForResult(
            Intent(this, WarpGenActivity::class.java).putExtra(WarpGenActivity.EXTRA_URL, url),
            WARPGEN_REQUEST,
        )
    }

    private fun probeNetwork(
        network: android.net.Network?,
        requiredSuccesses: Int,
    ): Map<String, Any> {
        if (network == null) {
            return mapOf(
                "success" to false,
                "latencyMs" to 0,
                "detail" to "Requested Android network not found",
            )
        }
        val targets = listOf(
            "https://cp.cloudflare.com/generate_204" to setOf(200, 204),
            "https://www.gstatic.com/generate_204" to setOf(200, 204),
            "https://www.msftconnecttest.com/connecttest.txt" to setOf(200, 204),
        )
        var successes = 0
        var totalLatency = 0L
        val failures = mutableListOf<String>()
        for ((url, acceptedCodes) in targets) {
            val started = android.os.SystemClock.elapsedRealtime()
            val connection = network.openConnection(URL(url)) as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 4_000
                connection.readTimeout = 4_000
                connection.useCaches = false
                connection.setRequestProperty("Cache-Control", "no-cache")
                val code = connection.responseCode
                try {
                    connection.inputStream?.close()
                } catch (_: Throwable) {
                    try { connection.errorStream?.close() } catch (_: Throwable) {}
                }
                if (code in acceptedCodes) {
                    successes += 1
                    totalLatency += android.os.SystemClock.elapsedRealtime() - started
                } else {
                    failures += "$url returned HTTP $code"
                }
            } catch (error: Throwable) {
                failures += "$url: ${error.message ?: error.javaClass.simpleName}"
            } finally {
                connection.disconnect()
            }
        }
        val success = successes >= requiredSuccesses
        return mapOf(
            "success" to success,
            "latencyMs" to if (successes == 0) 0 else totalLatency / successes,
            "detail" to if (success) {
                "$successes/${targets.size} HTTPS checks passed on the requested network"
            } else {
                "$successes/${targets.size} HTTPS checks passed: ${failures.joinToString("; ")}"
            },
        )
    }

    private fun handleAwgCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestVpnPermission(result)
            "start" -> {
                val config = call.argument<String>("config")
                val name = sanitizeTunnelName(call.argument<String>("name") ?: "pokolenie-warp")
                if (config.isNullOrBlank()) {
                    result.error("AWG_CONFIG", "Конфигурация AmneziaWG пуста.", null)
                    return
                }
                executor.execute {
                    try {
                        AwgRuntime.start(applicationContext, config, name)
                        runOnUiThread { result.success(true) }
                    } catch (error: Throwable) {
                        Log.e(TAG, "Unable to start AmneziaWG", error)
                        runOnUiThread {
                            result.error(
                                "AWG_START",
                                error.message ?: error.javaClass.simpleName,
                                Log.getStackTraceString(error),
                            )
                        }
                    }
                }
            }
            "stop" -> executor.execute {
                try {
                    AwgRuntime.stop()
                    runOnUiThread { result.success(true) }
                } catch (error: Throwable) {
                    Log.e(TAG, "Unable to stop AmneziaWG", error)
                    runOnUiThread {
                        result.error(
                            "AWG_STOP",
                            error.message ?: error.javaClass.simpleName,
                            Log.getStackTraceString(error),
                        )
                    }
                }
            }
            "state" -> result.success(AwgRuntime.state())
            "networkStatus" -> executor.execute {
                try {
                    val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val vpnNetwork = manager.allNetworks.firstOrNull { network ->
                        manager.getNetworkCapabilities(network)
                            ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
                    }
                    val capabilities = vpnNetwork?.let(manager::getNetworkCapabilities)
                    val properties = vpnNetwork?.let(manager::getLinkProperties)
                    val value = mapOf(
                        "vpnPresent" to (vpnNetwork != null),
                        "hasInternetCapability" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true),
                        "validated" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
                        "interfaceName" to (properties?.interfaceName ?: ""),
                    )
                    runOnUiThread { result.success(value) }
                } catch (error: Throwable) {
                    runOnUiThread {
                        result.error(
                            "AWG_NETWORK_STATUS",
                            error.message ?: error.javaClass.simpleName,
                            Log.getStackTraceString(error),
                        )
                    }
                }
            }
            "baseNetworkStatus" -> executor.execute {
                try {
                    val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val network = manager.activeNetwork
                    val capabilities = network?.let(manager::getNetworkCapabilities)
                    val properties = network?.let(manager::getLinkProperties)
                    val value = mapOf(
                        "vpnPresent" to (network != null),
                        "hasInternetCapability" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true),
                        "validated" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
                        "interfaceName" to (properties?.interfaceName ?: ""),
                    )
                    runOnUiThread { result.success(value) }
                } catch (error: Throwable) {
                    runOnUiThread {
                        result.error(
                            "BASE_NETWORK_STATUS",
                            error.message ?: error.javaClass.simpleName,
                            Log.getStackTraceString(error),
                        )
                    }
                }
            }
            "probeBaseNetwork" -> executor.execute {
                try {
                    val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val value = probeNetwork(manager.activeNetwork, 1)
                    runOnUiThread { result.success(value) }
                } catch (error: Throwable) {
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "success" to false,
                                "latencyMs" to 0,
                                "detail" to (error.message ?: error.javaClass.simpleName),
                            ),
                        )
                    }
                }
            }
            "probeVpnNetwork" -> executor.execute {
                try {
                    val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val vpnNetwork = manager.allNetworks.firstOrNull { network ->
                        manager.getNetworkCapabilities(network)
                            ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
                    }
                    val value = probeNetwork(vpnNetwork, 2)
                    runOnUiThread { result.success(value) }
                } catch (error: Throwable) {
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "success" to false,
                                "latencyMs" to 0,
                                "detail" to (error.message ?: error.javaClass.simpleName),
                            ),
                        )
                    }
                }
            }
            "lastHandshake" -> executor.execute {
                try {
                    val value = AwgRuntime.lastHandshake()
                    runOnUiThread { result.success(value) }
                } catch (error: Throwable) {
                    runOnUiThread {
                        result.error(
                            "AWG_HANDSHAKE",
                            error.message ?: error.javaClass.simpleName,
                            Log.getStackTraceString(error),
                        )
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("VPN_PERMISSION_BUSY", "Запрос разрешения уже открыт.", null)
            return
        }
        pendingPermissionResult = result
        startActivityForResult(intent, VPN_PERMISSION_REQUEST)
    }

    @Deprecated("Deprecated in Android SDK, retained for activity results")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            VPN_PERMISSION_REQUEST -> {
                val pending = pendingPermissionResult
                pendingPermissionResult = null
                pending?.success(resultCode == Activity.RESULT_OK)
                return
            }
            WARPGEN_REQUEST -> {
                val pending = pendingWarpGenResult
                pendingWarpGenResult = null
                if (resultCode == Activity.RESULT_OK) {
                    pending?.success(data?.getStringExtra(WarpGenActivity.EXTRA_CONFIG))
                } else {
                    pending?.success(null)
                }
                return
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun sanitizeTunnelName(value: String): String {
        val safe = value.replace(Regex("[^a-zA-Z0-9_=+.-]"), "-")
        return when {
            safe.isBlank() -> "pokolenie"
            safe.length <= Tunnel.NAME_MAX_LENGTH -> safe
            else -> safe.substring(0, Tunnel.NAME_MAX_LENGTH)
        }
    }
}

class WarpGenActivity : Activity(), DownloadListener {
    companion object {
        const val EXTRA_CONFIG = "warpgen_config"
        const val EXTRA_URL = "warpgen_url"
        private const val START_URL = "https://warpgen.net/"
    }

    private lateinit var webView: WebView
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile
    private var completed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        webView = WebView(this)
        webView.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        setContentView(webView)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.allowFileAccess = false
        webView.settings.allowContentAccess = false
        webView.webChromeClient = WebChromeClient()
        webView.addJavascriptInterface(ConfigBridge(), "PokolenieBridge")
        webView.setDownloadListener(this)
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                return handleNavigation(view, request.url.toString())
            }

            @Deprecated("Deprecated in Android SDK, retained for older WebView")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
                return handleNavigation(view, url)
            }

            override fun onPageFinished(view: WebView, url: String) {
                super.onPageFinished(view, url)
                if (isAllowedPage(url)) installDownloadHook()
            }
        }
        val requested = intent.getStringExtra(EXTRA_URL) ?: START_URL
        webView.loadUrl(if (isAllowedPage(requested)) requested else START_URL)
    }


    private fun isAllowedPage(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val parsed = try { android.net.Uri.parse(url) } catch (_: Throwable) { return false }
        val host = parsed.host?.lowercase() ?: return false
        return parsed.scheme == "https" &&
            (host == "warpgen.net" || host == "warp-gen.github.io")
    }

    private fun handleNavigation(view: WebView, url: String): Boolean {
        if (url.startsWith("blob:") || url.startsWith("data:")) {
            if (isAllowedPage(view.url)) captureBrowserUrl(url)
            return true
        }
        return !isAllowedPage(url)
    }

    override fun onDownloadStart(
        url: String,
        userAgent: String,
        contentDisposition: String,
        mimetype: String,
        contentLength: Long,
    ) {
        if (isAllowedPage(webView.url)) captureBrowserUrl(url, userAgent)
    }

    private fun installDownloadHook() {
        if (!isAllowedPage(webView.url)) return
        val script = """
            (() => {
              if (window.__pokolenieHooked) return;
              window.__pokolenieHooked = true;
              const looksLikeConfig = (text) =>
                typeof text === 'string' && text.length >= 80 && text.length <= 250000 &&
                (/\[Interface\]/i.test(text) || /PrivateKey/i.test(text) || /AllowedIPs/i.test(text));
              const deliver = (text) => {
                if (looksLikeConfig(text)) PokolenieBridge.deliverText(text);
              };
              const inspectPage = () => {
                deliver(document.body ? document.body.innerText : '');
                document.querySelectorAll('textarea, pre, code, input').forEach((element) => {
                  deliver(element.value || element.textContent || '');
                });
              };
              try {
                if (navigator.clipboard && navigator.clipboard.writeText) {
                  const originalWriteText = navigator.clipboard.writeText.bind(navigator.clipboard);
                  navigator.clipboard.writeText = (text) => {
                    deliver(String(text || ''));
                    return originalWriteText(text);
                  };
                }
              } catch (_) {}
              try {
                const originalCreateObjectUrl = URL.createObjectURL.bind(URL);
                URL.createObjectURL = (object) => {
                  const generatedUrl = originalCreateObjectUrl(object);
                  if (object instanceof Blob) {
                    object.text().then(deliver).catch(() => {});
                  }
                  return generatedUrl;
                };
              } catch (_) {}
              document.addEventListener('click', (event) => {
                const link = event.target && event.target.closest ? event.target.closest('a') : null;
                if (!link || !link.href) {
                  setTimeout(inspectPage, 700);
                  return;
                }
                if (link.href.startsWith('blob:') || link.href.startsWith('data:')) {
                  event.preventDefault();
                  fetch(link.href).then(r => r.text()).then(deliver).catch(() => {});
                } else {
                  setTimeout(inspectPage, 700);
                }
              }, true);
              new MutationObserver(inspectPage).observe(document.documentElement, {
                childList: true,
                subtree: true,
                characterData: true,
                attributes: true,
              });
              setInterval(inspectPage, 1200);
              inspectPage();
            })();
        """.trimIndent()
        webView.evaluateJavascript(script, null)
    }

    private fun captureBrowserUrl(url: String, userAgent: String = webView.settings.userAgentString) {
        when {
            url.startsWith("blob:") -> {
                val quoted = org.json.JSONObject.quote(url)
                val script = "fetch($quoted).then(r=>r.text()).then(t=>PokolenieBridge.deliverText(t)).catch(()=>{});"
                webView.evaluateJavascript(script, null)
            }
            url.startsWith("data:") -> {
                executor.execute {
                    try {
                        val payload = decodeDataUrl(url)
                        finishWithConfig(payload)
                    } catch (_: Throwable) {}
                }
            }
            else -> executor.execute {
                if (!isAllowedPage(url)) return@execute
                try {
                    val connection = URL(url).openConnection() as HttpURLConnection
                    connection.instanceFollowRedirects = true
                    connection.connectTimeout = 20_000
                    connection.readTimeout = 20_000
                    connection.setRequestProperty("User-Agent", userAgent)
                    CookieManager.getInstance().getCookie(url)?.let {
                        connection.setRequestProperty("Cookie", it)
                    }
                    val text = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                    finishWithConfig(text)
                } catch (error: Throwable) {
                    Log.w("Pokolenie/WarpGen", "Download interception failed", error)
                }
            }
        }
    }

    private fun decodeDataUrl(url: String): String {
        val comma = url.indexOf(',')
        require(comma > 0) { "Invalid data URL" }
        val metadata = url.substring(0, comma)
        val payload = url.substring(comma + 1)
        return if (metadata.contains(";base64")) {
            String(Base64.decode(payload, Base64.DEFAULT), Charsets.UTF_8)
        } else {
            URLDecoder.decode(payload, "UTF-8")
        }
    }

    private fun collectEmbeddedStrings(value: Any?, output: MutableList<String>) {
        when (value) {
            is String -> if (value.isNotBlank()) output += value
            is org.json.JSONObject -> {
                val keys = value.keys()
                while (keys.hasNext()) collectEmbeddedStrings(value.opt(keys.next()), output)
            }
            is org.json.JSONArray -> {
                for (index in 0 until value.length()) {
                    collectEmbeddedStrings(value.opt(index), output)
                }
            }
        }
    }

    private fun extractPlainConfig(raw: String): String? {
        val normalized = raw.replace("\r\n", "\n")
        val allowed = setOf(
            "privatekey", "address", "dns", "mtu", "listenport", "table", "fwmark",
            "jc", "jmin", "jmax", "s1", "s2", "s3", "s4",
            "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5",
            "publickey", "presharedkey", "allowedips", "endpoint",
            "persistentkeepalive", "reserved",
        )
        val output = mutableListOf<String>()
        var section = ""
        var sawInterface = false
        var sawPeer = false
        for (rawLine in normalized.lines()) {
            val line = rawLine.trim()
            if (line.equals("[Interface]", ignoreCase = true)) {
                if (sawInterface) break
                section = "interface"
                sawInterface = true
                output += "[Interface]"
                continue
            }
            if (line.equals("[Peer]", ignoreCase = true) && sawInterface) {
                if (sawPeer) break
                section = "peer"
                sawPeer = true
                output += ""
                output += "[Peer]"
                continue
            }
            if (section.isEmpty()) continue
            if (line.startsWith("[") && line.endsWith("]")) {
                if (sawPeer) break
                continue
            }
            if (line.isEmpty() || line.startsWith("#") || line.startsWith(";")) continue
            val separator = line.indexOf('=')
            if (separator <= 0) continue
            val key = line.substring(0, separator).trim().lowercase()
            if (key in allowed) output += line
        }
        if (!sawInterface || !sawPeer) return null
        val result = output.joinToString("\n").trim()
        val lower = result.lowercase()
        if (!lower.contains("privatekey =") ||
            !lower.contains("publickey =") ||
            !lower.contains("allowedips =") ||
            !lower.contains("endpoint =") ||
            !lower.contains("address =")) return null
        return "$result\n"
    }

    private fun extractConfig(raw: String): String? {
        val queue = mutableListOf(raw)
        val seen = mutableSetOf<String>()
        var inspected = 0
        while (queue.isNotEmpty() && inspected < 80) {
            val candidate = queue.removeAt(0).trim()
            if (candidate.isEmpty() || !seen.add(candidate)) continue
            inspected += 1
            extractPlainConfig(candidate)?.let { return it }

            val unescaped = candidate
                .replace("\\r\\n", "\n")
                .replace("\\n", "\n")
                .replace("&#91;", "[")
                .replace("&#93;", "]")
                .replace("&lbrack;", "[")
                .replace("&rbrack;", "]")
                .replace("&equals;", "=")
                .replace("&amp;", "&")
            if (unescaped != candidate) queue += unescaped

            try {
                val decodedJson = org.json.JSONTokener(candidate).nextValue()
                collectEmbeddedStrings(decodedJson, queue)
            } catch (_: Throwable) {}

            val compact = candidate.replace(Regex("\\s+"), "")
            if (compact.length in 80..200000 &&
                compact.matches(Regex("^[A-Za-z0-9+/_=-]+$"))) {
                try {
                    queue += String(Base64.decode(compact, Base64.DEFAULT), Charsets.UTF_8)
                } catch (_: Throwable) {}
            }
        }
        return null
    }

    private fun finishWithConfig(raw: String) {
        val config = extractConfig(raw) ?: return
        if (completed) return
        completed = true
        runOnUiThread {
            setResult(
                RESULT_OK,
                Intent().putExtra(EXTRA_CONFIG, config),
            )
            finish()
        }
    }

    inner class ConfigBridge {
        @JavascriptInterface
        fun deliverText(text: String) {
            runOnUiThread {
                if (isAllowedPage(webView.url)) finishWithConfig(text)
            }
        }
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            setResult(RESULT_CANCELED)
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        webView.removeJavascriptInterface("PokolenieBridge")
        webView.destroy()
        executor.shutdownNow()
        super.onDestroy()
    }
}
''',
        encoding="utf-8",
    )


def _patch_gradle_properties() -> None:
    properties = ROOT / "android/gradle.properties"
    text = properties.read_text(encoding="utf-8") if properties.exists() else ""
    required = {
        "amneziawgPackageName": AWG_PACKAGE,
        "android.bundle.enableUncompressedNativeLibs": "false",
        "org.gradle.vfs.watch": "false",
    }
    lines = text.splitlines()
    for key, value in required.items():
        pattern = re.compile(rf"^{re.escape(key)}=")
        for index, line in enumerate(lines):
            if pattern.match(line):
                lines[index] = f"{key}={value}"
                break
        else:
            lines.append(f"{key}={value}")
    properties.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def _patch_android_icons() -> None:
    icon_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in icon_sizes.items():
        target = ROOT / "android/app/src/main/res" / folder / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "assets/images" / f"launcher_{size}.png", target)

    drawable = ROOT / "android/app/src/main/res/drawable/ic_stat_singbox_mm.xml"
    drawable.parent.mkdir(parents=True, exist_ok=True)
    drawable.write_text(
        '''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
  <path android:fillColor="#FFFFFFFF" android:pathData="M12,2L4,5.5V11c0,5.1 3.4,9.7 8,11 4.6,-1.3 8,-5.9 8,-11V5.5L12,2zM12,6a3,3 0,1 1,0 6,3 3,0 0,1 0,-6zM8,17c0,-2.2 1.8,-4 4,-4s4,1.8 4,4c-1.1,1.1 -2.5,1.9 -4,2.4C10.5,18.9 9.1,18.1 8,17z"/>
</vector>\n''',
        encoding="utf-8",
    )


def patch_android() -> None:
    _patch_awg_module()
    _patch_android_settings()
    _patch_android_gradle()
    _patch_android_manifest()
    _write_main_activity()
    _patch_gradle_properties()
    _patch_android_icons()

def patch_generated_widget_test() -> None:
    test = ROOT / "test/widget_test.dart"
    test.parent.mkdir(parents=True, exist_ok=True)
    test.write_text(
        """import 'package:flutter_test/flutter_test.dart';
import 'package:pokolenie_vpn/main.dart';

void main() {
  test('PokolenieApp can be constructed', () {
    expect(const PokolenieApp(), isA<PokolenieApp>());
  });
}
""",
        encoding="utf-8",
    )


def main() -> None:
    if not (ROOT / "android").exists():
        raise SystemExit("Android host project not found. Run flutter create first.")
    patch_generated_widget_test()
    patch_android()
    print("Patched Android + AmneziaWG platform files.")


if __name__ == "__main__":
    main()
