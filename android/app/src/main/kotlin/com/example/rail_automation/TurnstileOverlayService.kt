package com.example.rail_automation

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.*
import android.webkit.*
import android.widget.*
import androidx.core.app.NotificationCompat

/**
 * System-alert-window overlay service that displays the Cloudflare Turnstile
 * challenge over whatever is currently on screen (including other apps).
 *
 * Started by MainActivity when the monitor detects a Turnstile requirement.
 * Sends the solved token back to Flutter via the TURNSTILE_TOKEN broadcast.
 */
class TurnstileOverlayService : Service() {

    companion object {
        const val ACTION_SHOW   = "rail.turnstile.SHOW"
        const val ACTION_TOKEN  = "rail.turnstile.TOKEN"
        const val ACTION_CANCEL = "rail.turnstile.CANCEL"
        const val EXTRA_TOKEN   = "token"
        const val EXTRA_CONTEXT = "context_label"

        private const val NOTIF_CHANNEL = "rail_turnstile_overlay"
        private const val NOTIF_ID      = 88881

        fun canDrawOverlays(ctx: Context) =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(ctx)

        // language=JS
        val TURNSTILE_SCRIPT = """
(function () {
  function post(o) { try { TurnstileBridge.postMessage(JSON.stringify(o)); } catch (e) {} }
  if (window.__rsTs) { if (window.__rsRender) window.__rsRender(); return; }
  window.__rsTs = true;
  var KEYS = ['0x4AAAAAACNkZ_TxQr_zpcZW', '0x4AAAAAAB5VTjZ90pUxRuXR'];
  var keyIdx = 0, widgetId = null;
  var st = document.createElement('style');
  st.textContent = 'html,body{background:transparent!important;overflow:hidden!important}' +
    'body{display:none!important}' +
    '#rs-ts{position:fixed;left:0;top:0;right:0;bottom:0;display:flex;align-items:center;justify-content:center}';
  document.head.appendChild(st);
  var box = document.createElement('div');
  box.id = 'rs-ts';
  document.documentElement.appendChild(box);
  function render() {
    if (widgetId !== null) { try { turnstile.remove(widgetId); } catch (e) {} widgetId = null; }
    box.innerHTML = '';
    try {
      widgetId = turnstile.render(box, {
        sitekey: KEYS[keyIdx], theme: 'auto', retry: 'auto', 'refresh-expired': 'auto',
        callback: function (t) { post({ status: 'SUCCESS', token: t }); },
        'error-callback': function (c) {
          if (keyIdx < KEYS.length - 1) { keyIdx++; setTimeout(render, 300); }
          else { post({ status: 'ERROR', message: String(c) }); }
          return true;
        },
        'expired-callback': function () { post({ status: 'READY' }); },
        'timeout-callback': function () { post({ status: 'READY' }); }
      });
      post({ status: 'READY' });
    } catch (e) { post({ status: 'ERROR', message: String(e) }); }
  }
  window.__rsRender = render;
  if (window.turnstile && window.turnstile.render) { render(); return; }
  var s = document.createElement('script');
  s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
  s.async = true; s.onload = render;
  s.onerror = function () { post({ status: 'ERROR', message: 'Could not reach Cloudflare' }); };
  document.head.appendChild(s);
})();
""".trimIndent()
    }

    private var windowManager: WindowManager? = null
    private var overlayRoot: View? = null

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        val notif = NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Verify human")
            .setContentText("Tap to verify and continue booking")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        startForeground(NOTIF_ID, notif)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val label = intent?.getStringExtra(EXTRA_CONTEXT) ?: ""
        showOverlay(label)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }

    // ── Overlay window ───────────────────────────────────────────────────────

    private fun showOverlay(contextLabel: String) {
        if (overlayRoot != null) return
        if (!canDrawOverlays(this)) { stopSelf(); return }

        val inflater = LayoutInflater.from(this)
        val root = inflater.inflate(R.layout.overlay_turnstile, null)
        overlayRoot = root

        if (contextLabel.isNotEmpty()) {
            root.findViewById<TextView>(R.id.tvContextLabel)?.let {
                it.text = contextLabel
                it.visibility = View.VISIBLE
            }
        }

        root.findViewById<View>(R.id.btnClose)?.setOnClickListener {
            sendBroadcast(Intent(ACTION_CANCEL).apply { setPackage(packageName) })
            removeOverlay()
            stopSelf()
        }

        root.findViewById<TextView>(R.id.btnCancelText)?.setOnClickListener {
            sendBroadcast(Intent(ACTION_CANCEL).apply { setPackage(packageName) })
            removeOverlay()
            stopSelf()
        }

        // Animate passenger boarding the train
        root.findViewById<View>(R.id.ivPassenger)?.let { passenger ->
            val anim = android.animation.ObjectAnimator.ofFloat(passenger, "translationX", 0f, 100f).apply {
                duration = 2200
                repeatCount = android.animation.ValueAnimator.INFINITE
                repeatMode = android.animation.ValueAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }
            anim.start()
        }

        val webView = root.findViewById<WebView>(R.id.webViewTurnstile)
        setupWebView(webView)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.CENTER

        try {
            windowManager?.addView(root, params)
        } catch (_: Exception) {
            stopSelf()
        }
    }

    private fun removeOverlay() {
        overlayRoot?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        overlayRoot = null
    }

    // ── WebView ──────────────────────────────────────────────────────────────

    @Suppress("SetJavaScriptEnabled")
    private fun setupWebView(webView: WebView) {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
        }
        webView.setBackgroundColor(Color.TRANSPARENT)

        webView.addJavascriptInterface(object : Any() {
            @JavascriptInterface
            fun postMessage(json: String) {
                handleBridgeMessage(json)
            }
        }, "TurnstileBridge")

        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                view.evaluateJavascript(TURNSTILE_SCRIPT, null)
            }
        }
        webView.loadUrl("https://eticket.railway.gov.bd/login")
    }

    private fun handleBridgeMessage(json: String) {
        try {
            val obj = org.json.JSONObject(json)
            when (obj.optString("status")) {
                "SUCCESS" -> {
                    val token = obj.optString("token")
                    if (token.isNotEmpty()) {
                        val intent = Intent(ACTION_TOKEN).apply {
                            putExtra(EXTRA_TOKEN, token)
                            setPackage(packageName)
                        }
                        sendBroadcast(intent)
                        removeOverlay()
                        stopSelf()
                    }
                }
            }
        } catch (_: Exception) {}
    }

    // ── Notification channel ─────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                NOTIF_CHANNEL,
                "Human Verification",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Human verification overlay service" }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(ch)
        }
    }
}
