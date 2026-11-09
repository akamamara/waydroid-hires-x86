# Anatomy of the original Waydroid "High-Res Audio Fix and Apple Music Fix"

Research method note (2026-11-07): WebFetch and Bash were blocked by a broken context-mode hook (NODE_TOO_OLD), so no page could be opened in full. The Reddit post, the Google Drive folder, the GitHub repos and PR #80 were **not read directly**. Everything below comes from (a) the local copy of the post, `/home/akamamara/Apps/fork-waydroid-hires/waydroid_high-res_audio_fix_and_apple_music_fix.md` (cited as [Local post]), and (b) WebSearch result summaries, which are second-hand and can be wrong. Anything that would need the Drive binaries or the actual diffs is listed under Gaps.

[Local post]: file:///home/akamamara/Apps/fork-waydroid-hires/waydroid_high-res_audio_fix_and_apple_music_fix.md

## 1. Which components are modified (files, nature of each diff)

### Takeaway
The original fix changes three things: (1) the Waydroid vendor audio HAL (`android_hardware_waydroid/audio/audio_hw.c`), so it stops forcing S16_LE/48 kHz and accepts 16/24/32-bit and PCM_FLOAT at the requested rate; (2) `/vendor/etc/audio_policy_configuration.xml`, so it advertises those formats and rates (default primary output is PCM_FLOAT @ 48 kHz); (3) the system-side AudioFlinger in `frameworks/av`, so it adds `AUDIO_OUTPUT_FLAG_DIRECT` to Apple Music's tracks (the app is found by UID read from a file). The author published only binaries (Drive), not a source diff.

### Cited Findings
- The author first edited `/vendor/etc/audio_policy_configuration.xml`, and that alone did nothing, because Waydroid's custom HAL is what sends Android's mixed audio to PipeWire. — [Local post]
- The HAL limits the author found: "16bit 48khz was being forced with no possibility of high-res … The HAL simply says 'ok lets do 16bit'", and "FLOAT32 audio was neglected in the switch case." — [Local post]
- HAL change 1: "I added a switch case of 24bit audio, 16bit audio, 32 bit audio and a default safety cushion of 16bit 48khz in the switch case and edited the configuration file according to that", which gave "working 24bit audio with unlocked sample rate". — [Local post]
- HAL change 2, added later: float32 support in the Waydroid HAL. After it, DIRECT output also worked for 24-bit, "because apple music internally uses Float32 format for 24bit audio". — [Local post]
- Framework change: "the audio output flags are decided by AudioFlinger so i modified it to detect when apple music is running and forcefully added DIRECT audio flag." — [Local post]
- The app is detected by UID. The user runs `adb shell dumpsys package com.apple.android.music | grep userId` and writes the number to `~/.local/share/waydroid/data/local/tmp/apple_music_uid.txt`, which is `/data/local/tmp/apple_music_uid.txt` inside Android. The post spells the path `~./local/...`, a typo. — [Local post]
- The shipped XML's primary output: `<mixPort name="primary output" role="source" flags="AUDIO_OUTPUT_FLAG_PRIMARY">` with `<profile format="AUDIO_FORMAT_PCM_FLOAT" samplingRates="48000">`. The user can change it to 192000 etc. — [Local post]
- Independent confirmation of the stock HAL behaviour (PR #80, opened by kanya-approve against the `lineage-20` branch): `adev_open_output_stream()` hardcodes every output stream to S16_LE at `PLAYBACK_CODEC_SAMPLING_RATE`, and the float case in the format-conversion helper is treated as unsupported and hits a fatal log. — [PR #80](https://github.com/waydroid/android_hardware_waydroid/pull/80) (via search summary)
- PR #80 adds the mapping from `AUDIO_FORMAT_PCM_FLOAT` to ALSA float sample formats in both directions, opens output streams at the requested format and rate, and widens the policy to advertise float and standard rates. It deliberately leaves out a DIRECT mix port, arguing the primary output can carry 192 kHz once the HAL honours the request. It is marked untested, and its merge status is unknown. — [PR #80](https://github.com/waydroid/android_hardware_waydroid/pull/80) (via search summary)
- The lineage-18.1 Waydroid `audio_hw.c` opens an ALSA PCM named `"pulse"` with `snd_pcm_open` and sets a `PULSE_RUNTIME_PATH` property. So the HAL reaches the host through the alsa-lib pulse plugin, not `pa_simple`. On the host, PipeWire sees the stream as a node like `binder:114_2`. — [CachyOS forum thread](https://discuss.cachyos.org/t/bit-perfect-audio-on-waydroid-using-bit-perfect-audio-from-waydroid/11294) (via search summary)

### Inferences
- Concrete source paths, assuming the Waydroid/LineageOS 20 tree layout. These are not confirmed from a diff:
  - `hardware/waydroid/audio/audio_hw.c` (repo `waydroid/android_hardware_waydroid`, branch `lineage-20`): the format switch in `adev_open_output_stream` / `out_*` and the audio_format to `snd_pcm_format_t` helper (add `AUDIO_FORMAT_PCM_FLOAT`→`SND_PCM_FORMAT_FLOAT_LE`, `PCM_24_BIT_PACKED`/`8_24`→`S24_3LE`/`S24_LE`, `PCM_32_BIT`→`S32_LE`), plus using `config->sample_rate` instead of the constant.
  - The device tree's `audio_policy_configuration.xml`, installed to `/vendor/etc/`. In Waydroid it most likely comes from `device/waydroid/waydroid`.
  - `frameworks/av/services/audioflinger/` (probably `AudioFlinger::createTrack` / `openOutput` flag handling) or `frameworks/av/services/audiopolicy/` (`getOutputForAttr`). The post says only "AudioFlinger". Forcing DIRECT for a UID read from `/data/local/tmp` means the code reads a file at runtime (audioserver needs read access; SELinux may matter).
- No changes to PipeWire, PulseAudio or the host are made by the fix itself. The host side is configuration only, using Ivon's PipeWire `default.clock.allowed-rates` guide.
- PR #80 / `kanya-approve/android_hardware_waydroid-hires` is a later, separate reimplementation of the same HAL idea, not the original author's code (see section 5).

### Gaps
- The actual diffs, function names, lines and commits: the author published no source. The Drive folder (`1YsdesaHC1sWbwhXJYwSZ-sa-TKyon1Je`) could not be listed.
- Whether the AudioFlinger patch is in `AudioFlinger.cpp`, `Threads.cpp` or the AudioPolicyManager.
- Whether the shipped XML also has a `direct pcm` mixPort with `AUDIO_OUTPUT_FLAG_DIRECT`. Forcing DIRECT needs a matching profile, so it very likely does, but this is unverified.

## 2. Android/LineageOS base and HAL API dependency

### Takeaway
Android 13 only, meaning Waydroid's LineageOS 20 base, used through supechicken's waydroid-builds Android 13 image. The HAL is Waydroid's legacy libhardware `audio_hw_device` C HAL (`audio.primary.*.so`), loaded by the stock HIDL audio service (android.hardware.audio@7.x default wrapper on A13). It is not an AIDL audio HAL.

### Cited Findings
- The author ran "Waydroid with Android 13 on CachyOS". — [Local post]
- "Use this android-13 build only … my modifications are different for different android versions so they will work on android 13 only." — [Local post]
- supechicken/waydroid-builds offers Android 13 to 16 Waydroid builds. Release `20260201-eos` is /e/OS 3.4 (Android 13). Install is by extracting system/vendor images into Waydroid's images directory, and a clean install is recommended. — [newreleases.io: waydroid-builds 20260201-eos](https://newreleases.io/project/github/supechicken/waydroid-builds/release/20260201-eos); [oosmetrics: supechicken](https://oosmetrics.com/u/supechicken)
- Upstream Waydroid's Android 13 HAL lives on the `lineage-20` branch of `android_hardware_waydroid` (PR #80 targets that branch). — [PR #80](https://github.com/waydroid/android_hardware_waydroid/pull/80)
- The legacy HAL entry point `adev_open_output_stream` is part of the libhardware `audio_hw_device` interface. — [AOSP libhardware audio_hw.c](https://android.googlesource.com/platform/hardware/libhardware/+/master/modules/audio/audio_hw.c); [audio_hw_device reference](https://source.android.com/reference/hal/structaudio__hw__device)

### Inferences
- Because the system-side patched AudioFlinger is a binary, it is tied to the exact A13 framework build (supechicken's image). Mixing it with another system.img (official Waydroid LineageOS 20, or a different supechicken release such as the /e/OS-based one) risks ABI or symbol mismatch. This is probably why the author says "use this build only".
- In AOSP 14 and later, the default audio HAL moved toward AIDL (`android.hardware.audio.core`), but Waydroid's legacy C HAL still loads through the HIDL/legacy wrapper wherever the image ships it. An Android 17 port would need to check which wrapper the image uses. Not verified here.

### Gaps
- Which supechicken release (date or tag) the author used. The release list says Android 13 builds are /e/OS-based in 2026, but the author's build may have been LineageOS 20-based.
- The exact HIDL audio HAL version in that image.

## 3. Output artifacts, partitions, installation, standalone build

### Takeaway
The fix ships as prebuilt files in two overlay trees, `vendor/` and `system/`, copied into `/var/lib/waydroid/overlay/`. No image is rebuilt. `vendor/` holds the patched HAL plus the policy XML and is enough for hi-res through the mixer. `system/` holds the patched AudioFlinger and is optional; it is needed only for the forced DIRECT (non-resampled) path.

### Cited Findings
- Install steps: download the Drive folder, move "vendor" and "system" to `/var/lib/waydroid/overlay/`. "If you are happy with android resampling then you dont need system folder. Please delete it." — [Local post]
- The shipped `vendor/etc/audio_policy_configuration.xml` can be edited in place. — [Local post]
- A later project uses the same overlay mechanism: it builds a checksum-guarded overlay from the user's own vendor image, writes the patched HAL and `audio_policy_configuration.xml` into Waydroid's overlay directory, and refuses to install if the vendor files don't match tested checksums. It was tested on Waydroid 1.6.2 with an Android 13 image. — [svrkb/waydroid-sample-rate-switch](https://github.com/svrkb/waydroid-sample-rate-switch) (via search summary)

### Inferences
- Likely artifact names, inferred from Waydroid conventions and not confirmed against the Drive contents:
  - `vendor/lib64/hw/audio.primary.waydroid.so` (and maybe `vendor/lib/hw/…` for 32-bit). One `cc_library_shared` module in `hardware/waydroid/audio/Android.bp`/`.mk`, which can be built standalone with `m audio.primary.waydroid` in a lunch'd waydroid tree.
  - `vendor/etc/audio_policy_configuration.xml`.
  - `system/lib64/libaudioflinger.so` (the AudioFlinger code is a shared library loaded by `audioserver`). It can be built with `m libaudioflinger`, but the module ABI is tied to the matching system image. If the policy-manager route was used instead, the file is `libaudiopolicymanagerdefault.so`.
- The vendor part is a self-contained single-module rebuild. The system part is not portable across system images.

### Gaps
- The real file list and sizes in the Drive folder. Check for 32-bit libs, extra configs (`audio_policy_volumes.xml`, `default_volume_tables.xml`) and props.
- Whether any build.prop changes are shipped. The post mentions none.

## 4. The Apple Music fix: what was broken and why; independence from the audio patch

### Takeaway
The "Apple Music fix" is not about DRM or Widevine. It has three parts. (a) Lossless won't unlock because Waydroid's network shows as Ethernet and Apple Music allows lossless streaming only on Wi-Fi or cellular; supechicken's A13 build fixes this by exposing a virt-wifi interface, with an older alternative being a fake-wifi prop. (b) Animated artwork must be turned off. (c) An AudioFlinger patch forces DIRECT output for Apple Music's UID, so Apple Music's PCM_FLOAT 24-bit stream skips the mixer and resampler. Part (a) is independent of the audio patch. Part (c) depends on the HAL's float32 support.

### Cited Findings
- "Apple Music denied running Lossless because that was only supported on Wi-Fi but waydroid actually used Bridged networking (via lxcbr0 / host bridge) detected as Ethernet." Fix: supechicken's android-13 build, which "fixes lossless streaming on ethernet by using virt-wifi". — [Local post]
- Alternative used earlier by the community: Apple Music checks for Wi-Fi or mobile data but not Ethernet. Setting `waydroid prop set persist.waydroid.fake_wifi <package>` for the Apple Music package unlocks lossless. — [Lemmy.World post](https://lemmy.world/post/1771401); [gist: Apple music lossless linux](https://gist.github.com/sohamukute/076ff3f4a40ee5dbc9acbe226cee2b95)
- Waydroid issue: Apple Music reports "no internet" over Waydroid's Ethernet. A commenter says lossless only works on Wi-Fi. Another asks how to patch the HAL for 24-bit. A user reports "@Prak005's guide" worked, linking a Reddit post (r/iemlndia). — [waydroid/waydroid#1514](https://github.com/waydroid/waydroid/issues/1514) (via search summary)
- "For Apple Music Users - Go to Settings → Motion. Turn off animated art. Its very important." No reason given. — [Local post]
- Apple Music uses Float32 for its 24-bit output. DIRECT 16-bit worked, but DIRECT 24-bit only worked after the HAL gained float32 support. — [Local post]
- Apple tiers: Lossless up to 24-bit/48 kHz, Hi-Res Lossless up to 24-bit/192 kHz. On Android, rates above 48 kHz may need an external DAC. — [Apple support](https://support.apple.com/fr-afri/guide/music/mus90b573cbb/mac) (via search summary)
- Before the fix, Apple Music could request 192 kHz, but Waydroid delivered 48 kHz to the host (pw-top), which Ivon attributes to Android's SRC/mixer. Ivon's guide raises PipeWire's allowed rates. — [Ivon's Blog](https://ivonblog.com/en-us/posts/play-apple-music-android-on-linux/)
- A separate Waydroid guide notes a workaround for Apple Music's "no longer available on rooted devices" message, done by editing the Waydroid config. — mentioned in a search summary only, no primary source opened.

### Inferences
- The Wi-Fi/virt-wifi part is purely a network-type detection issue and works with stock audio. Widevine/DRM is not part of this fix. Apple Music streams, including lossless ALAC, play with the Widevine L3 that supechicken builds ship; I found no source saying DRM was broken.
- "Turn off animated art" is probably needed because motion-art video playback (a MediaCodec/video track with its own audio session or surface) interferes with the forced-DIRECT path or hurts performance. This is speculation; the author gives no reason.
- UID-based DIRECT forcing is an alternative to Android 14+'s `AudioMixerAttributes` bit-perfect API, which apps must opt into. Android 13 has no such API, and Apple Music doesn't use it.

### Gaps
- The exact reason for the animated-art requirement.
- Whether supechicken's virt-wifi is a build-time framework change or a prop, and in which commit or release it appeared.

## 5. Known issues, follow-ups, forks, later versions; dates

### Takeaway
The original post (undated here, since the Reddit page could not be opened; it comes from the Waydroid community before mid-2026, most likely by Reddit user Prak005) set off several follow-ups. These include an upstream HAL PR (#80, lineage-20, by kanya-approve) with a fork `kanya-approve/android_hardware_waydroid-hires` and an AUR package `waydroid-apple-music`, plus svrkb's checksum-guarded overlay tools. All of them target the Waydroid HAL only. None of them reproduce the AudioFlinger DIRECT patch.

### Cited Findings
- `kanya-approve/android_hardware_waydroid-hires`: a fork of the upstream Waydroid hardware repo (audio, gralloc, hwcomposer, …) with 1 star. — [GitHub repo](https://github.com/kanya-approve/android_hardware_waydroid-hires) (via search summary)
- AUR `waydroid-apple-music` (maintainer kanya-approve, 0 votes): "bit-perfect Apple Music on Waydroid: patched audio HAL, container properties, and app settings"; works with any Waydroid image and ships neither the image nor the app. Its upstream URL is the -hires fork. — [AUR](https://aur.archlinux.org/packages/waydroid-apple-music) (via search summary)
- svrkb/waydroid-sample-rate-switch: switches Waydroid between 44.1/48 kHz at 16/24-bit with matched PipeWire output. It patches HAL binaries and states that upstream still hardcodes 48 kHz/16-bit. — [GitHub](https://github.com/svrkb/waydroid-sample-rate-switch)
- svrkb/waydroid-apple-music: Apple Music on Waydroid with Linux media controls and an optional shared 32-bit/192 kHz path. It says this is not automatic sample-rate switching and does not make 44.1 kHz content into real 192 kHz. — [GitHub](https://github.com/svrkb/waydroid-apple-music)
- Earlier attempts: CachyOS/Arch/Garuda "BIT Perfect Audio on Waydroid" threads (about 484 days old as of the search, so roughly mid-2025) proposed virtual ALSA nodes plus WirePlumber routing, and noted PipeWire doesn't follow the track's rate. — [CachyOS](https://discuss.cachyos.org/t/bit-perfect-audio-on-waydroid-using-bit-perfect-audio-from-waydroid/11294); [Arch](https://bbs.archlinux.org/viewtopic.php?id=306897); [Garuda](https://forum.garudalinux.org/t/bit-perfect-audio-on-waydroid-using-bit-perfect-audio-from-waydroid/44934)
- Arch thread "Bypassing android 16 bit/48kHz audio resampling in waydroid": a reply says a patched audio HAL is the minimum needed and links to a Reddit post describing the method. — [Arch forum 312445](https://bbs.archlinux.org/viewtopic.php?id=312445)
- Reddit snapshot pages for r/waydroid posts dated 2026-06-12 and 2026-06-15 exist on reddit.sentinel-team.org. They may be this post or related ones, but this is unverified. — [snapshot 1u3e0bs](https://reddit.sentinel-team.org/posts/1u3e0bs/snapshots/2026-06-12T18%3A44%3A42.360004Z); [snapshot 1u5u9c6](https://reddit.sentinel-team.org/posts/1u5u9c6/snapshots/2026-06-15T23%3A18%3A40.545619Z)

### Inferences
- Known limitations of the original fix, from the post itself: Android 13 / supechicken build only; a fixed sample rate set in XML with no automatic per-track switching (the PipeWire allowed-rates config does the host-side switching); the UID file is needed for DIRECT mode; animated art must be off. The post asks readers to report problems, but the comments were not retrieved.
- For an Android 17 fork, the PR #80 approach (HAL honours the requested format and rate, primary port advertises float plus multiple rates, no framework patch) is a lower-maintenance route than the original's AudioFlinger patch. That patch would have to be redone for every framework version.

### Gaps
- Post date, author handle confirmation, upvotes and comments: Reddit could not be fetched.
- Whether PR #80 was merged, and its dates.
- Contents, dates and file hashes of the Google Drive folders (files and images).
