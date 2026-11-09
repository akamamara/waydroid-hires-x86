# Waydroid hi-res audio for WayDroid-ATV (LineageOS 24 / Android 17)

A port of the Android 13 "Waydroid high-res audio fix and Apple Music fix" to the WayDroid-ATV LineageOS 24.0 image (release 20261017, x86_64).

On the stock image, all audio is mixed at 16-bit and up to 48 kHz. This repo gives you two things:

1. **Hi-res through the mixer.** A vendor policy XML overlay lets Android's mixer run in 32-bit float at up to 192 kHz. No build needed.
2. **Bit-perfect for one app.** A small patch to AudioFlinger sends one app's audio (for example Apple Music) to a DIRECT output. That audio keeps its own sample rate and format and skips Android's mixer and resampler. This needs a rebuilt `audioserver`, and a prebuilt copy is included.

Tested on one install: Apple Music plays a 96 kHz float track on its own DIRECT output thread, and PipeWire on the host shows a matching `Android Playback @ 96000Hz` stream. Details are in [docs/build-libaudioflinger.md](docs/build-libaudioflinger.md).

## Not covered

- The legacy `audio_hw.c` HAL, the AUR `waydroid-apple-music` package, Android 13 images and arm64.
- Bluetooth, recording and telephony audio paths. They stay as shipped.
- Apple Music's Wi-Fi-only lossless gate. If it blocks lossless, `persist.waydroid.fake_wifi` is the known workaround; it is not tested here.

## What is in this repo

| Path | What it is |
|---|---|
| `overlay/vendor/etc/primary_audio_policy_configuration.xml` | The shipped policy XML plus a float profile (44.1 to 192 kHz) on the primary output and a new `direct output` port. |
| `overlay/system/bin/audioserver` | `audioserver` built from the WayDroid-ATV `lineage-24.0` tree (BUILD_ID `CP2A.260605.016`) with the patch. |
| `overlay/system/lib64/libaudioflinger.so` | A by-product of the same build. `audioserver` links AudioFlinger statically and never loads this file, so installing it does nothing. |
| `patches/frameworks_av/0001-audioflinger-direct-output-for-uid.patch` | The source patch for `frameworks/av`, so you can rebuild it yourself. |
| `docs/build-libaudioflinger.md` | Step-by-step guide to build the patched `audioserver`, install it, test it and roll back. |
| `docs/plans/` | The plan this was built from. Its overlay target is out of date; the build guide has the correction. |
| `docs/handoff-libaudioflinger.md` | Session handoff with current state and open items. |
| `reports/`, `research_notes/` | Research behind the design. Start with the "Verified corrections" section of the report. |

## How it works

- **The XML is the format list.** The AIDL audio HAL builds its modules from `/vendor/etc/audio_policy_configuration.xml` and refuses anything outside the offered profiles. The shipped file offers only 16-bit PCM up to 48 kHz. The overlay adds float and a DIRECT port.
- **The patch picks the app.** In `AudioFlinger::createTrack`, a track from the UID in the property `persist.waydroid.direct_audio_uid` gets `AUDIO_OUTPUT_FLAG_DIRECT` when it is linear PCM and not offload or MMAP. The property is read for every new track, so changing it needs no restart.
- **Fallback is built in.** If no direct profile fits (for example a mono track), Android's policy manager drops the flag and the track plays through the mixer.

## Install

Back up first, or just keep the rollback below in mind. Each step takes effect after the restart at the end.

**1. Hi-res mixer and the DIRECT port (the XML)**

```sh
sudo mkdir -p /var/lib/waydroid/overlay/vendor/etc
sudo cp overlay/vendor/etc/primary_audio_policy_configuration.xml /var/lib/waydroid/overlay/vendor/etc/
```

**2. Bit-perfect for one app (optional)**

```sh
sudo mkdir -p /var/lib/waydroid/overlay/system/bin
sudo install -m 755 -o root -g root overlay/system/bin/audioserver /var/lib/waydroid/overlay/system/bin/audioserver
```

Find the app's UID. For user 0 it equals the `appId`:

```sh
sudo waydroid shell cmd package list packages -U | grep -i apple      # package:com.apple.android.music uid:10113
waydroid prop set persist.waydroid.direct_audio_uid 10113
```

**3. Restart**

```sh
sudo waydroid session stop && sudo systemctl restart waydroid-container && waydroid session start
```

## Check that it works

Play a hi-res track, then:

```sh
sudo waydroid shell -- logcat -d | grep "direct output for uid"     # shows the uid, format and rate
sudo waydroid shell dumpsys media.audio_flinger | grep -A14 "type 1 (DIRECT)"
pactl list sink-inputs | grep -iE "Sample Specification|media.name"
```

You should see a DIRECT thread at the track's rate carrying the app's track, and a PipeWire stream at that rate. A second stream at 192000 Hz that stays idle is the mixer, which is normal.

## Roll back

```sh
sudo rm -f /var/lib/waydroid/overlay/system/bin/audioserver
sudo rm -f /var/lib/waydroid/overlay/vendor/etc/primary_audio_policy_configuration.xml
sudo waydroid session stop && sudo systemctl restart waydroid-container && waydroid session start
```

## Known limits

- **The prebuilt `audioserver` comes from a different build than your image.** It was built from a May 2026 tree, and the image is release 20261017. It worked on the tested install. If `audioserver` crash-loops on yours, remove the file as above and rebuild from your own tree with the guide.
- **Other audio is still resampled.** Everything except the chosen app goes through the mixer, which runs at 192 kHz float. Removing `176400 192000` from the float profile of `primary output` in the XML lowers it to 96 kHz; removing the rates above 48000 gives 48 kHz.
- **Volume on the DIRECT path is untested.** Android's volume slider may not change the level of the DIRECT output; control the volume on the host or your DAC.
- **Gapless playback is not guaranteed.** Each new track opens a new DIRECT thread.
- **The host's PipeWire must allow the rate.** If `default.clock.allowed-rates` lacks it, PipeWire resamples on the host. Check with `pw-top`.
- **Only linear PCM tracks are redirected.** Compressed or offload streams are not.

## Building it yourself

See [docs/build-libaudioflinger.md](docs/build-libaudioflinger.md). In short: sync the WayDroid-ATV `lineage-24.0` tree, apply the patch to `frameworks/av`, run `lunch lineage_waydroid_x86_64_only-cp2a-userdebug`, then `m audioserver`. A full tree needs about 250 GB of free disk, and the analysis step is memory-hungry; a 16 GB machine may need a large swapfile or a bigger machine.

## Licence

The XML overlay is derived from the Android Open Source Project and keeps its Apache 2.0 header. The patch applies to AOSP code, which is Apache 2.0. The prebuilt binaries are built from the WayDroid-ATV and LineageOS sources, so their licences apply. This repo does not declare a separate licence of its own.
