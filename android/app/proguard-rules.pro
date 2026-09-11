# ML Kit discovers these registrars by manifest class name and reflection.
# R8 must retain their public no-argument constructors.
-keep class com.google.mlkit.** implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
