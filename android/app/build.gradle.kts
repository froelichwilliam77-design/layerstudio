import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun propOrEnv(propKey: String, envKey: String): String? {
    val fromFile = keystoreProperties.getProperty(propKey)?.takeIf { it.isNotBlank() }
    if (fromFile != null) return fromFile
    return System.getenv(envKey)?.takeIf { it.isNotBlank() }
}

val uploadStoreFilePath = propOrEnv("storeFile", "ANDROID_KEYSTORE_PATH")
val uploadStorePassword = propOrEnv("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val uploadKeyAlias = propOrEnv("keyAlias", "ANDROID_KEY_ALIAS")
val uploadKeyPassword = propOrEnv("keyPassword", "ANDROID_KEY_PASSWORD")

val hasReleaseSigning =
    !uploadStoreFilePath.isNullOrBlank() &&
        !uploadStorePassword.isNullOrBlank() &&
        !uploadKeyAlias.isNullOrBlank() &&
        !uploadKeyPassword.isNullOrBlank()

android {
    namespace = "com.layerstudio.layerstudio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.layerstudio.layerstudio"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                val storePath = uploadStoreFilePath!!
                val store = file(storePath)
                // Also accept path relative to android/ or android/app/
                storeFile = when {
                    store.exists() -> store
                    rootProject.file(storePath).exists() -> rootProject.file(storePath)
                    file("upload-keystore.jks").exists() -> file("upload-keystore.jks")
                    else -> store
                }
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                println("WARNING: Release signing secrets/key.properties missing — falling back to debug signing.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
