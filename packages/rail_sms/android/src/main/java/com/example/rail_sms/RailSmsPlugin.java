package com.example.rail_sms;
import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.os.Build;
import android.provider.Telephony;
import android.telephony.SmsMessage;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.*;
import java.util.HashMap;
import java.util.Map;

public class RailSmsPlugin implements FlutterPlugin, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private Context context;
    private ActivityPluginBinding activityBinding;
    private MethodChannel methods;
    private EventChannel events;
    private MethodChannel.Result permissionResult;
    private BroadcastReceiver receiver;
    private static final int REQUEST = 721;
    private boolean allowed() { return context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED; }
    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        methods = new MethodChannel(binding.getBinaryMessenger(), "com.example.rail_automation/sms");
        methods.setMethodCallHandler((call, result) -> {
            if (call.method.equals("hasSmsPermission")) { result.success(allowed()); return; }
            if (!call.method.equals("requestSmsPermission")) { result.notImplemented(); return; }
            if (allowed()) { result.success(true); return; }
            if (activityBinding == null || permissionResult != null) { result.success(false); return; }
            permissionResult = result;
            activityBinding.getActivity().requestPermissions(new String[]{Manifest.permission.RECEIVE_SMS}, REQUEST);
        });
        events = new EventChannel(binding.getBinaryMessenger(), "com.example.rail_automation/sms_stream");
        events.setStreamHandler(new EventChannel.StreamHandler() {
            @Override public void onListen(Object args, EventChannel.EventSink sink) {
                stop();
                if (!allowed()) { sink.error("PERMISSION_DENIED", "Enter the OTP manually", null); return; }
                receiver = new BroadcastReceiver() {
                    @Override public void onReceive(Context c, Intent intent) {
                        if (!Telephony.Sms.Intents.SMS_RECEIVED_ACTION.equals(intent.getAction())) return;
                        SmsMessage[] parts = Telephony.Sms.Intents.getMessagesFromIntent(intent);
                        if (parts == null || parts.length == 0) return;
                        StringBuilder body = new StringBuilder();
                        for (SmsMessage part : parts) body.append(part.getMessageBody());
                        Map<String,Object> data = new HashMap<>();
                        data.put("sender", parts[0].getOriginatingAddress());
                        data.put("body", body.toString());
                        sink.success(data);
                    }
                };
                IntentFilter filter = new IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION);
                if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Manifest.permission.BROADCAST_SMS, null, Context.RECEIVER_EXPORTED);
                else context.registerReceiver(receiver, filter, Manifest.permission.BROADCAST_SMS, null);
            }
            @Override public void onCancel(Object args) { stop(); }
        });
    }
    private void stop() { if (receiver != null) { context.unregisterReceiver(receiver); receiver = null; } }
    @Override public boolean onRequestPermissionsResult(int request, String[] permissions, int[] grants) {
        if (request != REQUEST) return false;
        if (permissionResult != null) { permissionResult.success(allowed()); permissionResult = null; }
        return true;
    }
    @Override public void onAttachedToActivity(ActivityPluginBinding binding) { activityBinding = binding; binding.addRequestPermissionsResultListener(this); }
    @Override public void onDetachedFromActivityForConfigChanges() { detach(); }
    @Override public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) { onAttachedToActivity(binding); }
    @Override public void onDetachedFromActivity() { detach(); }
    private void detach() {
        if (activityBinding != null) activityBinding.removeRequestPermissionsResultListener(this);
        activityBinding = null;
        if (permissionResult != null) { permissionResult.success(false); permissionResult = null; }
    }
    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) { stop(); methods.setMethodCallHandler(null); events.setStreamHandler(null); }
}
