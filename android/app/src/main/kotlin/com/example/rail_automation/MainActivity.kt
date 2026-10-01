package com.example.rail_automation

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val OVERLAY_CHANNEL = "com.example.rail_automation/overlay"
    private val REQUEST_CODE_OVERLAY = 1001

    /** Callback to resolve the pending Flutter overlay-permission Future. */
    private var overlayPermissionResult: MethodChannel.Result? = null

    /** Receives the solved Turnstile token from TurnstileOverlayService. */
    private var tokenResult: MethodChannel.Result? = null
    private val tokenReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                TurnstileOverlayService.ACTION_TOKEN -> {
                    val token = intent.getStringExtra(TurnstileOverlayService.EXTRA_TOKEN)
                    tokenResult?.success(token)
                    tokenResult = null
                }
                TurnstileOverlayService.ACTION_CANCEL -> {
                    tokenResult?.success(null)
                    tokenResult = null
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Register receiver for token and cancellation coming back from overlay service
        val filter = IntentFilter().apply {
            addAction(TurnstileOverlayService.ACTION_TOKEN)
            addAction(TurnstileOverlayService.ACTION_CANCEL)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(tokenReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(tokenReceiver, filter)
        }
    }

    override fun onDestroy() {
        unregisterReceiver(tokenReceiver)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OVERLAY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // Check whether SYSTEM_ALERT_WINDOW is granted
                "canDrawOverlays" -> {
                    result.success(TurnstileOverlayService.canDrawOverlays(this))
                }

                // Send the user to the Settings page to grant the permission.
                // Resolves with true/false when they return.
                "requestOverlayPermission" -> {
                    if (TurnstileOverlayService.canDrawOverlays(this)) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        overlayPermissionResult = result
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        startActivityForResult(intent, REQUEST_CODE_OVERLAY)
                    } else {
                        result.success(true)          // pre-M: always granted
                    }
                }

                // Launch the floating overlay with the Turnstile challenge.
                // Resolves with the token string on success, or null on cancel.
                "showTurnstileOverlay" -> {
                    if (!TurnstileOverlayService.canDrawOverlays(this)) {
                        result.error("NO_PERMISSION", "Overlay permission not granted", null)
                        return@setMethodCallHandler
                    }
                    // Store the pending result — resolved when token broadcast arrives
                    tokenResult?.success(null)        // resolve any prior stale call
                    tokenResult = result
                    val label = call.argument<String>("contextLabel") ?: ""
                    val serviceIntent = Intent(this, TurnstileOverlayService::class.java).apply {
                        action = TurnstileOverlayService.ACTION_SHOW
                        putExtra(TurnstileOverlayService.EXTRA_CONTEXT, label)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                }

                // Stop the overlay (called on cancel / timeout from Flutter)
                "dismissTurnstileOverlay" -> {
                    stopService(Intent(this, TurnstileOverlayService::class.java))
                    tokenResult?.success(null)
                    tokenResult = null
                    result.success(null)
                }

                // Saves PDF bytes to Downloads and opens the PDF viewer
                "saveAndOpenPdf" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName") ?: "rail_ticket.pdf"
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Bytes cannot be null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = savePdfToDownloads(bytes, fileName)
                        openPdfIntent(uri)
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun savePdfToDownloads(bytes: ByteArray, fileName: String): Uri {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/RailPro")
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw IllegalStateException("Failed to create download entry in MediaStore")
            contentResolver.openOutputStream(uri)?.use { os ->
                os.write(bytes)
            }
            return uri
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "RailPro")
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, fileName)
            file.writeBytes(bytes)
            return FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        }
    }

    private fun openPdfIntent(uri: Uri) {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/pdf")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val chooser = Intent.createChooser(intent, "Open Ticket PDF")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)
        } catch (_: Exception) {}
    }

    // ── Permission result ────────────────────────────────────────────────────

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_OVERLAY) {
            val granted = TurnstileOverlayService.canDrawOverlays(this)
            overlayPermissionResult?.success(granted)
            overlayPermissionResult = null
        }
    }
}
