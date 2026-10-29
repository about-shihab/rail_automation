package com.example.rail_automation

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * A small, VISIBLE card drawn over other apps that hosts its own Turnstile
 * widget. Shown only when a seat was found and the silent solve failed while
 * the app is minimized. The user solves it in place; the token is returned to
 * Dart through the pending MethodChannel result.
 */
object TurnstileOverlay {
    private val main = Handler(Looper.getMainLooper())
    private var root: View? = null
    private var webView: WebView? = null
    private var status: TextView? = null
    private var pending: MethodChannel.Result? = null

    private fun dp(ctx: Context, v: Int) = (v * ctx.resources.displayMetrics.density).toInt()

    @SuppressLint("SetJavaScriptEnabled")
    fun show(
        context: Context,
        siteKey: String,
        title: String,
        message: String,
        result: MethodChannel.Result,
    ) {
        main.post {
            if (root != null) {
                result.success(null) // already showing; Dart treats as no token
                return@post
            }
            val ctx = context.applicationContext
            val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager

            val card = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(ctx, 16), dp(ctx, 12), dp(ctx, 16), dp(ctx, 12))
                background = GradientDrawable().apply {
                    setColor(Color.WHITE)
                    cornerRadius = dp(ctx, 16).toFloat()
                }
                elevation = dp(ctx, 8).toFloat()
            }

            val header = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
            val titleView = TextView(ctx).apply {
                text = title
                setTextColor(Color.parseColor("#1B1B1F"))
                textSize = 15f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }
            val close = TextView(ctx).apply {
                text = "\u2715"
                textSize = 18f
                setTextColor(Color.parseColor("#6B6B72"))
                setPadding(dp(ctx, 12), 0, 0, 0)
                setOnClickListener { finish(null) }
            }
            header.addView(titleView)
            header.addView(close)

            val msg = TextView(ctx).apply {
                text = message
                setTextColor(Color.parseColor("#4A4A52"))
                textSize = 13f
                setPadding(0, dp(ctx, 4), 0, dp(ctx, 8))
            }
            status = msg

            val web = WebView(ctx).apply {
                setBackgroundColor(Color.TRANSPARENT)
                webViewClient = WebViewClient()
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.databaseEnabled = true
                CookieManager.getInstance().setAcceptCookie(true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                }
                addJavascriptInterface(Bridge(), "Rail")
                layoutParams = LinearLayout.LayoutParams(dp(ctx, 300), dp(ctx, 78))
            }
            webView = web

            card.addView(header)
            card.addView(msg)
            card.addView(web)

            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                y = dp(ctx, 96)
            }

            try {
                wm.addView(card, params)
            } catch (e: Exception) {
                webView?.destroy()
                webView = null
                status = null
                result.success(null)
                return@post
            }
            root = card
            pending = result

            // Same origin as the booking site so the site key's domain check passes.
            web.loadDataWithBaseURL(
                "https://eticket.railway.gov.bd/",
                html(siteKey),
                "text/html",
                "utf-8",
                null,
            )
        }
    }

    fun hide() {
        main.post { finish(null) }
    }

    private fun finish(token: String?) {
        val ctx = root?.context
        root?.let {
            try {
                (ctx?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.removeView(it)
            } catch (_: Exception) {
            }
        }
        webView?.apply {
            removeJavascriptInterface("Rail")
            stopLoading()
            destroy()
        }
        root = null
        webView = null
        status = null
        val r = pending
        pending = null
        r?.success(token)
    }

    private class Bridge {
        @JavascriptInterface
        fun post(json: String) {
            main.post {
                try {
                    val o = JSONObject(json)
                    val token = o.optString("token", "")
                    if (token.isNotEmpty()) {
                        finish(token)
                    } else {
                        status?.text = "Verification failed. Tap \u2715 and try from the notification."
                    }
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun html(siteKey: String): String {
        val key = JSONObject.quote(siteKey)
        return """<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:transparent;overflow:hidden}#c{display:flex;justify-content:center}</style>
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script>
</head><body><div id="c"></div><script>
function send(o){ Rail.post(JSON.stringify(o)); }
var t = setInterval(function () {
  if (!window.turnstile) return;
  clearInterval(t);
  turnstile.render('#c', {
    sitekey: $key,
    theme: 'light',
    retry: 'never',
    callback: function (tok) { send({token: tok}); },
    'error-callback': function (e) { send({error: String(e)}); return true; },
    'expired-callback': function () { send({error: 'expired'}); }
  });
}, 100);
</script></body></html>"""
    }
}

