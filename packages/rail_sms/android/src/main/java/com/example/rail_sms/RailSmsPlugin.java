package com.example.rail_sms;

import android.app.Activity;
import android.app.Application;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Bundle;
import androidx.annotation.NonNull;
import com.google.android.gms.auth.api.phone.SmsRetriever;
import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.GoogleApiAvailability;
import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.common.api.Status;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;

public class RailSmsPlugin implements FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
    private MethodChannel methods;
    private EventChannel events;
    private ActivityPluginBinding activityBinding;
    private static final int SMS_CONSENT_REQUEST = 852;
    // UI and foreground-service Flutter engines share one Android SMS session.
    private static Context context;
    private static RailSmsPlugin activityOwner;
    private static Activity resumedActivity;
    private static boolean lifecycleRegistered;
    private static BroadcastReceiver receiver;
    private static Intent pendingConsent;
    private static String pendingMessage;
    private static boolean consentInFlight;
    private static boolean starting;
    private static final Map<RailSmsPlugin, EventChannel.EventSink> sinks = new LinkedHashMap<>();
    private static final ArrayList<MethodChannel.Result> preparations = new ArrayList<>();

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        registerLifecycle();
        methods = new MethodChannel(binding.getBinaryMessenger(), "com.example.rail_automation/sms");
        methods.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "hasSmsPermission":
                case "requestSmsPermission":
                    // No READ_SMS grant: Google asks for this one message after it arrives.
                    result.success(available());
                    break;
                case "prepareListening":
                case "startListening":
                    prepare(result);
                    break;
                case "promptPendingConsent":
                    result.success(promptConsent());
                    break;
                default:
                    result.notImplemented();
            }
        });
        events = new EventChannel(binding.getBinaryMessenger(), "com.example.rail_automation/sms_stream");
        events.setStreamHandler(new EventChannel.StreamHandler() {
            @Override public void onListen(Object args, EventChannel.EventSink sink) {
                sinks.put(RailSmsPlugin.this, sink);
                if (pendingMessage != null) {
                    deliver(pendingMessage);
                } else {
                    // Subscribe to an already-armed session without restarting it.
                    prepare(null);
                    promptConsent();
                }
            }
            @Override public void onCancel(Object args) {
                removeSink();
            }
        });
    }

    private static boolean available() {
        return GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
            == ConnectionResult.SUCCESS;
    }

    private static void completePreparations(boolean ok) {
        starting = false;
        ArrayList<MethodChannel.Result> results = new ArrayList<>(preparations);
        preparations.clear();
        for (MethodChannel.Result result : results) result.success(ok);
    }

    private static void prepare(MethodChannel.Result result) {
        if (starting) {
            if (result != null) preparations.add(result);
            return;
        }
        if (receiver != null || pendingConsent != null || consentInFlight || pendingMessage != null) {
            if (result != null) result.success(true);
            return;
        }
        if (!available()) {
            if (result != null) result.success(false);
            fail("SMS_UNAVAILABLE", "Google SMS consent is unavailable. Enter the OTP manually.");
            return;
        }
        starting = true;
        if (result != null) preparations.add(result);
        try {
            receiver = new BroadcastReceiver() {
                @Override public void onReceive(Context c, Intent intent) {
                    if (intent == null || !SmsRetriever.SMS_RETRIEVED_ACTION.equals(intent.getAction())) return;
                    Bundle extras = intent.getExtras();
                    if (extras == null) return;
                    Status status = (Status) extras.get(SmsRetriever.EXTRA_STATUS);
                    if (status == null) return;
                    if (status.getStatusCode() == CommonStatusCodes.TIMEOUT) {
                        fail("SMS_TIMEOUT", "Enter the OTP manually or resend it.");
                    } else if (status.getStatusCode() == CommonStatusCodes.SUCCESS) {
                        pendingConsent = Build.VERSION.SDK_INT >= 33
                            ? extras.getParcelable(SmsRetriever.EXTRA_CONSENT_INTENT, Intent.class)
                            : extras.getParcelable(SmsRetriever.EXTRA_CONSENT_INTENT);
                        stopReceiver();
                        if (pendingConsent == null) {
                            fail("SMS_UNAVAILABLE", "SMS consent is unavailable. Enter the OTP manually.");
                        } else {
                            promptConsent();
                        }
                    }
                }
            };
            IntentFilter filter = new IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION);
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, SmsRetriever.SEND_PERMISSION, null, Context.RECEIVER_EXPORTED);
            } else {
                context.registerReceiver(receiver, filter, SmsRetriever.SEND_PERMISSION, null);
            }
            SmsRetriever.getClient(context).startSmsUserConsent(null)
                .addOnSuccessListener(unused -> completePreparations(true))
                .addOnFailureListener(error -> {
                    completePreparations(false);
                    fail("SMS_UNAVAILABLE", "Google SMS consent is unavailable. Enter the OTP manually.");
                });
        } catch (Exception error) {
            completePreparations(false);
            fail("SMS_UNAVAILABLE", "Enter the OTP manually.");
        }
    }

    private static boolean promptConsent() {
        if (pendingConsent == null || consentInFlight || activityOwner == null) return false;
        Activity activity = activityOwner.activityBinding.getActivity();
        // Never open Google's UI over another app; retain it until this Activity resumes.
        if (activity != resumedActivity || activity.isFinishing() || activity.isDestroyed()) return false;
        try {
            activity.startActivityForResult(pendingConsent, SMS_CONSENT_REQUEST);
            pendingConsent = null;
            consentInFlight = true;
            return true;
        } catch (Exception error) {
            return false;
        }
    }

    private static void deliver(String message) {
        pendingMessage = message;
        EventChannel.EventSink sink = sinks.get(activityOwner);
        if (sink == null) {
            for (EventChannel.EventSink candidate : sinks.values()) sink = candidate;
        }
        if (sink == null) return; // SMS may arrive before Dart has saved awaitingOtp.
        Map<String, Object> data = new HashMap<>();
        data.put("sender", ""); // Consent provides no sender; Dart validates Railway branding.
        data.put("body", message);
        pendingMessage = null;
        sink.success(data); // One engine owns verification, never broadcast the OTP to both.
    }

    private static void stopReceiver() {
        if (receiver != null) {
            try { context.unregisterReceiver(receiver); } catch (Exception ignored) {}
            receiver = null;
        }
    }

    private static void fail(String code, String message) {
        stopReceiver();
        pendingConsent = null;
        pendingMessage = null;
        for (EventChannel.EventSink sink : new ArrayList<>(sinks.values())) sink.error(code, message, null);
    }

    private void removeSink() {
        sinks.remove(this);
        if (sinks.isEmpty()) {
            stopReceiver();
            pendingConsent = null;
            pendingMessage = null;
            boolean closeConsent = consentInFlight;
            consentInFlight = false;
            if (closeConsent && activityOwner != null) {
                activityOwner.activityBinding.getActivity().finishActivity(SMS_CONSENT_REQUEST);
            }
        }
    }

    private static void registerLifecycle() {
        if (lifecycleRegistered) return;
        ((Application) context.getApplicationContext()).registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override public void onActivityResumed(Activity activity) {
                resumedActivity = activity;
                promptConsent();
            }
            @Override public void onActivityPaused(Activity activity) {
                if (resumedActivity == activity) resumedActivity = null;
            }
            @Override public void onActivityCreated(Activity a, Bundle b) {}
            @Override public void onActivityStarted(Activity a) {}
            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
            @Override public void onActivityDestroyed(Activity a) {}
        });
        lifecycleRegistered = true;
    }

    @Override public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != SMS_CONSENT_REQUEST) return false;
        if (!consentInFlight) return true; // Ignore a result from a cancelled OTP session.
        consentInFlight = false;
        if (resultCode == Activity.RESULT_OK && data != null) {
            String message = data.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE);
            if (message != null && !message.isEmpty()) deliver(message);
            else fail("SMS_UNAVAILABLE", "No SMS was returned. Enter the OTP manually.");
        } else {
            fail("SMS_DECLINED", "SMS consent declined. Enter the OTP manually.");
        }
        return true;
    }

    @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        activityOwner = this;
        binding.addActivityResultListener(this);
        if (binding.getActivity().hasWindowFocus()) resumedActivity = binding.getActivity();
        promptConsent();
    }
    @Override public void onDetachedFromActivityForConfigChanges() { detach(); }
    @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) { onAttachedToActivity(binding); }
    @Override public void onDetachedFromActivity() { detach(); }
    private void detach() {
        if (activityBinding != null) activityBinding.removeActivityResultListener(this);
        if (activityOwner == this) {
            activityOwner = null;
            resumedActivity = null;
        }
        activityBinding = null;
    }
    @Override public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        // Engine teardown is a handoff, not user cancellation. Keep a prepared
        // capture alive for the UI engine (or Google's five-minute timeout).
        sinks.remove(this);
        detach();
        if (methods != null) methods.setMethodCallHandler(null);
        if (events != null) events.setStreamHandler(null);
    }
}
