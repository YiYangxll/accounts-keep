plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yiyangxll.accounts_keep"
    compileSdk = flutter.compileSdkVersion
    // 本工程自身不含任何原生（C/C++）代码，因此这里刻意不**写死** ndkVersion，
    // 避免把本机 NDK 版本锁进仓库。
    //
    // 但要注意：path_provider_android 2.3.1 起会传递依赖 jni / jni_flutter 这两个
    // native_build 插件，Flutter Gradle Plugin 会自动补上默认 ndkVersion
    // （实测 28.2.13676358），于是构建**确实需要本机安装 NDK**。
    // 若报 "LicenceNotAcceptedException: ndk;xx"：先
    //   sdkmanager --install "ndk;xx"
    // 再确认 android/local.properties 的 sdk.dir 指向真实 SDK
    // （曾经被自动改写成 "E:\Program Files"，导致许可证找不到）。
    // 想彻底摆脱 NDK，可把 path_provider_android 固定到不依赖 jni 的旧版本。

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yiyangxll.accounts_keep"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
