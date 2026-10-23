plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.vayora.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    defaultConfig {
        applicationId = "com.vayora.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            it.jvmArgs("--add-opens=java.base/java.lang=ALL-UNNAMED",
                "--add-opens=java.base/java.util=ALL-UNNAMED",
                "--add-opens=java.base/java.io=ALL-UNNAMED",
                "--add-opens=java.base/java.net=ALL-UNNAMED",
                "--add-opens=java.base/java.security=ALL-UNNAMED",
                "--add-opens=java.base/java.text=ALL-UNNAMED",
                "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED",
                "--add-opens=java.desktop/java.awt.font=ALL-UNNAMED",
                "--add-opens=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED")
        }
    }
    buildFeatures { buildConfig = true }
    flavorDimensions += "distribution"
    productFlavors {
        create("direct") {
            dimension = "distribution"
            manifestPlaceholders["authScheme"] = "com.vayora.app"
        }
        // Google Play listing uses its own application ID so the website/ads
        // APK (signed with our key) and the Play app (signed by Google) never
        // clash on the same phone.
        create("play") {
            dimension = "distribution"
            applicationId = "com.vayora.play"
            manifestPlaceholders["authScheme"] = "com.vayora.play"
        }
    }
    signingConfigs {
        if (System.getenv("ANDROID_KEYSTORE_PASSWORD") != null) {
            create("release") {
                storeFile = file("release.jks")
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}
flutter { source = "../.." }

dependencies {
 testImplementation("junit:junit:4.13.2")
 testImplementation("org.robolectric:robolectric:4.17")
 implementation("androidx.core:core-ktx:1.16.0")
 implementation("com.android.billingclient:billing:8.3.0")
 implementation("com.google.android.play:integrity:1.6.0")
}
