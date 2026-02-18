# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Google Play Core (for deferred components) - ignore missing classes
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ONNX Runtime
-keep class ai.onnxruntime.** { *; }

# Speech to Text
-keep class com.csdcorp.speech_to_text.** { *; }

# Flutter Foreground Task
-keep class com.pravera.flutter_foreground_task.** { *; }

# App classes - prevent stripping of alarm/activity components
-keep class com.bunny.neuro.AlarmReceiver { *; }
-keep class com.bunny.neuro.MainActivity { *; }

# Android Alarm Manager
-keep class io.flutter.plugins.androidalarmmanager.** { *; }
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }

# Flutter Local Notifications - full screen intent support
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Flutter Overlay Window
-keep class com.phan_tech.flutter_overlay_window.** { *; }

# Keep BroadcastReceivers and Services
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends android.app.Service { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Gson (for flutter_local_notifications TypeToken)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Fix R8 full mode stripping TypeToken generic signatures (critical for flutter_local_notifications)
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
