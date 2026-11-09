# WayDroid-ATV lineage-24.0 (Android 17) build tree, audio HAL, and porting the hi-res / Apple Music fix

> **Method caveat (read first):** In this session WebFetch was blocked by a broken PreToolUse hook (context-mode, `NODE_TOO_OLD`), and Bash was off-limits. So I could **not** open the `lineage-24.0` tree, the raw files, the commit list, or the GitHub API for `WayDroid-ATV/android_vendor_waydroid`. Everything below comes from web-search result snippets of GitHub pages (releases, PRs, issues, READMEs), SourceForge, AUR and forums. Statements about file contents on the lineage-24.0 branch are therefore **inferences** unless cited. A follow-up pass with working WebFetch/`git clone` should check them, using the checklist in the final Gaps section.

## Q1. Which audio HAL does lineage-24.0 use, how does it reach the host, and what formats/rates are hardcoded?

### Takeaway
The Waydroid audio HAL lives in **`hardware/waydroid` (repo `android_hardware_waydroid`), directory `audio/`, file `audio_hw.c`**. It does not live in `android_vendor_waydroid`. It is a legacy `audio.primary.*` HAL module. Historically it was loaded by the **HIDL** service `android.hardware.audio@2.0-service` with the `@4.0` impl, and it talks to the host through **alsa-lib's "pulse" PCM plugin** using the host PulseAudio/pipewire-pulse socket. Upstream hardcodes **48000 Hz / S16_LE** in `adev_open_output_stream()`. WayDroid-ATV's Android 17 release notes say the Audio HAL was "reworked for stability and slightly better latency". Whether it is still HIDL or now AIDL on lineage-24.0 could not be confirmed.

### Cited Findings
- The HAL reads property `waydroid.pulse_runtime_path` (default `/run/user/1000/pulse`), exports `PULSE_RUNTIME_PATH`, then opens an ALSA PCM named **"pulse"** via `snd_pcm_open` in a retry loop — [CachyOS forum "BIT Perfect Audio on Waydroid"](https://discuss.cachyos.org/t/bit-perfect-audio-on-waydroid-using-bit-perfect-audio-from-waydroid/11294) (also posted at [bbs.archlinux.org](https://bbs.archlinux.org/viewtopic.php?id=306897))
- Upstream `audio/audio_hw.c` in android_hardware_waydroid sets `out->config.rate = 48000;` and S16_LE, and the stock policy advertises only 16-bit/48 kHz — [svrkb/waydroid-sample-rate-switch README](https://github.com/svrkb/waydroid-sample-rate-switch)
- Upstream PR **#80 "audio: honour the format and rate AudioFlinger requests"** (author kanya-approve, against `lineage-20`): it says `adev_open_output_stream()` hardcoded every output stream to S16_LE at the fixed playback rate. The PR takes the requested format/rate instead (falling back to S16_LE for formats missing from the probe table, and using AudioFlinger's rate unless 0), and widens the primary output in the policy XML to float plus standard rates up to 192 kHz. The author tested on x86_64 with an iFi USB DAC via PipeWire: S16_LE@48000 and S32_LE@192000 worked, and one float format **fell through to `LOG_ALWAYS_FATAL`** — [waydroid/android_hardware_waydroid PR #80](https://github.com/waydroid/android_hardware_waydroid/pull/80)
- Upstream PR **#91 "Restore the 4-period (85 ms) playback buffer"** (Sebby37): an earlier change switched the buffer size from bytes to frames but kept one period, so the buffer shrank to about 21 ms and audio through the pulse ALSA plugin turned choppy. It also says that "since #80" the primary output declares rates up to 192 kHz and AudioPolicyManager opens the mixer at the highest rate offered — [PR #91](https://github.com/waydroid/android_hardware_waydroid/pull/91)
- Legacy upstream (lineage-18.1) `device.mk` ships `android.hardware.audio@2.0-service`, `android.hardware.audio@4.0-impl`, effects, and `audio.primary.*`, `audio.r_submix.default`, `audio.usb.default`, `audio.a2dp.default`. It copies `audio_policy_configuration.xml` from `hardware/waydroid/audio` — [android_device_waydroid_waydroid device.mk @lineage-18.1](https://github.com/waydroid/android_device_waydroid_waydroid/blob/lineage-18.1/device.mk)
- A 2026 upstream bug: a vendor image dated 2026-04-28 lacked `android.hardware.audio@2.0-service`, so `vendor.audio-hal-2-0` failed to start, and only 4.0 audio libs were present. This shows the HIDL path is still used upstream — [waydroid/waydroid #2421](https://github.com/waydroid/waydroid/issues/2421)
- The DeepWiki overview of android_hardware_waydroid lists the subsystems hwcomposer, gralloc, **audio** (ALSA + PulseAudio), interfaces, and HAL stubs — [DeepWiki](https://deepwiki.com/waydroid/android_hardware_waydroid)
- WayDroid-ATV keeps its own fork of `android_hardware_waydroid`. Third-party forks such as Mnauiinecek/android_hardware_waydroid are forked from WayDroid-ATV's copy and carry the same audio HAL folder — [Mnauiinecek/android_hardware_waydroid](https://github.com/Mnauiinecek/android_hardware_waydroid)
- Release 20261017 (LineageOS 24.0, Android 17 QPR0) notes include "Reworked Audio HAL, which improves stability and brings slightly better audio latency performance" — [WayDroid-ATV/waydroid-builds release 20261017](https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20261017). One search summary flagged that this line might belong to an older release on the same page, so the attribution is not fully certain: [Releases page](https://github.com/WayDroid-ATV/waydroid-builds/releases)
- WayDroid-ATV also forks `android_hardware_interfaces` — [WayDroid-ATV/android_hardware_interfaces](https://github.com/WayDroid-ATV/android_hardware_interfaces)

### Inferences
- For a port, the file to patch is almost certainly `hardware/waydroid/audio/audio_hw.c` on WayDroid-ATV's `android_hardware_waydroid` **lineage-24.0** branch. The `audio_policy_configuration.xml` is likely in the same `audio/` dir or under `device/waydroid/waydroid`. `android_vendor_waydroid` mostly holds the manifest generator, patches, and build glue, not the HAL.
- The "reworked Audio HAL" in the A17 release may have restructured `audio_hw.c` (buffering and latency). The original Reddit patch, written against the Android 13 tree, will likely **not apply cleanly** and will need a manual re-port.
- Android 17 / LOS 24 still accepts HIDL audio HAL 7.x-era services only if the framework compatibility matrix allows them. AOSP has been pushing AIDL audio (`android.hardware.audio.service` with `IModule`). If WayDroid-ATV moved to AIDL, the legacy `audio_hw_device` API (`adev_open_output_stream`) might be wrapped by the AOSP `libaudiohal` legacy-shim (`android.hardware.audio.service-aidl.default` with a legacy primary module). Unverified.

### Gaps
- Exact lineage-24.0 file list, `Android.bp`, module names (`audio.primary.waydroid`?), and whether the service is `android.hardware.audio.service` (AIDL) or `@7.x`/`@4.0` HIDL. This needs a direct tree fetch.
- Whether PR #80 / #91 were merged upstream or picked into WayDroid-ATV.
- The hardcoded period size/count and channel mask on the reworked A17 HAL.

## Q2. What is the build entrypoint, and which repos must be synced?

### Takeaway
WayDroid-ATV follows the standard Waydroid flow. You `repo init` the LineageOS manifest (`--git-lfs`) on the target branch and `repo sync build/make`. Then you run **`generate-manifest.sh` from WayDroid-ATV `android_vendor_waydroid`** to write local_manifests, sync, apply the Waydroid patches, `lunch`, and `make systemimage vendorimage`. Documented lunch targets are `lineage_waydroid_x86_64-userdebug` (non-TV) and `lineage_waydroid_tv_x86_64-userdebug` (ATV). I found no documented lineage-24.0 release-config suffix (e.g. `-bp4a-`/`-cp1a-`).

### Cited Findings
- The WayDroid-ATV BUILDING.md (ATV 13 / lineage-20.0) does `repo init` LineageOS with `--git-lfs` on lineage-20.0, then `repo sync build/make`, then runs `generate-manifest.sh` from WayDroid-ATV `android_vendor_waydroid`, then `lunch lineage_waydroid_tv_x86_64-userdebug` and `make systemimage` / `make vendorimage -j$(nproc --all)`. It calls for about 300 GB of disk and roughly 5 h of build time. It only documents 18.1 and 20.0 — [BUILDING.md](https://github.com/WayDroid-ATV/waydroid-androidtv-builds/blob/main/BUILDING.md)
- The official Waydroid docs cover the same flow with the `lineage_waydroid_x86_64-userdebug` targets and a `waydroid-generate-manifest` helper. They note that lineage-20+ outputs raw images directly — [docs.waydro.id compile guide](https://docs.waydro.id/development/compile-waydroid-lineage-os-based-images)
- A comparable modern flow on lineage-23.2 (dragon-waydroid, arm64): init, run the manifest script, `apply-waydroid-patches`, `breakfast waydroid_arm64`, build — [dragon-waydroid-builds](https://github.com/dragon-waydroid/dragon-waydroid-builds)
- SourceForge file names show the branch naming: `lineage-23.0-20260518-GAPPS-waydroid_x86_64-system.zip` and `...-MAINLINE-waydroid_x86_64-vendor.zip` — [SourceForge waydroid-atv](https://sourceforge.net/projects/waydroid-atv/files/images/system/waydroid_x86_64/lineage-23.0-20260518-GAPPS-waydroid_x86_64-system.zip/download)
- The 20260717 release is LineageOS 23.2 (Android 16 QPR2). Its changelog cites commits in WayDroid-ATV forks of `android_hardware_waydroid` and `android_external_mesa3d` — [release 20260717](https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20260717)

### Inferences
- Likely recipe for 24.0 (unverified): `repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs` → `repo sync build/make` → `wget`/run `generate-manifest.sh` from `https://raw.githubusercontent.com/WayDroid-ATV/android_vendor_waydroid/lineage-24.0/manifest_scripts/generate-manifest.sh` (path guessed from upstream layout) → `repo sync` → `. build/envsetup.sh && apply-waydroid-patches` → `lunch lineage_waydroid_x86_64-<release>-userdebug` (Android 15+ lunch requires a release token, e.g. `bp2a`/`bp4a` on A16; the A17 token is unknown) → `make systemimage vendorimage`.
- Repos involved, at minimum: WayDroid-ATV forks of `android_vendor_waydroid`, `android_device_waydroid_waydroid`, `android_hardware_waydroid` (audio HAL), `android_hardware_interfaces`, `android_external_mesa3d`, plus the minigbm/gralloc and libgbinder-type repos the generated manifest pulls in.
- Fastest iteration for an audio-only port: build just the HAL module (`m audio.primary.waydroid`, name assumed) and drop the `.so` and the policy XML into `/var/lib/waydroid/overlay/vendor/...`. The original fix's "overlay" install method does exactly this, so a full image rebuild is not needed.

### Gaps
- Actual lineage-24.0 lunch target / release config name, and whether `generate-manifest.sh` exists on that branch.
- The commit history and dates of the lineage-24.0 branch (I could not query the API).

## Q3. Do WayDroid-ATV publish prebuilt LOS 24 images, and how are they installed?

### Takeaway
Yes. Release **20261017 "LineageOS 24.0, Android 17 QPR0"** (marked Latest, about 3 weeks before 2026-11-07) ships GAPPS/VANILLA system and MAINLINE vendor zips, x86_64 only (no ARM64). The recommended install is `waydroid init` pointed at WayDroid-ATV's OTA on `waydroid-atv.github.io` (`.../a17-qpr0/system` and `.../a17-qpr0/vendor`). Manual images go in `/etc/waydroid-extra/images/`.

### Cited Findings
- Release 20261017 is LineageOS 24.0 / Android 17 QPR0. It adds a Waydroid options tab in Settings, reworks the Audio HAL, fixes a crash on non-wlroots compositors, switches AMD to minigbm_gbm_mesa by default (switch back to minigbm for camera), ships no ARM64 images, and advises wiping Waydroid storage on upgrade errors (all data lost) — [release 20261017](https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20261017)
- The install command uses `waydroid init -f -c <...>/a17-qpr0/system -v <...>/a17-qpr0/vendor -r lineage -s GAPPS` against waydroid-atv.github.io. Manual install: copy system.img/vendor.img into `/etc/waydroid-extra/images/` and run `waydroid init -f` — [Releases page](https://github.com/WayDroid-ATV/waydroid-builds/releases); [release 20261017](https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20261017)
- SourceForge mirrors a ~1.5 GB GAPPS x86_64 system image for 20261017 — [SourceForge images](https://sourceforge.net/projects/waydroid-atv/files/images/)
- Known issue: scrcpy broke after upgrading from the pre-release A17 build to A17-qpr0 ("Pending dequeue output buffer request cancelled") — [waydroid-builds #51](https://github.com/WayDroid-ATV/waydroid-builds/issues/51)
- The ATV builds ship Widevine L3 (AIDL Widevine service) and Codec2 video decoders — [waydroid-androidtv-builds releases](https://github.com/WayDroid-ATV/waydroid-androidtv-builds/releases)
- A project update channel exists — [Telegram WayDroidATV](https://t.me/s/WayDroidATV)

### Inferences
- The exact OTA hostname path should be copied verbatim from the release page. The search snippet confirmed the host `waydroid-atv.github.io` and the `a17-qpr0/{system,vendor}` suffixes, but not the full URL.
- Because prebuilt images exist, the port can ship as an **overlay** (`/var/lib/waydroid/overlay/vendor/lib64/hw/audio.primary.*.so` plus `vendor/etc/audio_policy_configuration.xml`) on top of the stock 20261017 vendor image, provided the module is built against the same lineage-24.0 tree (same VNDK/ABI).

### Gaps
- Full OTA URL strings and whether VANILLA builds include Widevine (relevant to Apple Music, which needs Widevine L3).

## Q4. Is the original fix's target code present in lineage-24.0, and in what form?

### Takeaway
The original fix touches three things: (1) `audio_hw.c` format/rate handling in `adev_open_output_stream()`, adding 24-bit, 32-bit and **FLOAT32** cases and dropping the forced 16-bit/48 kHz; (2) the vendor `audio_policy_configuration.xml` primary mixPort set to `AUDIO_FORMAT_PCM_FLOAT`@48000+; (3) a **frameworks/av AudioFlinger** hack that adds `AUDIO_OUTPUT_FLAG_DIRECT` for the Apple Music UID read from `/data/local/tmp/apple_music_uid.txt`. Item 1 has since been proposed upstream almost verbatim as PR #80, and packaged for any image as `kanya-approve/android_hardware_waydroid-hires` (AUR `waydroid-apple-music`). Whether lineage-24.0's reworked HAL still has the hardcode is unverified.

### Cited Findings
- The original fix is Android-13-only, built on supechicken's A13 virt-wifi builds. It edits the Waydroid HAL to add 16/24/32-bit cases with a 16/48k default, adds FLOAT32 support (Apple Music uses float for 24-bit), and modifies AudioFlinger to force DIRECT for Apple Music. It ships as `vendor/` + `system/` overlay folders — local file `/home/akamamara/Apps/fork-waydroid-hires/waydroid_high-res_audio_fix_and_apple_music_fix.md` (from [Reddit post](https://www.reddit.com/r/waydroid/s/TjBa8AJyd3))
- PR #80 does the HAL plus policy part upstream. Its own test log shows a float format **hitting `LOG_ALWAYS_FATAL`**, which is the same FLOAT32 gap the Reddit author found — [PR #80](https://github.com/waydroid/android_hardware_waydroid/pull/80)
- AUR `waydroid-apple-music` 1.0.0-1 (maintainer kanya-approve, Apache-2.0, submitted Sept 2026, 0 votes) has upstream `github.com/kanya-approve/android_hardware_waydroid-hires`. It claims bit-perfect Apple Music via a "patched audio HAL, container properties, and app settings" that "works with any Waydroid image" — [AUR waydroid-apple-music](https://aur.archlinux.org/packages/waydroid-apple-music)
- svrkb/waydroid-sample-rate-switch is an overlay approach: it switches between 44.1/48 kHz at 16/24-bit with PipeWire output matched to it — [svrkb repo](https://github.com/svrkb/waydroid-sample-rate-switch)
- Background: Waydroid output stayed 48 kHz even with PipeWire at 192 kHz, blamed on Android resampling — [Ivon's Blog](https://ivonblog.com/en-us/posts/play-apple-music-android-on-linux/)

### Inferences
- The best base for the port is probably **PR #80's diff, rebased onto WayDroid-ATV lineage-24.0 `audio/audio_hw.c`**, plus a FLOAT32 → `SND_PCM_FORMAT_FLOAT_LE` case to avoid the fatal path and the PR #91 buffer sizing. That is simpler than replaying the A13 Reddit patch.
- The AudioFlinger DIRECT-flag hack lives in `frameworks/av/services/audioflinger` (or `audiopolicy`), which changed a lot between A13 and A17. It must be re-ported by hand and requires rebuilding the **system** image (or overlaying `libaudioflinger.so` from an identical-tree build). A less invasive A17 alternative is to declare a separate `direct` mixPort (`AUDIO_OUTPUT_FLAG_DIRECT`, PCM_FLOAT/24-bit, hi-res rates) in the policy XML. Android 14+ also exposes `AudioMixerAttributes` / bit-perfect mixer behavior (`AUDIO_OUTPUT_FLAG_BIT_PERFECT`, intended for USB devices). Whether Apple Music uses either is unverified.
- The Reddit Wi-Fi workaround came from supechicken's A13 virt-wifi builds. supechicken now runs the WayDroid-ATV org (the repos redirect from supechicken/*), so the A17 builds may already include virt-wifi. Unverified.

### Gaps
- An actual diff between the lineage-20 and lineage-24.0 `audio_hw.c` in WayDroid-ATV (blocked by the fetch failure).
- Whether kanya-approve's hires HAL publishes A17-compatible binaries.

## Q5. Open issues, PRs or discussions on audio quality, sample rate, Apple Music, or Widevine on the fork

### Takeaway
I found no WayDroid-ATV-specific issues on audio quality, sample rate or Apple Music. The relevant discussion is upstream (PR #80, PR #91, issue #2421) and in community repos and threads (AUR package, svrkb, CachyOS/Arch/Garuda "BIT Perfect Audio" threads). On Widevine, ATV builds ship L3, and there is a known login-crash workaround.

### Cited Findings
- Upstream audio PRs #80 and #91, and issue #2421, as cited above.
- "BIT Perfect Audio on Waydroid" threads report that PipeWire did not follow the track rate and that the `allowed-rates` default limited it — [CachyOS](https://discuss.cachyos.org/t/bit-perfect-audio-on-waydroid-using-bit-perfect-audio-from-waydroid/11294); [Garuda](https://forum.garudalinux.org/t/bit-perfect-audio-on-waydroid-using-bit-perfect-audio-from-waydroid/44934)
- ATV Widevine: L3 is built in. If the Widevine library is missing, the login prompt may crash; the workaround is to install Widevine or run `pm disable com.google.android.tungsten.setupwraith` — [waydroid-androidtv-builds releases](https://github.com/WayDroid-ATV/waydroid-androidtv-builds/releases)
- Apple Music on Waydroid: the app refuses lossless over Ethernet and complains when rooted — [waydroid #1514](https://github.com/waydroid/waydroid/issues/1514); [waydroid #1704](https://github.com/waydroid/waydroid/issues/1704)
- Waydroid audio degraded under Qubes sys-audio (not ATV-specific) — [Qubes forum](https://forum.qubes-os.org/t/global-irreversible-audio-degradation-with-waydroid-and-sys-audio/40139)

### Inferences
- An upstreamable contribution to WayDroid-ATV (PR to `android_hardware_waydroid` lineage-24.0: honor format/rate plus FLOAT32) would likely be welcome, since no competing ATV work turned up.

### Gaps
- I could not list the WayDroid-ATV issue trackers (waydroid-builds had about 32 issues per one snippet) or the `android_vendor_waydroid` PRs, nor confirm whether any mention audio.
- Verification checklist for the next pass (with working fetch):
  1. `https://api.github.com/repos/WayDroid-ATV/android_vendor_waydroid/git/trees/lineage-24.0?recursive=1` and `/commits?sha=lineage-24.0`
  2. `https://api.github.com/repos/WayDroid-ATV/android_hardware_waydroid/contents/audio?ref=lineage-24.0` → `audio_hw.c`, `Android.bp`, `audio_policy_configuration.xml`
  3. `WayDroid-ATV/android_device_waydroid_waydroid` lineage-24.0 `device.mk` / `manifest.xml` (grep `android.hardware.audio`)
  4. The merge status of PR #80/#91, and the kanya-approve/android_hardware_waydroid-hires README.
