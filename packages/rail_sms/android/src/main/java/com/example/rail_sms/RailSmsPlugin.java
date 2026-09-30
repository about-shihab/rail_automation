package com.example.rail_sms;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Bundle;
import androidx.annotation.NonNull;
import com.google.android.gms.auth.api.phone.SmsRetriever;
import com.google.android.gms.auth.api.phone.SmsRetrieverClient;
import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.common.api.Status;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import java.util.HashMap;
import java.util.Map;

public class RailSmsPlugin implements FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {
    private Context context;
    private ActivityPluginBinding activityBinding;
    private MethodChannel methods;
    private EventChannel events;
    private BroadcastReceiver receiver;
    private EventChannel.EventSink currentSink;
    private static final int SMS_CONSENT_REQUEST = 852;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        methods = new MethodChannel(binding.getBinaryMessenger(), "com.example.rail_automation/sms");
        methods.setMethodCallHandler((call, result) -> {
            if (call.method.equals("hasSmsPermission") || call.method.equals("requestSmsPermission")) {
                // Google SMS Retriever API does not require runtime Android permissions
                result.success(true);
                return;
            }
            if (call.method.equals("startListening")) {
                startRetriever();
                result.success(true);
                return;
            }
            result.notImplemented();
        });

        events = new EventChannel(binding.getBinaryMessenger(), "com.example.rail_automation/sms_stream");
        events.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object args, EventChannel.EventSink sink) {
                currentSink = sink;
                startRetriever();
            }

            @Override
            public void onCancel(Object args) {
                stop();
            }
        });
    }

    private void startRetriever() {
        stopReceiver();
        try {
            SmsRetrieverClient client = SmsRetriever.getClient(context);
            // Start standard SMS Retriever (if message includes app hash)
            client.startSmsRetriever();
            // Start SMS User Consent API (prompts consent dialog for any railway OTP without hash)
            client.startSmsUserConsent(null);

            receiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context c, Intent intent) {
                    if (intent == null || !SmsRetriever.SMS_RETRIEVED_ACTION.equals(intent.getAction())) return;
                    Bundle extras = intent.getExtras();
                    if (extras == null) return;
                    Status status = (Status) extras.get(SmsRetriever.EXTRA_STATUS);
                    if (status == null) return;

                    if (status.getStatusCode() == CommonStatusCodes.SUCCESS) {
                        // Directly retrieved (e.g. from startSmsRetriever with hash)
                        String message = extras.getString(SmsRetriever.EXTRA_SMS_MESSAGE);
                        if (message != null && !message.isEmpty()) {
                            deliverSms(message);
                            return;
                        }

                        // Consent intent retrieved (from startSmsUserConsent)
                        Intent consentIntent;
                        if (Build.VERSION.SDK_INT >= 33) {
                            consentIntent = extras.getParcelable(SmsRetriever.EXTRA_CONSENT_INTENT, Intent.class);
                        } else {
                            consentIntent = extras.getParcelable(SmsRetriever.EXTRA_CONSENT_INTENT);
                        }

                        if (consentIntent != null && activityBinding != null && activityBinding.getActivity() != null) {
                            try {
                                activityBinding.getActivity().startActivityForResult(consentIntent, SMS_CONSENT_REQUEST);
                            } catch (ActivityNotFoundException ignored) {}
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
        } catch (Exception ignored) {}
    }

    private void deliverSms(String message) {
        if (currentSink == null) return;
        Map<String, Object> data = new HashMap<>();
        data.put("sender", "RAILWAY");
        data.put("body", message);
        currentSink.success(data);
    }

    private void stopReceiver() {
        if (receiver != null) {
            try {
                context.unregisterReceiver(receiver);
            } catch (Exception ignored) {}
            receiver = null;
        }
    }

    private void stop() {
        stopReceiver();
        currentSink = null;
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == SMS_CONSENT_REQUEST) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                String message = data.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE);
                if (message != null && !message.isEmpty()) {
                    deliverSms(message);
                }
            }
            return true;
        }
        return false;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addActivityResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detach();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detach();
    }

    private void detach() {
        if (activityBinding != null) {
            activityBinding.removeActivityResultListener(this);
            activityBinding = null;
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        stop();
        if (methods != null) methods.setMethodCallHandler(null);
        if (events != null) events.setStreamHandler(null);
    }
}
