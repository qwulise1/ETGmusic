plugins {
    id("com.android.application")
}

android {
    namespace = "io.qwulise1.etgmusic"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.qwulise1.etgmusic"
        minSdk = 26
        targetSdk = 35
        versionCode = 5
        versionName = "0.5.0-vimusic-style"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
