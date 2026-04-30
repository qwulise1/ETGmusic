[app]
title = ETGmusic
package.name = etgmusic
package.domain = io.qwulise1
source.dir = .
source.include_exts = py,png,jpg,jpeg,kv,json,txt
version = 0.2.0

requirements = python3,kivy==2.3.0,kivymd==1.2.0,telethon==1.36.0,pillow==10.4.0,pyjnius,PySocks==1.7.1,certifi,openssl,sqlite3

orientation = portrait
fullscreen = 0
log_level = 2

android.permissions = INTERNET,READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE,WAKE_LOCK,FOREGROUND_SERVICE
android.api = 34
android.minapi = 24
android.ndk = 25b
android.archs = arm64-v8a
android.accept_sdk_license = True
android.enable_androidx = True

presplash.color = #090b11

[buildozer]
warn_on_root = 0
log_level = 2
