# Tam sürüm için Android ayarlarını yapar (bildirim, parmak izi, konum).
import glob, os, sys

d = sys.argv[1]
app = os.path.join(d, 'android', 'app')

# 1) Gradle: core library desugaring (bildirim paketi için gerekli)
kts, grv = os.path.join(app, 'build.gradle.kts'), os.path.join(app, 'build.gradle')
if os.path.exists(kts):
    s = open(kts, encoding='utf-8').read()
    assert 'compileOptions {' in s, 'compileOptions bulunamadi'
    s = s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    open(kts, 'w', encoding='utf-8').write(s)
elif os.path.exists(grv):
    s = open(grv, encoding='utf-8').read()
    assert 'compileOptions {' in s, 'compileOptions bulunamadi'
    s = s.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
    s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    open(grv, 'w', encoding='utf-8').write(s)
else:
    raise SystemExit('build.gradle bulunamadi')

# 2) Manifest: izinler ve bildirim alicilari
mf = os.path.join(app, 'src', 'main', 'AndroidManifest.xml')
s = open(mf, encoding='utf-8').read()
perms = ''.join('    <uses-permission android:name="android.permission.%s"/>\n' % p for p in
                ['POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'VIBRATE', 'USE_BIOMETRIC', 'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION'])
assert '<application' in s and '</application>' in s
s = s.replace('<application', perms + '    <application', 1)
rec = '''        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    '''
s = s.replace('</application>', rec + '</application>', 1)
open(mf, 'w', encoding='utf-8').write(s)

# 3) MainActivity: parmak izi icin FlutterFragmentActivity
found = 0
for f in glob.glob(os.path.join(app, 'src', 'main', '**', 'MainActivity.*'), recursive=True):
    t = open(f, encoding='utf-8').read()
    if 'FlutterFragmentActivity' not in t:
        t = t.replace('FlutterActivity', 'FlutterFragmentActivity')
    open(f, 'w', encoding='utf-8').write(t)
    found += 1
assert found > 0, 'MainActivity bulunamadi'

# 4) Tema: parmak izi penceresi icin AppCompat
for f in glob.glob(os.path.join(app, 'src', 'main', 'res', 'values*', 'styles.xml')):
    t = open(f, encoding='utf-8').read()
    for old in ['@android:style/Theme.Light.NoTitleBar', '@android:style/Theme.Black.NoTitleBar']:
        t = t.replace(old, 'Theme.AppCompat.DayNight.NoActionBar')
    open(f, 'w', encoding='utf-8').write(t)
print('Android ayarlari tamam')
