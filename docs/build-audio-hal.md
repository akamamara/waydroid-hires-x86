# Build the fixed audio HAL APEX for WayDroid-ATV (LineageOS 24 / Android 17)

Builds the AIDL audio HAL with the PulseAudio stall fix and installs it into Waydroid through the overlay directory, next to the `audioserver` and policy XML overlays.

## Why

On 2026-11-10 `audioserver` was killed by its own watchdog (`TimeCheck timeout for IAudioFlinger::registerClient`). The HAL's PulseAudio writer was blocked in `pa_threaded_mainloop_wait` inside `StreamPulse::transfer`, waiting for the server to ask for more data. AudioFlinger's DIRECT thread was blocked in that write while holding its locks, other binder calls queued behind them, and after 5 s the watchdog aborted `audioserver`. Apple Music kept a broken connection afterwards and failed every later track (`getMinBufferSize(): error querying hardware`) until it was force-stopped.

The wait could never end on its own. `pause()` and `standby()` cork the PulseAudio stream, and the stream worker passes writes that arrive while paused or in standby straight to `transfer()`. A corked stream takes about one target latency of data (21 ms by default) and then asks for no more, so a larger write waited until the next `start()`. A seek on a DIRECT output (pause, flush, write new data, resume) fits that pattern. A host-side stall of a playing stream blocked the same way.

The patch `patches/hardware_interfaces/0001-audio-pulse-bound-stream-waits.patch`:

- never waits on a corked stream. The rest of the buffer goes to the server as pre-roll, and the server keeps what fits in its buffer.
- gives up on a playing stream that asks for no data within 500 ms. It drops the rest of that buffer, logs one warning per stall (`PulseAudio stream stalled for 500 ms`) and reports the write as done, so AudioFlinger keeps running. When the server asks for data again, playback continues on the same stream and the HAL logs `PulseAudio stream recovered from a stall`.
- stops waiting at once when the stream has failed.
- limits the connect waits and the cork, flush, drain and gain operations to 2 s (was unlimited for connect and 5 s for the rest), under the 3 s watchdog for calls made inside a binder transaction.

The HAL ships as the vendor APEX `com.android.hardware.audio`. The stock image has it at `/vendor/apex/com.android.hardware.audio.apex` (about 71 MB, not compressed), so the overlay replaces that one file.

## Before you start

- A LineageOS 24 tree for WayDroid-ATV, set up as in [build-libaudioflinger.md](build-libaudioflinger.md) sections 1 and 2. The commands below assume you are at its top.
- `hardware/interfaces` must include the Pulse backend, which landed on `lineage-24.0` on 2026-09-24. Check it:

  ```sh
  ls hardware/interfaces/audio/aidl/default/pulse/StreamPulse.cpp
  ```

  If the file is missing, the tree is older than that. Update only this project, so `frameworks/av` and its applied patch stay as they are:

  ```sh
  repo sync -c hardware/interfaces
  ```

## 1. Apply the patch

```sh
git -C hardware/interfaces switch -c pulse-bound-waits
git -C hardware/interfaces am ~/Apps/waydroid-hires-x86/patches/hardware_interfaces/0001-audio-pulse-bound-stream-waits.patch
git -C hardware/interfaces log --oneline -1      # audio: pulse: bound stream waits
```

The branch keeps the commit safe from a later `repo sync`, which would otherwise reset the detached checkout.

## 2. Build only the APEX

```sh
source build/envsetup.sh
lunch lineage_waydroid_x86_64_only-cp2a-userdebug
# the product lists packages this tree does not have (vulkan.broadcom and others), which fails kati otherwise
ALLOW_MISSING_DEPENDENCIES=true m com.android.hardware.audio -j8
f=out/target/product/waydroid_x86_64_only/vendor/apex/com.android.hardware.audio.apex; ls -l "$f"
```

Check that the right code went in. The APEX holds its files in an ext4 image, `apex_payload.img`:

```sh
d=$(mktemp -d); unzip -q -o "$f" apex_payload.img -d "$d"
debugfs -R 'dump /bin/hw/android.hardware.audio.service-aidl.example /tmp/ahal' "$d/apex_payload.img"
strings /tmp/ahal | grep -E "stalled for|recovered from a stall"   # both must appear
```

apexd only takes the file if it is signed with the same key as the stock APEX. A build from the WayDroid-ATV tree uses the same key, which you can confirm against the stock file:

```sh
debugfs -R 'dump /apex/com.android.hardware.audio.apex /tmp/stock.apex' /etc/waydroid-extra/images/vendor.img
unzip -p /tmp/stock.apex apex_pubkey | sha256sum; unzip -p "$f" apex_pubkey | sha256sum   # must match
```

Use the `vendor.img` from `images_path` in `/var/lib/waydroid/waydroid.cfg`.

## 3. Install

```sh
sudo waydroid session stop
sudo mkdir -p /var/lib/waydroid/overlay/vendor/apex
sudo install -m 644 -o root -g root "$f" /var/lib/waydroid/overlay/vendor/apex/com.android.hardware.audio.apex
sudo systemctl restart waydroid-container
waydroid session start
```

The repo also has a prebuilt copy at `overlay/vendor/apex/com.android.hardware.audio.apex`. Use it in place of `"$f"` if you do not build.

Confirm the new HAL is the one running:

```sh
sudo waydroid shell -- sh -c 'ls -l /apex | grep hardware.audio'
sudo waydroid shell -- sh -c 'strings /apex/com.android.hardware.audio/bin/hw/* | grep "stalled for"'
sudo waydroid shell -- logcat -d -b all | grep -iE "apexd.*hardware.audio"
```

The `strings` line must print the warning text. If apexd rejected the overlaid file, its log lines say so, and Android either keeps the stock HAL or has no audio at all. Roll back (below).

## 4. Check

`scripts/check-audio-stall.sh` drives pause, play, seek and track changes on the running session and prints PASS when `audioserver` kept its pid, no new tombstone appeared and no watchdog timeout was logged. Run it as your own user (not with `sudo`); it calls `sudo waydroid shell` itself.

Start a hi-res track in Apple Music, then:

```sh
scripts/check-audio-stall.sh -d 900            # 15 minutes of pause, play, seek, next and previous
scripts/check-audio-stall.sh -d 60 -s 10 -n    # one 10 s host sink suspend, no commands
```

For the second run, listen: playback should go on by itself within about a second after the sink resumes. The script prints the HAL's stall and recovery lines. If it notes that no stall warning was logged, the sink suspend did not stall the stream on your PipeWire setup, and the run proves nothing about stalls.

Normal playback must not change. Play 10 minutes through the mixer (any app other than the DIRECT one, 44.1 kHz/16-bit) and 10 minutes through DIRECT (a 96 kHz track in Apple Music), then:

```sh
sudo waydroid shell -- logcat -d | grep -E "AHAL_StreamPulse.*(stalled|not ready)"   # should be empty
sudo waydroid shell dumpsys media.audio_flinger | grep -iE "underrun|AudioOut_"
```

### Results

Build (2026-11-10, a 27 GB RAM / 12-core host, tree at `hardware/interfaces` `lineage-24.0` head `728aa6c`, BUILD_ID `CP2A.260605.016`):

- `m com.android.hardware.audio` finished in 16 minutes with no compiler warnings from the changed files.
- The APEX is 71,159,808 bytes. Its HAL binary `bin/hw/android.hardware.audio.service-aidl.example` holds the new stall and recovery log text.
- Its `apex_pubkey` and manifest name match the stock `com.android.hardware.audio.apex` from the 20261017 vendor image.

Install and the device checks above: not run yet.

## Rollback

```sh
sudo rm /var/lib/waydroid/overlay/vendor/apex/com.android.hardware.audio.apex
sudo waydroid session stop && sudo systemctl restart waydroid-container && waydroid session start
sudo waydroid shell -- sh -c 'strings /apex/com.android.hardware.audio/bin/hw/* | grep -c "stalled for"'   # 0: stock HAL again
```

If apexd will not take an overlaid vendor APEX, the fallback is a `vendorimage` built from the same tree (`m vendorimage`) and installed with `waydroid init -f`. That replaces the whole vendor image, takes much longer and is not covered here.

## Limits

- A stall still costs a gap of up to 500 ms per write while it lasts.
- The HAL connects to PulseAudio once per process. After a restart of the host's `pipewire-pulse`, Waydroid stays silent until the session is restarted. That was already true before the patch.
