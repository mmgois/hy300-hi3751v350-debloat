# HY300 projector (HiSilicon Hi3751V350): ADB, debloat and launcher swap

A guide to what was done on a mini projector sold as "HY300" to make it lighter, replace the home
screen and remove suspicious factory apps. Everything was done over ADB, without root and without
opening the device. Tested on a single unit, in November 2026.

## Identification

Check this before going further: the "HY300" guides online cover different boards sold under the
same name (Allwinner H713, Rockchip RK3326, Amlogic T950S) and do not apply to this one.

| Property | Value |
|---|---|
| `ro.product.device` | `Hi3751V350` |
| `ro.board.platform` | `bigfish` |
| Android | 12, `userdebug` build |
| `ro.build.fingerprint` | `google/redfin/...` (pretends to be a Pixel 5) |
| RAM | ~2 GB |
| Build shown in the menu | `JM_P1-2026...` |
| Factory launcher | `com.tcl.movieark.launcher`, `com.htc.htclauncherhighenglishd08` |

Without ADB, a sign of this variant: the Android version easter egg shows a clock (Android 12),
and there are **no** `com.rockchip.*` or `com.hotack.*` packages (you can check with Activity
Launcher).

## What does not work on this board

- **Developer options**: tapping "Android TV OS build" or the model name 7 times does nothing.
  Opening `DevelopmentActivity` from Activity Launcher shows "developer options are not available
  for this user".
- **ADB over USB**: the projector's USB-A port is host-only. It reads **FAT32** flash drives (exFAT
  does not show up), but it does not speak ADB to a PC. A USB A-A cable connects the 5 V lines of
  both sides and can even power the board from the PC: **do not leave an A-A cable connected while
  the projector is plugged into the wall**.
- **Recovery** via buttons (holding power at boot, power + volume, etc.): nothing worked.
- The vendor's "USB debugging – On" menu does not open port 5555.

## 1. Find ADB (port 13111)

Network ADB **is enabled from the factory**, on a non-standard port and with no authentication:

```
persist.adb.tcp.port=13111
service.adb.tcp.port=13111
ro.adb.secure=        (empty: no confirmation prompt on screen)
```

To find the port on another unit, use [`scan-adb.sh`](scan-adb.sh): it scans the TCP ports and
tests each one with `adb` (non-ADB services accept the connection but stay `offline`).

```bash
./scan-adb.sh 192.168.0.50            # all ports (takes a few minutes)
./scan-adb.sh 192.168.0.50 13000 14000
adb connect 192.168.0.50:13111
```

The other open ports (11022, 11101–11104, 4321, 38400 and a few random high ones) belong to
system services (uid `system`/`root`: Miracast and HiSilicon TV services), not to third-party
apps.

The examples below use `adb -s <ip>:13111 shell ...`, shortened to `adb shell`.

## 2. Disable animations

The biggest perceived speed-up when navigating:

```bash
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
```

## 3. Replace the home screen with Projectivy

Install **Projectivy Launcher** from the Play Store. Setting it as the default launcher **is not
enough**: the firmware was modified so the Home button sends its own category,
`android.intent.category.HOME.JM`, which only `com.jm.jmlauncher` handles. It is a "dispatcher"
that opens the package set in `persist.sys.home.selectpkg` (the HTC launcher by default). Since
the build is `userdebug`, `setprop` works from `adb shell`:

```bash
adb shell cmd package set-home-activity --user 0 com.spocky.projengmenu/.ui.home.MainActivity
adb shell setprop persist.sys.home.selectpkg com.spocky.projengmenu
adb shell pm disable-user --user 0 com.tcl.movieark.launcher
adb shell pm disable-user --user 0 com.htc.htclauncherhighenglishd08
```

> ⚠️ **Never disable `com.jm.jmlauncher`.** Without it, Home falls back to `FallbackHome` ("User
> unlocked but no home") and the screen goes black. If that happens:
> `adb shell pm enable com.jm.jmlauncher`.

The setting survived reboots.

## 4. Remove and disable apps

**Uninstalled** (they shipped in `/data/app`, so removal is clean; a factory reset brings them
back):

| Package | What it is |
|---|---|
| `com.google.android.youtube.tv` (fake) | see [section 5](#5-fake-factory-youtube-app) |
| `com.tv.flarehub` | "Flarehub", 100 MB, signed by `CN=metax_os` |
| `com.unitvnet.tvod` | UniTV, pirate IPTV |
| `com.eusfu.appstore` | third-party app store |
| `com.tv9c.upgrade` | vendor updater (connected to an Alibaba Cloud IP) |
| `com.tcl.browser` | TCL browser |
| `com.mobisystems.office` | preinstalled Office |
| `com.bozee.usbdisplay` | screen mirroring, always running (~27 MB of RAM) |
| `com.netflix.mediaclient`, `com.disney.disneyplus`, `com.amazon.amazonvideo.livingroom` | not used |

```bash
adb uninstall <package>
```

**Disabled** (system apps; reversible with `pm enable`):

| Package | Reason |
|---|---|
| `com.tcl.movieark.launcher`, `com.htc.htclauncherhighenglishd08` | replaced launchers |
| `com.define.shellservice` | exported service that runs as `system` and accepts the `com.define.shellservice.shellcommand` action (runs commands). Nothing on the projector broke without it: keystone, focus, input switching and picture settings were tested |

```bash
adb shell pm disable-user --user 0 com.define.shellservice
```

**Accessibility pre-authorized for a package that does not exist.** The factory settings authorize
`com.android.nfx/com.android.nfx.NfxAccessibilityService`, which is not installed. If an app with
that name were installed (by an updater, for example), it would immediately get permission to read
the screen and simulate input. Keep only the HiSilicon service:

```bash
adb shell settings put secure enabled_accessibility_services \
  com.hisilicon.rmservice/com.hisilicon.rmservice.HiRMService
```

**Do not touch**: `com.jm.jmlauncher`, `com.htc.htcsettings` (settings), `com.softwinner.tcorrection`
(keystone), `com.hisilicon.*` (TV services, HDMI input, remote control), `com.vendor.vnaudiomanager`
(audio).

## 5. Fake factory YouTube app

The preinstalled "YouTube" app uses the official package name (`com.google.android.youtube.tv`,
version `2026.06.3018`), but:

- it is **2.3 MB** (the official one is ~50 MB) and contains another developer's code (`com.wuliang.*`);
- it only opens Flarehub pointed at the website: `flarehubtv://{"type":6,"url":"https://www.youtube.com/tv"}`;
- it contains code to **silently install** apps (`com.google.android.youtube.tv.ACTION_SILENCE_INSTALL`,
  `PackageInstaller`, `initSilenceInstalledReceiver`); after Flarehub was uninstalled, it asked to
  reinstall it.

| File | SHA-256 |
|---|---|
| Fake YouTube (`base.apk`) | `7cdcbeff7866db75333043ddae3158c4d26a00720b0828c92f755e5dca2ea336` |
| Flarehub (`base.apk`) | `adc537151adc19d5301dc64c6f9a09de1279e5284f1654cc44cc304e9ccc58a9` |

To check your unit:

```bash
adb shell pm path com.google.android.youtube.tv
adb shell dumpsys package com.google.android.youtube.tv | grep -E 'versionName|installerPackageName'
```

If the APK is only a few MB and there is no `installerPackageName=com.android.vending`, it is the
fake. Uninstall it and install the official one from the Play Store ("YouTube for Android TV",
Google LLC).

To look for other fake apps, compare signing keys: an app with a Google name signed with a key
different from the other Google apps is suspicious. On this unit, Play Services, Play Store, GSF,
built-in Chromecast and Chrome had consistent keys; only YouTube stood out.

## 6. Apps installed instead

- **Projectivy Launcher**, **YouTube for Android TV** and **Symfonium** (Subsonic/Navidrome client;
  `app.symfonik.music.player`) from the Play Store. Purchases made on the phone carry over to the
  projector if the Google account is the same.
- **Jellyfin for Android TV** from the [official GitHub](https://github.com/jellyfin/jellyfin-androidtv/releases)
  with `adb install -r jellyfin-androidtv-<version>-release.apk` (no automatic updates).

## Results and notes

- About 40–60 MB of resident memory was freed (TCL launcher 53 MB → Projectivy ~41 MB; `usbdisplay`
  27 MB; processes that woke up in the background). Free storage went from 2.6 to 2.9 GB, already
  counting the new apps.
- **The hardware is still the bottleneck**: with Jellyfin (~95 MB) and Symfonium (~70 MB) open,
  the device uses ~350 MB of swap. Use one heavy app at a time. For real performance, use an HDMI
  stick.
- The factory **Chrome** is legitimate, but the Play Store considers it "not compatible" and it is
  stuck on version 133 (early 2025), with no security fixes. Use it only on sites you trust.
- **ADB stays open, with no password, to the whole local network**, and there is no way to turn it
  off persistently (on a Redmi Projector Lite with the same chip, `setprop` reverts to the original
  value after a reboot). Keep the projector on a **guest network**, isolated from other devices.
- The chip is different, but the factory apps (fake YouTube, third-party store, pirate IPTV) follow
  the pattern of malware reports on cheap projectors (BADBOX 2.0, residential proxy). No proxy
  traffic was found on this unit, but Flarehub was not analyzed internally.

## How to undo

```bash
adb shell pm enable <package>                                  # re-enable
adb shell setprop persist.sys.home.selectpkg com.htc.htclauncherhighenglishd08
adb shell settings put global window_animation_scale 1         # same for the other two
```

Apps uninstalled from `/data` only come back with a factory reset.

## References

- [Free My TV PR #230](https://github.com/simbasjungles/free-my-tv/pull/230): the same
  `HOME.JM` / `persist.sys.home.selectpkg` mechanism on an Amlogic board.
- [hy300t-android-guia](https://github.com/mariorodriguesoficial/hy300t-android-guia): HY300-T
  (Amlogic T950S); warns never to disable `com.jm.jmlauncher`.
- [cleanyourtv #1178](https://github.com/Gathin23/cleanyourtv/issues/1178): Redmi Projector Lite,
  same Hi3751V350 chip, ADB open without authentication and impossible to turn off.
- [BruBread/Hy300-Root](https://github.com/BruBread/Hy300-Root) (RK3326) and
  [HY300_PRO.md](https://gist.github.com/probonopd/3ad6b7777caea1503f00d5fe7710ad06) (Allwinner H713):
  other boards sold as HY300.
- [FBI / BADBOX 2.0](https://www.bleepingcomputer.com/news/security/fbi-badbox-20-android-malware-infects-millions-of-consumer-devices/).

## Disclaimer

Done on a device I own. Use at your own risk: nothing here touches the bootloader or system
partitions, but disabling the wrong package can leave the home screen black until it is reverted
over ADB.

## License

MIT. See [LICENSE](LICENSE).
