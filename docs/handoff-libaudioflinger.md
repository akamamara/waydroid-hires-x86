---
artifact_contract: "ce-handoff/v1"
created_at: "2026-11-08T13:46:00Z"
title: "Waydroid hi-res audio on LineageOS 24: libaudioflinger build in progress"
summary: "Vendor XML overlay works on the user's Waydroid; the patched libaudioflinger build (LOS 24 tree, lunch passed) has not yet shown an m nothing or build result."
keywords: ["waydroid", "lineageos-24", "android-17", "audioflinger", "bit-perfect", "apple-music", "aosp-build"]
cwd: "/home/akamamara/Apps/fork-waydroid-hires"
resume_focus: "Get the patched libaudioflinger built and overlaid, or decide the mixer-rate cap; the user's last open topic was copying the tree to a 32 GB PC"
repository: "fork-waydroid-hires (local only, no remote)"
repo_root_sha: "023e9d5d282892c7229eea3a5be5e39adec01495"
branch: "feat/waydroid-hires-audio-lineage24"
head: "e40842cdaa5ffc37093a5e9e46a9b1632a049faf"
---

# Waydroid hi-res audio on LineageOS 24: handoff

## Correction (2026-11-09, after this handoff was written)

The overlay target is wrong throughout this handoff and the plan. `audioserver` links `libaudioflinger` statically (`frameworks/av/media/audioserver/Android.bp`, `static_libs`), so an overlaid `libaudioflinger.so` is never loaded. The patch only takes effect in a rebuilt `/system/bin/audioserver`: build with `m audioserver -j8` and overlay `/var/lib/waydroid/overlay/system/bin/audioserver` (mode 755, root). `docs/build-libaudioflinger.md` has the corrected steps. Evidence: the running audioserver had no `libaudioflinger.so` in its maps, and no "direct output for uid" log line appeared. The patch strings are present in the built `.so` (checked), so the patch itself is not the problem.

**Result after the fix:** with the patched `audioserver` overlaid, Apple Music (uid 10113) plays on a DIRECT thread at its own rate (96000 Hz float for the hi-res track, 44100 Hz 16-bit for the others), and PipeWire shows a matching `@ 96000Hz` stream. See "Verified result" in `docs/build-libaudioflinger.md`. Still open: the primary mixer stays at 192 kHz float for all other audio (an optional cap in the XML, 96 or 48 kHz, was offered and not answered), Android volume on the DIRECT path is untested, and gapless playback between tracks is untested.

## Objective

Port the user's Android 13 hi-res audio and Apple Music fix (`waydroid_high-res_audio_fix_and_apple_music_fix.md`) to WayDroid-ATV LineageOS 24.0 / Android 17 (release 20261017, x86_64 only). Two goals, both chosen by the user: hi-res output through the mixer, and bit-perfect (DIRECT, no resampling) playback for Apple Music. The user wants the smallest possible build because their main PC has 16 GB RAM and a Ryzen 7700F.

## Work completed

- Research report, notes and a plan, written earlier in the session (see references). The report's body was partly wrong; its top section "Verified corrections" supersedes it.
- `ce-work` ran the plan's code units. Two local commits on `feat/waydroid-hires-audio-lineage24` (no remote, nothing pushed):
  - `023e9d5`: `overlay/vendor/etc/primary_audio_policy_configuration.xml` (adds PCM_FLOAT 44.1 to 192 kHz to the primary output, plus a new `direct output` port with float, 24-bit packed, 32-bit and 16-bit stereo, routed to Speaker).
  - `e40842c`: `patches/frameworks_av/0001-audioflinger-direct-output-for-uid.patch`. In `AudioFlinger::createTrack`, a track from the UID in `persist.waydroid.direct_audio_uid` gets `AUDIO_OUTPUT_FLAG_DIRECT` (FAST and DEEP_BUFFER cleared) when its format is linear PCM and it is not offload or MMAP. The property is read per track.
- Code review (`ce-code-review`, lite path, run `20261107-122624-41ee369b` under `/tmp/compound-engineering-1000/ce-code-review/`): no findings, verdict "Ready to merge". Residual risks are listed below.
- `docs/build-libaudioflinger.md` (untracked, not committed): step-by-step build, install, test and rollback guide, written at the user's request.

## Decisions and who made them

- User's decision: build it themselves rather than ask the WayDroid-ATV maintainer to add profiles upstream, and include the bit-perfect path for Apple Music (recorded in the plan as session-settled).
- My call: the DIRECT mixPort plus a UID check in `createTrack` as the bit-perfect mechanism. The Android 14+ bit-perfect mixer API is USB-only per the source, so it was not an option.
- My call: skip `generate-manifest.sh` and copy the three manifest XML files into `.repo/local_manifests` directly, because the script lives in `vendor/extra`, which exists only after the first sync. This deviates from plan unit U3 step 2. The plan body was not edited (ce-work rule).
- My call: build the `lineage_waydroid_x86_64_only` variant, to match the "x86_64 only" release. The plan names `lineage_waydroid_x86_64`; neither was confirmed against the user's installed image.
- Not decided: the mixer rate cap (see next steps). I asked the user to pick 96 or 48 kHz and they have not answered.

## Current state

Observed on the user's Waydroid (from their pastes, so verified by them, not by me):

- The overlay XML is installed and loaded. `dumpsys media.audio_policy` lists the float profile on `primary output` and the four-profile `direct output`.
- The mixer (`AudioOut_D`, MIXER) runs at 192000 Hz float, and `pactl` shows `Android Playback @ 192000Hz`. So every stream, including a 44.1 kHz song, is still upsampled by Android's mixer. This is what the cap would address.
- A DIRECT thread `AudioOut_15` exists at 44100 Hz float with no evidence of a client. Why it opens is unexplained.
- Apple Music's track row (from `dumpsys media.audio_flinger`): client `1928/10113`, Flags `0x000`, Format `00000005` (PCM_FLOAT), stereo, SRate 96000. I read it as plain PCM. Which thread block it sat under was cut off by the user's `grep`; I assumed the mixer thread.
- The user reports having run `waydroid prop set persist.waydroid.direct_audio_uid` (value not shown; presumably 10113). It has no effect until the patched library is installed.

Observed on the user's build tree `~/los24` (their pastes):

- `repo init` and `repo sync` done with the WayDroid-ATV manifests.
- `vendor/extra/waydroid-patches/apply-patches.sh` ran and reported one conflict, in `packages/apps/SetupWizard` (a first-run wizard patch; irrelevant to audio). No other project conflicted, per their output.
- `git -C frameworks/av am <patch>` failed with "Stray .git/rebase-apply directory found". I gave the `am --abort` fix. I have not seen whether it worked or whether the patch commit is on `frameworks/av` now.
- `lunch lineage_waydroid_x86_64_only-cp2a-userdebug` succeeded: Android 17, `BUILD_ID=CP2A.260605.016`. The release token `cp2a` comes from `vendor/lineage/vars/aosp_target_release`.
- No `m nothing` or `m libaudioflinger` result has been reported. The 16 GB machine may not finish `m nothing`.
- The user then asked about copying the tree to a second PC (32 GB RAM, Ryzen 5 3xxx, same OS). I advised `rsync -aH --exclude=/out` to a case-sensitive Linux filesystem at the same path, or a single `tar` archive if the transfer drive is HFS+ (a plain HFS+ copy is unsuitable). They have not said which they chose.

## Not verified

- The patch has never been compiled; only `git apply --check` against a fresh copy of the file was run.
- Whether a library built from a May 2026 tree (`CP2A.260605.016`) runs against the prebuilt 20261017 image. If audioserver crash-loops, remove the overlay file and the fallback is building matching system and vendor images (plan unit U5, hours on 16 GB).
- Whether the property name, 33 characters long, passes through `waydroid prop set` into the container (the user reported setting it; I did not see `getprop` output).
- Whether PipeWire passes a 96 kHz stream unresampled (`default.clock.allowed-rates`).
- Apple Music's Wi-Fi-only lossless gate is out of the plan's scope.
- Nothing in this session was tested on a device by me.

## Failed or abandoned approaches

- The original Android 13 approach (edit the legacy `audio_hw.c` and build with the NDK) does not apply: WayDroid-ATV removed that HAL on 2026-09-22. The AIDL HAL with a PulseAudio backend replaced it.
- My earlier claim that an XML-only change could not lift the 16-bit limit was wrong; the XML is the format list, and the overlay now works.
- Running `generate-manifest.sh` as the plan says: do not retry; the script is not available before the first sync.
- A bare `lunch` fails ("No target specified"); the full `product-release-variant` string is needed.
- A raw tree object cannot be a base for the code-review helper; I used an unreferenced empty commit `384b8e764c719d26421fd1495444ac6bdf78ab0b` instead (no history change).

## References

- `docs/plans/2026-11-07-1209-feat-waydroid-hires-audio-lineage24-plan.md` (untracked): requirements R1 to R7, KTD1 to KTD5, units U1 to U5. U3 (build setup) and U5 (fallback images) are host-side by design.
- `docs/build-libaudioflinger.md` (untracked): the commands for everything left, including rollback.
- `reports/Waydroid hires audio fork Android 17.md` (untracked): read its "Verified corrections" section first.
- `patches/frameworks_av/0001-audioflinger-direct-output-for-uid.patch`: the patch, 15 added lines in `createTrack` before `AudioSystem::getOutputForAttr`.
- `overlay/vendor/etc/primary_audio_policy_configuration.xml`: the overlay; install target `/var/lib/waydroid/overlay/vendor/etc/` (machine-local).
- Upstream sources used: WayDroid-ATV `android_frameworks_av` lineage-24.0 (`AudioFlinger.cpp`, `AudioPolicyManager.cpp:1989` drops DIRECT when no direct output opens, `Threads.cpp:2612-2615` masks flags a thread lacks); `android_hardware_interfaces` lineage-24.0 (`ModulePrimary.cpp` routes any non-MMAP, non-offload output to the Pulse stream); `android_vendor_waydroid` lineage-24.0 (`manifest_scripts/manifests-37/`, `waydroid-patches/apply-patches.sh`).
- Machine-local: build tree `~/los24` (not in this repo), scratch files under `/tmp/claude-1000/...`.

## Fragile or unrelated local state

- `git status` in this repo also shows untracked `.nvmrc`, `KernelSU/`, `kernelsu-dkms-waydroid/` and `vendor.img`. I did not create these and do not know their purpose; leave them alone unless the user says otherwise.
- The plan, reports and notes are untracked and uncommitted. `/tmp` handoff and review files are not permanent.
- A separate forked session named "Waydroid high-res audio fix port" (id `3b8ac188`) exists. I have not seen what it did.

## Plausible next steps

One path, in order, taken from `docs/build-libaudioflinger.md` sections 3 to 6: confirm the patch commit is on `frameworks/av`; run `time m nothing` (stop and use the 32 GB PC or a VM if it is OOM-killed); `m libaudioflinger -j8`; copy `libaudioflinger.so` to `/var/lib/waydroid/overlay/system/lib64/`; restart the session; check `logcat -b crash`, the "direct output for uid" log line, the DIRECT thread and `pactl`.

Separate decision for the user: cap the primary mixer's float rates at 96000 (or 48000) in the overlay XML, so non-bit-perfect audio is not upsampled to 192 kHz. This is independent of the build.

## Skills that may help

`compound-engineering:ce-work` and `ce-code-review` were used. `compound-engineering:ce-debug` fits if the build or the audioserver crash-loop needs diagnosis.
