# Build the patched `audioserver` for WayDroid-ATV (LineageOS 24 / Android 17)

Builds the patched `audioserver` binary and installs it into Waydroid through the overlay directory. The patch makes tracks from one app UID request a DIRECT output, so they skip the mixer and keep their own sample rate and format.

**Build `audioserver`, not `libaudioflinger.so`.** `frameworks/av/media/audioserver/Android.bp` links `libaudioflinger` under `static_libs`, so AudioFlinger is compiled into `/system/bin/audioserver`. An overlaid `libaudioflinger.so` is never loaded (checked on a running Waydroid: `/proc/<audioserver pid>/maps` has no `libaudioflinger.so`, and the patch log line never appears). The file name of this guide is historical.

Nothing else is rebuilt. The vendor XML overlay (`overlay/vendor/etc/primary_audio_policy_configuration.xml`) must already be installed. The DIRECT output port it defines is what the patch sends tracks to.

Everything below was checked against the sources, but the build itself has only been run step by step with the outputs noted in each section. Anything marked "expect" is what should happen, not a recorded result.

## Before you start

- At least 250 GB free disk. The checkout alone is about 100 GB with `--depth=1`, and `out/` adds more.
- The vendor XML overlay is installed and works. Check it first:

  ```sh
  sudo waydroid shell dumpsys media.audio_policy | grep -iE -A8 "direct output"
  ```

  It should list `direct output` with four profiles.
- Apple Music (or the app you want) plays plain PCM. Check its row while a song plays:

  ```sh
  sudo waydroid shell dumpsys media.audio_flinger > /tmp/af.txt
  grep -n -A6 "Type     Id Active Client" /tmp/af.txt | head -60
  ```

  Its row must show `Flags 0x000`, a PCM `Format` (`00000005` is float) and sit under a `MIXER` thread. If it shows offload, MMAP or a compressed format, the patch cannot reach it and the build is not worth doing.
- The app's UID. On current Android `dumpsys package` prints `appId`, and for user 0 the UID equals the `appId`:

  ```sh
  sudo waydroid shell cmd package list packages -U | grep -i apple
  ```

## 1. Host setup (once)

```sh
df -h ~                      # need >= 250 GB free
swapon --show                # CachyOS usually already has zram

# 48G swapfile (on btrfs use the second line instead of the first)
sudo fallocate -l 48G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon -p 10 /swapfile
# sudo btrfs filesystem mkswapfile --size 48g /swapfile && sudo swapon -p 10 /swapfile

# 16G lz4 zram, higher priority than the swapfile
sudo modprobe zram; dev=$(sudo zramctl --find --size 16G --algorithm lz4); sudo mkswap $dev; sudo swapon -p 100 $dev

sudo pacman -S --needed git git-lfs python rsync unzip zip curl
mkdir -p ~/bin && curl -o ~/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod +x ~/bin/repo
export PATH=~/bin:$PATH
git config --global user.name  "<your name>"
git config --global user.email "<your noreply address>"     # git am needs an identity
```

On a machine with 32 GB of RAM, a smaller swapfile (about 16 GB) is enough.

## 2. Init and sync

This takes hours. The download is the long part.

```sh
mkdir ~/los24 && cd ~/los24
repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs --depth=1

# WayDroid-ATV manifests (this is what vendor/extra/manifest_scripts/generate-manifest.sh does;
# the script itself only exists after the first sync, so copy the XML directly)
git clone --depth=1 -b lineage-24.0 https://github.com/WayDroid-ATV/android_vendor_waydroid /tmp/vw
mkdir -p .repo/local_manifests
cp /tmp/vw/manifest_scripts/manifests-37/*.xml .repo/local_manifests/
ls .repo/local_manifests        # expect 00-remotes.xml 01-removes.xml 02-waydroid.xml

repo sync -c -j8 --no-tags --no-clone-bundle --optimized-fetch
```

If `repo sync` stops with `remove-project … non-existent project`, delete that line from `.repo/local_manifests/01-removes.xml` and run it again.

The local manifests replace `frameworks/av`, `hardware/interfaces`, `frameworks/base` and others with the WayDroid-ATV forks on `lineage-24.0`. That is where the patched `AudioFlinger.cpp` comes from.

## 3. Patches

Waydroid base patches first, then the AudioFlinger patch.

```sh
cd ~/los24
source build/envsetup.sh
vendor/extra/waydroid-patches/apply-patches.sh      # base patches for SDK 37
```

Expect one conflict, in `packages/apps/SetupWizard` (a patch that skips the Bluetooth pairing screen). The script records conflicts and carries on, so the other patches are applied and the script exits non-zero. This does not affect the audio build. Check that nothing is left half-applied:

```sh
git -C packages/apps/SetupWizard status | head -3     # should be clean
```

None of the base patches touch `frameworks/av` or audio, so the AudioFlinger patch applies on top:

```sh
git -C frameworks/av am ~/Apps/fork-waydroid-hires/patches/frameworks_av/0001-audioflinger-direct-output-for-uid.patch
git -C frameworks/av log --oneline -1     # should show "audioflinger: request a DIRECT output for one app UID"
```

If `am` says `Stray .git/rebase-apply directory found`, an earlier `am` left state behind:

```sh
git -C frameworks/av log --oneline -3         # already applied? then skip the patch step
git -C frameworks/av am --abort
# if it says there is nothing to abort but the error persists:
d=$(git -C frameworks/av rev-parse --git-dir); echo "$d"      # must be inside .repo/projects/
rm -rf "$d/rebase-apply"
```

Then run the `am` command again. If it fails for another reason, the usual causes are a missing git identity (see section 1) or a context mismatch if your `AudioFlinger.cpp` has moved. As a last resort, `git -C frameworks/av apply <patch>` applies the change without committing it.

## 4. Gate: confirm the tree analyzes on this machine

```sh
cd ~/los24
source build/envsetup.sh
lunch lineage_waydroid_x86_64_only-cp2a-userdebug
time m nothing
```

- `cp2a` is the release token from `vendor/lineage/vars/aosp_target_release`. Check it with `cat vendor/lineage/vars/aosp_target_release`.
- `lunch` needs the full target string. A bare `lunch` prints "No target specified".
- "Trying dependencies-only mode on a non-existing device tree?" is a routine message here.
- If the name is rejected, try `lineage_waydroid_x86_64-cp2a-userdebug` (the non-`_only` variant), or run `lunch --help`.
- In a second terminal, watch memory: `watch -n5 'free -h; swapon --show'`.

Pass: it ends with `#### build completed successfully`.

Fail: if it dies with "Killed" or an out-of-memory message, stop. A 16 GB host may not manage it even with swap. Use the 32 GB machine, or rent a VM (a Hetzner CCX63 costs about EUR 1.37 per hour).

## 5. Build only audioserver

```sh
m audioserver -j8
f=$(find out/target/product -path '*system/bin/audioserver'); echo "$f"
strings "$f" | grep -E "persist.waydroid.direct_audio_uid|direct output for uid"    # both must appear
```

A compile error here is most likely in the patch, which has been checked for clean application but not compiled. Fix the line the compiler names in `frameworks/av/services/audioflinger/AudioFlinger.cpp` and re-run `m audioserver -j8`. Then export the fixed change back into this folder:

```sh
git -C frameworks/av commit -a --amend --no-edit
git -C frameworks/av format-patch -1 --stdout > ~/Apps/fork-waydroid-hires/patches/frameworks_av/0001-audioflinger-direct-output-for-uid.patch
```

Optional sanity check, comparing the binary's dependencies with the installed one:

```sh
readelf -d "$f" | grep NEEDED
sudo waydroid shell sh -c 'ls -l /system/bin/audioserver'
```

## 6. Install and test

```sh
sudo waydroid session stop
# remove the unused shared-library overlay if you installed one earlier
sudo rm -f /var/lib/waydroid/overlay/system/lib64/libaudioflinger.so
sudo mkdir -p /var/lib/waydroid/overlay/system/bin
sudo install -m 755 -o root -g root "$f" /var/lib/waydroid/overlay/system/bin/audioserver
sudo systemctl restart waydroid-container
waydroid session start

# confirm the patched binary is the one running (inside `sudo waydroid shell`)
#   strings /system/bin/audioserver | grep "direct output for uid"

# the app's UID (see "Before you start")
waydroid prop set persist.waydroid.direct_audio_uid <appId>
sudo waydroid shell getprop persist.waydroid.direct_audio_uid     # should print it back
```

The patch reads the property for every new track, so changing it later needs no restart. Then play a hi-res track in the app and check:

```sh
sudo waydroid shell -- logcat -b crash -d                                   # should be empty
sudo waydroid shell -- logcat -d | grep "direct output for uid"             # shows the UID and rate (start a NEW track first)
sudo waydroid shell dumpsys media.audio_flinger | grep -A12 "type 1 (DIRECT)"   # a track on the DIRECT thread
pactl list sink-inputs | grep -iE "Sample Specification|media.name"         # expect the track's own rate, e.g. @ 96000Hz
```

What the results mean:

| Result | Meaning |
|---|---|
| DIRECT thread at the track's rate, and `pactl` shows that rate | Working. Android is no longer resampling that app. |
| `logcat` shows no "direct output" line | The property is not set, or its value does not match the UID in the track's `Client(pid/uid)` column. |
| Log line present but the track stays on the mixer | No DIRECT profile fits (for example a mono track, or a rate the XML lacks). The policy manager falls back to the mixer, which is the intended fallback. |
| audioserver crash-loops, or Waydroid does not boot | The built binary does not match the installed image. Roll back (below). |

PipeWire on the host can still resample if its `default.clock.allowed-rates` does not include the rate. Check it with `pw-top`.

### Verified result (2026-11-09, one Waydroid install)

With the patched `audioserver` overlaid and `persist.waydroid.direct_audio_uid` set to Apple Music's uid (10113):

- `logcat` showed `createTrack() direct output for uid 10113 format 0x5 rate 96000` for each new track.
- `dumpsys media.audio_flinger` listed a `type 1 (DIRECT)` thread (`AudioOut_35`) at 96000 Hz, `PCM_FLOAT`, `Standby: no`, carrying Apple Music's track. The mixer thread was in standby.
- 16-bit 44.1 kHz tracks opened DIRECT threads at 44100 Hz, 16-bit.
- PipeWire showed a `Android Playback @ 96000Hz` stream (running, F32) next to an idle `@ 192000Hz` stream. The idle one is the mixer's output, which stays at 192 kHz for every other app.

Seen but not investigated: each new track opens a new DIRECT thread, so gapless playback between tracks is not guaranteed. Android's volume slider may not change the DIRECT output's level (untested).

## Rollback

```sh
sudo rm /var/lib/waydroid/overlay/system/bin/audioserver
sudo waydroid session stop && sudo systemctl restart waydroid-container && waydroid session start
```

Removing the vendor XML overlay file as well restores the shipped 16-bit, up to 48 kHz audio.

If the overlaid binary cannot run against the installed image, the fallback is building matching `systemimage` and `vendorimage` from the same tree and installing them with `waydroid init -f`. That takes hours on a 16 GB host and is not covered here.

## Building on a second machine

Copy the whole tree, including the hidden `.repo`, and leave out `out/`:

```sh
rsync -aH --info=progress2 --exclude=/out ~/los24/ otherpc:~/los24/
```

- Use the same username and path (`~/los24`) on both machines.
- The destination must be a case-sensitive Linux filesystem (ext4, xfs or btrfs). HFS+, exFAT and NTFS do not work as the working tree. To carry the tree on such a drive, store a single archive on it (`tar --exclude=los24/out -cf /mnt/drive/los24.tar -C ~ los24`) and unpack it onto ext4/xfs/btrfs.
- On the second machine, run `repo sync -l` (it re-checks out from the local copy and downloads nothing), confirm `git -C frameworks/av log --oneline -1` shows the patch, then do sections 4 and 5.
- Copy the built `audioserver` binary back to the machine that runs Waydroid for section 6.
