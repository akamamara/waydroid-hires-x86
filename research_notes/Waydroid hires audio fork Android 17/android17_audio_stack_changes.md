# Android audio stack changes from Android 11–14 (LOS 18.1–21) to Android 16/17 (LOS 23.x/24.0), for porting the Waydroid hi-res audio + Apple Music fix

Research date: 2026-11-07. Method note: WebFetch was blocked in this session by a broken context-mode hook (NODE_TOO_OLD), so **every finding below comes from search-result snippets, not full-page reads**. File contents (for example `Configuration.cpp` and the 202604 compatibility matrix) could not be opened. Items from background knowledge with no source found are kept under Inferences or Gaps and labelled as such.

What the original fix touches (from `/home/akamamara/Apps/fork-waydroid-hires/waydroid_high-res_audio_fix_and_apple_music_fix.md`, Android 13 / LOS 20 only):
1. The Waydroid audio HAL (the `android_hardware_waydroid` audio module that outputs to PulseAudio/PipeWire). The patch removes the forced 16-bit/48 kHz output and adds 24-bit, 32-bit and **PCM_FLOAT** cases. Float support was what made 24-bit DIRECT output work, because Apple Music hands 24-bit content over as float.
2. `/vendor/etc/audio_policy_configuration.xml`: the primary output mixPort is set to `AUDIO_FORMAT_PCM_FLOAT`, with configurable sampling rates.
3. **AudioFlinger (frameworks/av)**: patched to detect the Apple Music UID (read from `/data/local/tmp/apple_music_uid.txt`) and force `AUDIO_OUTPUT_FLAG_DIRECT`. This is shipped as a `system` overlay.
4. Network: virt-wifi (supechicken builds), so Apple Music treats the connection as Wi-Fi and allows lossless.

---

## Q1. HIDL vs AIDL audio HAL status in Android 14/15/16/17; the default AIDL HAL; how high-res is expressed

### Takeaway
From Android 14 the audio HAL is defined in AIDL (`android.hardware.audio.core`, service `vendor.audio-hal-aidl`). HIDL audio (last version 7.1) gets no new APIs, and features added in Android 14 or later, such as bit-perfect, work **only** with AIDL. Under VINTF rules, deprecated HIDL HALs keep working for "upgrading" devices whose vendor image declares an older target FCM level. That likely includes Waydroid's vendor image, which still ships a HIDL audio service. I could not confirm whether HIDL audio is still listed in the Android 17 matrix (202604).

### Cited Findings
- "In Android 14 and higher, the Audio HAL interface is defined using AIDL. For past versions, the Audio HAL interface is defined using HIDL. Partners and SoC vendors are encouraged to reimplement their Audio HAL to provide an AIDL interface." — [AOSP: AIDL and HIDL Audio HAL comparison](https://source.android.com/docs/core/audio/aidl-hidl-comp); also [Audio HAL implement](https://source.android.com/docs/core/audio/implement)
- New HAL APIs for Android 14+ features are AIDL-only, and no new API is added to HIDL from Android 14 onward. Android 13 updated HIDL audio to 7.1, its final version. — [AOSP aidl-hidl-comp](https://source.android.com/docs/core/audio/aidl-hidl-comp)
- AIDL interface mapping: HIDL `IDevice` becomes `IModule`, `IDevicesFactory` is removed, `IConfig` provides system-wide configuration, and `IBluetooth`/`ITelephony` take over parts of the old functionality. Free-form `get/setParameters` strings become typed `getVendorParameters`/`setVendorParameters` using ParcelableHolders. Android 14 adds the service name `vendor.audio-hal-aidl`. — [AOSP aidl-hidl-comp](https://source.android.com/docs/core/audio/aidl-hidl-comp)
- VINTF/FCM: Android 16 = FCM level 202504. Android 16 supports FCM levels 6 (12), 7 (13), 8 (14), 202404 (15) and 202504 (16). A HAL version is deprecated at an FCM level if that level's matrix does not list it. Devices targeting that level must not implement it, but "a deprecated HAL version is still supported by the framework for upgrading devices". — [AOSP: FCM lifecycle](https://source.android.com/docs/core/architecture/vintf/fcm)
- The `android17-release` branch of `platform/hardware/interfaces` contains `compatibility_matrices/compatibility_matrix.202404.xml`, `.202504.xml` and `.202604.xml`, so 202604 is the Android 17 FCM level. — [AOSP gitiles, android17-release compatibility_matrices](https://android.googlesource.com/platform/hardware/interfaces/+/android17-release/compatibility_matrices)
- Reference for the old matrix: [compatibility_matrix.8.xml at android-14.0.0_r50](https://android.googlesource.com/platform/hardware/interfaces.git/+/refs/tags/android-14.0.0_r50/compatibility_matrices/compatibility_matrix.8.xml)
- The VINTF `hal.format` attribute (default HIDL; `aidl` valid only on matrix meta-version 2.0) is "deprecated after Android 15 and no longer has any effect". — [AOSP compatibility matrices](https://source.android.com/docs/core/architecture/vintf/comp-matrices)
- Default AIDL HAL tree: `hardware/interfaces/audio/aidl/default/`. It has an `alsa/` subdirectory (`Mixer.cpp`, `ModuleAlsa.cpp`, `StreamAlsa.cpp`, `Utils.cpp`). `Module::createInstance` maps the DEFAULT type to `ModulePrimary`. When a port config does not specify a sample rate, `Module.cpp` takes the first value from the port profile's sample-rate set. — [gitiles alsa dir](https://android.googlesource.com/platform/hardware/interfaces/+/a4513dcf05/audio/aidl/default/alsa); [Module.cpp (OmniROM mirror)](https://gerrit.omnirom.org/plugins/gitiles/android_hardware_interfaces/+/78ad482f3fd8d5e0760607e55e358513d3d42298/audio/aidl/default/Module.cpp); [Module.cpp (AOSP rev 588943abd)](https://android.googlesource.com/platform/hardware/interfaces/+/588943abd/audio/aidl/default/Module.cpp); [audio/ on main](https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/main/audio/)
- Waydroid status: issue #2421 reports that the lineage_waydroid_x86_64 vendor image (built 2026-04-28) lacks `android.hardware.audio@2.0-service`, so `vendor.audio-hal-2-0` fails to start. Only 4.0 audio libraries are shipped, and a symlink workaround is suggested. Waydroid on LOS 23 is therefore still on the **HIDL** audio HAL path. — [waydroid/waydroid#2421](https://github.com/waydroid/waydroid/issues/2421); an older crash of `/vendor/bin/hw/android.hardware.audio.service` is in [#576](https://github.com/waydroid/waydroid/issues/576)
- `android_hardware_waydroid` has an `audio/` directory that bridges the Android audio framework to ALSA/PulseAudio. — [DeepWiki: android_hardware_waydroid](https://deepwiki.com/waydroid/android_hardware_waydroid); [DeepWiki: Waydroid hardware integration](https://deepwiki.com/waydroid/waydroid/10-hardware-integration)

### Inferences
- Porting route A (lowest effort): keep Waydroid's legacy `audio_hw` HAL behind the HIDL default wrapper (`hardware/interfaces/audio/core/all-versions/default`, which produces `android.hardware.audio.service`). The format and sample-rate switch-case patch then ports almost unchanged. This works only if the Android 17 framework still loads HIDL audio for a vendor image with an older target FCM level. The VINTF "upgrading devices" rule suggests it does, and issue #2421 shows LOS 23 Waydroid still does this, but I did not verify it against the 202604 matrix.
- Porting route B (future-proof): write an AIDL `IModule` for Waydroid, for example based on `ModulePrimary`/`StreamAlsa` or a PulseAudio/PipeWire stream class, and declare the high-res profiles (PCM_16, PCM_24_BIT_PACKED/PCM_8_24, PCM_32, PCM_FLOAT; 44.1–384 kHz) in the module configuration (`Configuration.cpp` in the default implementation). In AIDL, formats are `AudioFormatDescription` parcelables, not `audio_format_t` enums, so the float/24-bit switch-case logic has to be rewritten against the AIDL types. Bit-perfect (Q2) requires route B.
- The Android 13 patch hard-codes HIDL/legacy `audio_format_t` handling. It will not apply mechanically to any AIDL HAL.

### Gaps
- Whether `compatibility_matrix.202604.xml` (Android 17) still lists `android.hardware.audio@7.x` HIDL, or only AIDL `android.hardware.audio.core`. The gitiles file could not be fetched.
- Exact contents of `hardware/interfaces/audio/aidl/default/Configuration.cpp` in android17-release: the default primary-module profiles and the maximum sample rates. Not retrieved.
- Whether upstream Waydroid or WayDroid-ATV has moved the audio HAL to AIDL for LOS 24. The sources conflict (see Q4).

---

## Q2. frameworks/av changes: AudioFlinger, output flags, bit-perfect, policy config (XML 7.0 vs AIDL IConfig), AAudio/MMAP

### Takeaway
Android 14 added an official framework path for unmodified high-res output: **preferred mixer attributes** (`AudioMixerAttributes`) with `AUDIO_OUTPUT_FLAG_BIT_PERFECT`. This makes the framework reopen the output with the requested format and rate and skip mixing, SRC and volume. It is defined for USB devices and supported **only with the AIDL HAL**. It may replace the UID-based "force DIRECT" hack in AudioFlinger, but only if Apple Music calls the API, which is unconfirmed. Separately, with the AIDL HAL the content of the policy XML moves into `IConfig`/`IModule`. This changes where the "PCM_FLOAT @ 192000" mixPort edit has to be made.

### Cited Findings
- Android 14 added developer APIs to query and set preferred mixer attributes on USB audio: format, channel mask, sample rate and mixer behavior. When an app sets mixer attributes, "the framework reopens the output stream with new attributes, if needed". — [AOSP: Preferred mixer attributes on USB devices](https://source.android.com/docs/core/audio/preferred-mixer-attr)
- BIT_PERFECT is optional and "supported only in the AIDL implementation of the Audio HAL". The other preferred mixer attributes are mandatory for USB audio on Android 14. Vendors must add `AUDIO_OUTPUT_FLAG_BIT_PERFECT` to the dynamic mixPort routable to USB; the docs give a sample `usb_audio_policy_configuration.xml`. In bit-perfect mode the HAL must not apply volume, SRC or processing. CTS: `PreferredMixerAttributesTestActivity.java`. — [AOSP preferred-mixer-attr](https://source.android.com/docs/core/audio/preferred-mixer-attr)
- In the AIDL vs HIDL mapping table, the system-wide settings from `audio_policy_configuration.xml` and `audio_policy_engine_configuration.xml` map to the AIDL `IConfig`/`IModule` interfaces. For the configurable audio policy engine files, the table says to keep the HIDL implementation for Android 14. — [AOSP aidl-hidl-comp](https://source.android.com/docs/core/audio/aidl-hidl-comp)
- `<audioPolicyConfiguration version="7.0">` is the HIDL-era XML format used in current AOSP and vendor trees, for example goldfish. — [goldfish audio_policy_configuration.xml](https://android.googlesource.com/device/generic/goldfish/+/cc5ff994/audio/policy/audio_policy_configuration.xml); [Pixel felix config (Evolution-X mirror)](https://git.evolution-x.org/Evolution-X-Tensor/device_google_felix/src/branch/bka/audio/felix/config/audio_policy_configuration.xml)
- frameworks/av audioserver changes include bypassing AIDL translation for in-process AudioFlinger calls and initializing services before publishing them. No release tag is attached, so I cannot place this in a specific Android version. — [/e/OS mirror of frameworks/av commit](https://gitlab.e.foundation/e/os/android_frameworks_av/-/commit/d387cf7c4c791c2abc64fbf31d29b96d7f070cd3)
- AAudio MMAP lets apps write to shared memory that the hardware reads directly, for lower latency. An Android 11 bug in shared MMAP streams returns `AAUDIO_ERROR_TIMEOUT` instead of `DISCONNECTED`. — [AOSP AAudio and MMAP](https://source.android.com/devices/audio/aaudio); [Oboe AndroidAudioHistory.md](https://android.googlesource.com/platform/external/oboe/+/HEAD/docs/AndroidAudioHistory.md)

### Inferences
- The AudioFlinger patch (UID check plus a forced `AUDIO_OUTPUT_FLAG_DIRECT`) touches files that change heavily between Android 13 and 17: `frameworks/av/services/audioflinger/AudioFlinger.cpp` and `Threads.cpp`, and probably `services/audiopolicy/managerdefault/AudioPolicyManager.cpp` (`getOutputForAttrInt`/`getOutputForDevices`). From Android 14, AudioFlinger was split into interface headers such as `IAfThread.h` and `IAfTrack.h` (background knowledge, unverified here), and the HAL goes through `frameworks/av/media/libaudiohal/impl/*HalAidl*`. Expect to rebase by hand, not cherry-pick.
- A cleaner alternative to the UID hack: in the audio policy layer, give the Waydroid "primary/direct" mixPort a profile with PCM_FLOAT/24-bit at high rates plus the DIRECT (or, with AIDL, BIT_PERFECT) flag. Then let policy pick DIRECT whenever the app's format and rate match. The original author found DIRECT was not chosen automatically; that part still needs testing on 17.
- On an AIDL HAL, the policy config may come from the HAL (`IConfig`/`IModule::getAudioPort*`) and not from `/vendor/etc/audio_policy_configuration.xml`. Editing the XML overlay (step 12 of the original guide) would then have no effect. On a HIDL HAL the XML still applies.
- MMAP/AAudio is unlikely to matter: Waydroid's HAL is not MMAP-capable, so AAudio falls back to the legacy path.

### Gaps
- No Android 16- or 17-specific audio framework release notes were found: no mixer or resampler max-rate changes, no new output flags. Searches for "Android 17 audio changes" returned nothing relevant.
- Whether `AudioMixerAttributes`/BIT_PERFECT can apply to non-USB devices, such as Waydroid's primary output, in Android 16/17. The docs found are USB-only.
- Whether Apple Music for Android calls `setPreferredMixerAttributes`. No source found.
- The exact current AudioPolicyConfig loading logic (AIDL HAL vs XML fallback) in android17-release. Not verified.

---

## Q3. DRM / MediaDrm / Widevine, Codec2 vs OMX, media playback for Apple Music in a container

### Takeaway
I found no Android 16/17 DRM change that is specific to Apple Music. Two trends matter for a Waydroid image. First, OMX is effectively gone for software codecs; Codec2 in the swcodec APEX is the path. Second, the Widevine HAL has moved to AIDL in community Waydroid builds. Apple Music lossless reportedly relies on Apple's own FairPlay-based protection and not on Widevine levels, but that is a secondhand claim.

### Cited Findings
- WayDroid-ATV's Android TV build release 20250718 updated the Widevine service to AIDL and switched to Codec2-based video decoders. — [newreleases.io: WayDroid-ATV waydroid-androidtv-builds 20250718](https://newreleases.io/project/github/WayDroid-ATV/waydroid-androidtv-builds/release/20250718)
- WayDroid-ATV waydroid-builds release 20260125 (lineage-21.0) added a KeyMint HAL and camera support. — [newreleases.io 20260125](https://newreleases.io/project/github/WayDroid-ATV/waydroid-builds/release/20260125)
- Device commit: the legacy codec list "is no longer available as of Android 14 QPR3", and Codec2 software codecs in the swcodec APEX take over. OMX HW audio codecs do not work without QCOM A/V extensions. — [Evolution-X sm8150-common: remove OMX](https://git.evolution-x.org/Evolution-X-Devices/device_xiaomi_sm8150-common/commit/cefc28f8bd0af20fea1231205404652641cd304e)
- OMX is deprecated in favor of Codec2 (GStreamer discussion). — [GStreamer Discourse](https://discourse.gstreamer.org/t/omx-removal-from-gstreamer-1-24/1672)
- A Cider developer claims Apple's lossless sources are FairPlay-only, so non-Apple devices cannot decrypt lossless. This is secondhand and concerns desktop clients; the Android app does play lossless. — [itch.io post](https://itch.io/post/14301006/view-in-topic)
- Waydroid can get Widevine L3 via Magisk or scripts, with roughly 720p limits on streaming services and no passing attestation. — [Lemmy thread](https://lemmy.nekusoul.de/post/202812)
- A lossless-related failure on Apple Music can look like a DRM error (djay forum). — [Algoriddim community](https://community.algoriddim.com/t/possibly-misleading-drm-error-message-when-using-lossless-files/21231)
- The unvetted AUR package `waydroid-apple-music` (first submitted Sept 2026) claims bit-perfect Apple Music on Waydroid via a patched audio HAL, container properties and app settings, with PipeWire for rate switching. It may be prior art for this port. — [AUR waydroid-apple-music](https://aur.archlinux.org/packages/waydroid-apple-music)

### Inferences
- The "turn off animated art" step from the original guide suggests video (Codec2 decode) of animated artwork interferes on Waydroid. On LOS 24 the Codec2 HW/SW decoder setup will differ, so retest it.
- The virt-wifi trick (supechicken builds) is separate from the audio stack and must be re-ported for LOS 24 independently.

### Gaps
- No source on Android 16/17 MediaDrm/Widevine API changes. No source on whether Apple Music's Android app needs Widevine (and which level), Play Integrity or attestation, or whether it changed its requirements on Android 16/17.
- No confirmation that Android 17 removed OMX completely, as opposed to it being unused.

---

## Q4. Is Android 17 source released? LineageOS 24.0 base and dates

### Takeaway
**Confirmed for Android 17:** AOSP moved to publishing source twice a year (Q2 and Q4) from 2026. Android 17 stable came out in June 2026, and its source is on AOSP: an `android17-release` branch, an `android-17.0.0_r1` tag, and an `android-security-17.0.0_r1` manifest tag dated 2026-10-07. LineageOS 24.0 (Android 17) was announced 2026-10-11/12. The Q4 2026 AOSP drop (17 QPR) may be out or imminent as of today; not verified.

### Cited Findings
- From 2026, Google publishes AOSP source in Q2 and Q4 to match the trunk-stable model. — [source.android.com: Android 17 compatibility versions (localized copy)](https://source.android.com/docs/compatibility/17/versions?authuser=2&hl=tr)
- Android 17 Beta 1 came in Feb 2026. The plan was a major SDK release in Q2 2026 and a minor SDK release in Q4 2026. — [CNX Software, 2026-02-14](https://www.cnx-software.com/2026/02/14/android-17-beta-1-released-with-h-266-vvc-support-camera-improvements-and-more/?amp=1)
- Android 17 stable reached Pixels, and the source is "officially available at AOSP" (no exact date given). — [FoneArena](https://www.fonearena.com/blog/?p=485177)
- AOSP manifest tag `android-security-17.0.0_r1`, dated 2026-10-07. — [android.googlesource.com manifest tag](https://android.googlesource.com/platform/manifest/+/refs/tags/android-security-17.0.0_r1)
- A third-party ODROID-M release says it is based on `android-17.0.0_r1`. — [odroid-dev android-releases CNB-R.01](https://github.com/odroid-dev/android-releases/releases/tag/ODROID-M_CNB-R.01)
- The `android17-release` branch exists in `platform/hardware/interfaces`. — [gitiles](https://android.googlesource.com/platform/hardware/interfaces/+/android17-release/compatibility_matrices)
- LineageOS 24.0 is based on Android 17, released 2026-10-11 ahead of schedule. Android 17 itself came out in June. The rebase was fast because of earlier refactor work, and 17's first release was mostly iterative. It ships security patches through October 2026, a WebUSB flash tool and a Canvas editor. — [9to5Google, 2026-10-12](https://9to5google.com/2026/10/12/lineageos-24-launches-based-on-android-17-with-app-redesigns-and-simple-flash-tool/); [Linuxiac](https://linuxiac.com/lineageos-24-0-open-source-mobile-os-released-with-android-17); [Android Authority](https://androidauthority.com/lineageos-24-android-17-3721683); [AndroidSage](https://www.androidsage.com/2026/10/12/lineageos-24-released-based-on-android-17-in-browser-webusb-flashing-canvas-photo-editor-and-kernel-overhauls/); [OSNews](https://www.osnews.com/?p=146132)
- Waydroid timeline: official Waydroid images were stuck on LOS 20 (Android 13) for a long time. A feature request for Android 16/LOS 23 records LOS 22.2 booting but not LOS 23 at that time. The WayDroid-ATV community builds offer newer bases; a LOS 23.0 image was dated 2026-05-18. — [waydroid#2229](https://github.com/waydroid/waydroid/issues/2229); [SourceForge: lineage-23.0-20260518 waydroid_x86_64](https://sourceforge.net/projects/waydroid-atv/files/images/system/waydroid_x86_64/lineage-23.0-20260518-GAPPS-waydroid_x86_64-system.zip/download)
- **Conflict:** one search summary of the [WayDroid-ATV waydroid-builds releases page](https://github.com/WayDroid-ATV/waydroid-builds/releases) said it lists LOS 22.2, 23.2 and **24.0** images and a "Reworked Audio HAL, which improves stability and brings slightly better audio latency performance" tied to an Android 17 image. A second search said the newest release, [20260717](https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20260717), is LOS 23.2 (Android 16 QPR2) with no audio work, and that the [repo README](https://github.com/WayDroid-ATV/waydroid-builds) describes Android 13–16 builds only. The pages were not fetched, so this is unresolved. The 24.0 build may have been released after 20260717.

### Inferences
- The LOS 24.0 base is most likely `android-17.0.0_r1` plus later security tags. LineageOS's exact manifest tag was not verified.
- If the WayDroid-ATV LOS 24 image with a reworked audio HAL exists, it is the natural porting base. Check whether that HAL is AIDL before porting the patch.

### Gaps
- The exact date `android-17.0.0_r1` was pushed to AOSP, and whether the Q4 2026 (17 QPR1) source drop has happened as of 2026-11-07.
- The exact AOSP tag in LineageOS 24.0's `android` manifest (`lineage-24.0` branch). Not fetched.

---

## Q5. Build-system changes affecting building a single audio module

### Takeaway
I found few sourced specifics. Soong/Android.bp is the main build system, and Android.mk (Kati) is being phased out. The "Bazel migration" was abandoned (background knowledge, unsourced). Since Android 14 the `lunch` target takes a release config (`lunch <product>-<release>-<variant>`, e.g. `trunk_staging`/`ap2a`/`bp2a`-style). That is background knowledge I could not source here.

### Cited Findings
- AOSP is replacing Makefiles with Soong. During the transition, Kati reads Android.mk files into a ninja file that is combined with Soong's ninja. — [AOSP build Changes.md](https://android.googlesource.com/platform/build/+show/759d0c8cb2/Changes.md)
- Community projects are converting Android.mk to Android.bp because "Android.mk (kati build system) is being deprecated in AOSP". — [freedesktop mesa/drm MR 361](https://gitlab.freedesktop.org/mesa/drm/-/merge_requests/361)
- The build team deprecated the bash `m*` commands in favor of Soong's `modules-in*` commands, then reverted that change, which shows churn in the single-module workflow. — [OmniROM mirror of build revert](https://gerrit.omnirom.org/plugins/gitiles/android_build/+/fa7204b0e1e9e3b39a2847ac18566345fb13cb88%5E)
- Flattened APEXes are deprecated. This matters if the patched module ends up inside an APEX, for example swcodec. — [AOSP build: Deprecate flattened apexes](https://android.googlesource.com/platform/build/+/2ac1f2fabc)

### Inferences
- If Waydroid's audio HAL (`android_hardware_waydroid/audio`) still uses Android.mk, it may need conversion to Android.bp (`cc_library_shared` with `vendor: true`, `relative_install_path: "hw"`) for LOS 24. Check the tree first.
- Typical single-module build on LOS 24 (unverified for 24): `source build/envsetup.sh; breakfast`/`lunch lineage_waydroid_x86_64-<release>-userdebug; m audio.primary.waydroid` (or the AIDL service module name), plus `m libaudioflinger` / `m audioserver` for the framework patch. Then push via the `/var/lib/waydroid/overlay/{system,vendor}` overlay as in the original guide.
- The AudioFlinger patch ships `system` libraries (libaudioflinger.so etc.). Those must exactly match the LOS 24 system image build, so rebuild them against the same manifest and security tag as the Waydroid system image in use.

### Gaps
- No sourced confirmation of the `lunch <product>-<release>-<variant>` syntax or of the current LineageOS 24 release config name (`bp2a`, `bp4a` or similar).
- No source on whether Android.mk is fully rejected in Android 17 or only discouraged.
