# Low-resource partial build and deployment of Waydroid audio libs (LineageOS 24.0 / Android 17)

Research method note: WebFetch was blocked in this session by a broken context-mode hook (NODE_TOO_OLD), so no page could be read in full. Every citation below comes from search-result summaries, not full pages. Treat exact wording and numbers as needing a check against the source. Items marked "general build-system knowledge" in Inferences have no source in this session and must be verified.

Modules involved (from /home/akamamara/Apps/fork-waydroid-hires/waydroid_high-res_audio_fix_and_apple_music_fix.md):
1. The Waydroid audio HAL (vendor side): adds 24-bit, 32-bit and FLOAT32 cases to the format switch and unlocks the sample rate. Source is `audio/audio_hw.c` in waydroid/android_hardware_waydroid, which ends up in the image as a vendor `.so`.
2. `/vendor/etc/audio_policy_configuration.xml`: a text config, no build needed.
3. AudioFlinger (system side, frameworks/av `libaudioflinger.so`): patched to force AUDIO_OUTPUT_FLAG_DIRECT for the Apple Music UID, which it reads from `/data/local/tmp/apple_music_uid.txt`.
The original author shipped these as `vendor/` and `system/` folders dropped into `/var/lib/waydroid/overlay/`, on Android 13 only.

## Q1: Minimal source checkout (repo flags, removing projects, disk size)

### Takeaway
`repo init --depth=1` (shallow) saves the most disk. Partial clone saves little and fetches blobs on demand. LineageOS officially asks for about 400 GB of free space for lineage-21 and later, but that covers a full checkout plus a full build output. A shallow checkout with a single-module build needs far less. I found no measured figure for LOS 22, 23 or 24.

### Cited Findings
- AOSP android-11 checkout benchmark: full clone about 105 GB, partial clone (`--partial-clone --clone-filter=blob:limit=10M`) about 98 GB, shallow clone (`--depth=1`) about 77 GB. The author's verdict: "Partial clone might work for you if you have fast network, but it does not seem to save much space." Shallow clones drop history, branches and tags. This is from 2021 (Android 11), and newer trees are larger. — [junsun.net, AOSP Repo Checkout Method and Size Comparison](https://junsun.net/wordpress/2021/01/android-aosp-repo-checkout-method-and-size-comparison/)
- Under a git partial clone, any blob needed later (at checkout or in later operations) is downloaded on demand. — [GitLab docs: partial clone](https://docs.Gitlab.com/ee/topics/git/partial_clone.html)
- LineageOS wiki storage guidance: about 200 GB for lineage-17.1, 300 GB for 18.1, 400 GB for lineage-21 and up. It also gives 16 GB RAM or more as the hardware guidance. — [LineageOS wiki build page (e.g. corvette)](https://wiki.lineageos.org/devices/corvette/build/)
- Waydroid's official build flow: `repo init` on a LineageOS branch, fetch the Waydroid local_manifests with `generate-manifest.sh` from android_vendor_waydroid, `repo sync`, `lunch lineage_waydroid_x86_64-userdebug`, then `make systemimage` and `make vendorimage`. Resyncing after `waydroid-generate-manifest` wipes local changes. From lineage-20.0 on, the output is already a raw image. — [Waydroid docs: Compile Waydroid LineageOS based images](https://docs.waydro.id/development/compile-waydroid-lineage-os-based-images)
- LineageOS 23 (Android 16) was released on 2025-10-11. 23.2 is based on Android 16 QPR2. One Fairphone user said 23.2 had no build instructions because it "requires many patches from gerrit" to be applied by hand. This suggests that early, not-yet-official branches such as 24.0 also need manual patching. — [OSNews](https://www.osnews.com/?p=143524); [Fairphone forum FP6 unofficial LOS 23](https://forum.fairphone.com/t/fp6-unofficial-lineageos-23/127048?page=6); [MisterZtr LineageOS_gsi releases](https://github.com/MisterZtr/LineageOS_gsi/releases)

### Inferences
- Recommended command, based on general repo knowledge plus the benchmark above: `repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs --depth=1 --no-clone-bundle`, then add the Waydroid local_manifests, then `repo sync -c --no-tags --no-clone-bundle --optimized-fetch -j8`. `-c` syncs only the current branch, and `--no-tags` skips tags.
- `<remove-project name="..."/>` in `.repo/local_manifests/*.xml` is a standard repo feature (general knowledge). In practice you can only remove projects that no Android.bp or Android.mk in the remaining tree references. Soong analyzes the whole tree, so a removed dependency makes analysis fail unless `ALLOW_MISSING_DEPENDENCIES=true` is set. Safe candidates to remove are other devices' kernel and device trees, prebuilt Chromium/WebView (large), and other-architecture prebuilts such as darwin. Remove them conservatively and iterate.
- Realistic estimate (not measured): a shallow LOS 22–24 checkout is roughly 90–130 GB of source. A full image build adds 150–250 GB. Building only a few modules adds a few tens of GB (mostly `out/soong` intermediates and ninja files). Plan for at least 200 GB free for a single-module workflow.

### Gaps
- No measured shallow-checkout size for LOS 22, 23 or 24, and no list of projects that can safely be removed for a Waydroid target.
- Could not read the lineage-24.0 android_vendor_waydroid tree (WebFetch blocked), so its manifest contents and whether a lineage-24.0 branch of android_hardware_waydroid exists are unconfirmed.

## Q2: Single-module builds and RAM on 16 GB

### Takeaway
On 16 GB RAM, Soong analysis is the bottleneck: it OOM-kills `soong_build` without extra swap or zram. `m <module>` saves compile time but not analysis time. Google now lists 64 GB RAM as the minimum. Community reports say 16 GB works with swap or zram and a lower `-j`.

### Cited Findings
- The current official AOSP requirements page (android16-release, updated around Aug 2025) gives 64 GB RAM as the minimum. Google's reference machine has 72 cores and 64 GB and does a full build in about 40 min. A 6-core, 64 GB machine takes about 6 h. — [source.android.com requirements](https://source.android.com/docs/setup/requirements?hl=ko) (English text paraphrased via search summary)
- An Android-building thread from Oct 2025 says the Android team still treats RAM as a major build-speed factor. — [Google Groups: AOSP build being so resource demanding](https://groups.google.com/g/android-building/c/SE4cjLQoc9E)
- A low-RAM ROM-building guide says 16 GB is workable. Builds fail when physical RAM fills, even if the zram limit is not reached. lz4 zram worked better than zstd in its tests. It recommends timing `m nothing` (Soong analysis only) to measure swap pressure, and found most build time went to swapping when swap was on SSD. — [dev.to merinorus: Building Android ROMs on limited RAM, zram vs zswap](https://dev.to/merinorus/building-android-roms-on-limited-ram-zram-vs-zswap-comparison-42jd)
- A `soong_build` process was "Killed" on a 16 GB machine. It was fixed by adding a swap file. The default `-j` is based on CPU cores, not memory, so lower `m -j#` on low-RAM machines. — [Google Groups: How to build AOSP with 8GB RAM](https://groups.google.com/g/android-building/c/5G2l5JR3jWE); [Google Groups: ninja error](https://groups.google.com/g/android-building/c/XRCPLcuSvwA)
- Exit status 137 (OOM kill): the advice was a smaller `-j`, more RAM, or swap. `-j16` still failed for that user, so `-j` alone does not fix analysis OOM. — [Khadas forum](https://forum.khadas.com/t/is-my-build-for-vim3-builds-fine/13226)
- Ninja pools or a lower `-j` are the tools for memory-heavy steps. — [ninja-build issue #1441](https://www.github.com/ninja-build/ninja/issues/1441)
- `ALLOW_MISSING_DEPENDENCIES=true` (older name `SOONG_ALLOW_MISSING_DEPENDENCIES`) turns missing-dependency errors into errors deferred until a module that depends on the missing piece is actually built. It is a tolerance setting, not a speed setting, and it can hide real problems. — [AOSP build commit: Enable missing dependency checks](https://android.googlesource.com/platform/build/+/de05f89%5E%21/); [OmniROM gerrit: Add SOONG_ALLOW_MISSING_DEPENDENCIES](https://gerrit.omnirom.org/plugins/gitiles/android_build/+/b6d813ce0ac661e4055fcbcd36eb259d521412f3%5E2); [AOSP: Delay platform availability error](https://android.googlesource.com/platform/build/+/b0f3a4d04c)
- `--skip-make` was removed. `--soong-only` skips the Kati (Make) stage. — [OmniROM gerrit: Remove --skip-make](https://gerrit.omnirom.org/plugins/gitiles/android_build_soong/+/88f469e9092a2446aae180bfce557a7211cb345b%5E%21)
- `mm` is the documented way to build the module in the current directory, as shown in the frameworks/av audioflinger tests README. — [AOSP frameworks/av audioflinger tests README](https://android.googlesource.com/platform/frameworks/av/+/ee169b81b834048e4bbc0b131615b324eb4a0ecc/services/audioflinger/tests/README)

### Inferences (general build-system knowledge, not sourced in this session; verify)
- `m <module>`, `mm` and `mmm <dir>` all still run full Soong analysis (bootstrap, parse every Android.bp, generate `out/soong/build.<product>.ninja`) plus Kati for Android.mk/product config. They differ only in which ninja targets they build. The first analysis on a recent tree commonly peaks at roughly 20–35 GB RSS, which is why 16 GB needs swap. Later runs reuse the ninja file if no .bp or .mk changed, so the cost is paid once per sync or config change.
- Recipe for 16 GB and a 7700F:
  1. zram of about 16–24 GB (lz4) via `zram-generator`. CachyOS ships zram by default; raise `zram-size`. Add a 32 GB NVMe swapfile with lower priority as a backstop.
  2. `export NINJA_ARGS="-j6"` or `m -j6 <module>`. Analysis is mostly single-process, so `-j` matters more for the compile and link phase. Clang compiles take about 0.5–1.5 GB per job.
  3. `export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache` and run `ccache -M 50G`. This helps on rebuilds after edits.
  4. Build the targets. For the HAL: `source build/envsetup.sh && lunch lineage_waydroid_x86_64-<release>-userdebug` (Android 15+ lunch takes a release config such as `bp1a`, `bp2a` or `trunk_staging`; check `lunch` output). Then `m audio.primary.waydroid` (check the exact module name in `hardware/waydroid/audio/Android.bp` or `.mk`) and `m libaudioflinger`.
  5. Outputs land in `out/target/product/waydroid_x86_64/vendor/lib64/hw/` and `.../system/lib64/`.
  6. Avoid `m` with no target (that builds droid), `m systemimage`, and doc or API targets (metalava, droiddoc). A module-only build normally doesn't pull these in. For `libaudioflinger` the transitive deps are only native libs.
- `SOONG_GEN_COMPDB=1` only generates `compile_commands.json` for IDEs and does not reduce RAM. `m nothing` is useful as a cheap first test of whether analysis survives on your RAM and swap setup.

### Gaps
- No source confirmed the exact current peak RSS of `soong_build` for Android 16 or 17 trees, or confirmed `--skip-soong-tests` as a current flag. Check `m help` and `build/soong/ui/build/config.go` in the checkout.
- No 2025–2026 first-hand report of a LOS 23 or 24 build on exactly 16 GB was found.

## Q3: Alternatives that avoid full-tree builds (out-of-tree NDK, cloud)

### Takeaway
The audio HAL most likely does not need the Android tree at all. An existing AUR package (`waydroid-apple-music`) builds a patched Waydroid audio HAL with the Android NDK and says it works "with any Waydroid image". AudioFlinger is different: it links many private platform libraries, so it realistically needs the full tree. Run that build on a large rented VM for a few hours, or on crave.io.

### Cited Findings
- AUR `waydroid-apple-music` (maintainer kanya-approve, first submitted 2026-09-01, 0 votes): "bit-perfect Apple Music on Waydroid: patched audio HAL, container properties, and app settings. Works with any Waydroid image; ships neither the image nor the app." Upstream is https://github.com/kanya-approve/android_hardware_waydroid-hires. Its makedepends include `android-ndk`, and its optional dependency `pipewire-audio` provides sample-rate switching. Sources include `99-waydroid-hires.conf`. It is new and unvetted, but it is direct evidence that an NDK-only, out-of-tree HAL build is workable. — [AUR waydroid-apple-music](https://aur.archlinux.org/packages/waydroid-apple-music)
- The Waydroid HAL source is `audio/audio_hw.c` in waydroid/android_hardware_waydroid. It reads the `waydroid.pulse_runtime_path` property, sets PULSE_RUNTIME_PATH, and opens a "pulse" ALSA device, so it outputs to the host's PulseAudio or PipeWire-pulse. A CachyOS user reports that PipeWire does not follow the track's sample rate and keeps the best format (S24_3LE). — [CachyOS forum: BIT Perfect Audio on Waydroid](https://discuss.cachyos.org/t/bit-perfect-audio-on-waydroid-using-bit-perfect-audio-from-waydroid/11294); mirror at [Garuda forum](https://forum.garudalinux.org/t/bit-perfect-audio-on-waydroid-using-bit-perfect-audio-from-waydroid/44934)
- crave.io gives free build servers to ROM builders. Self-signup is disabled; you request a "ROM builders" account from the homepage. It replaced Cirrus CI's free ROM-builder service, which ended around Nov 2023. It supports custom commands and Docker images and lets you enter build storage without starting a build. Community wikis mention a 6-hour timeout. For ROMs not in `crave clone list` there is an advanced workflow, but it is "not recommended" and "known to be troublesome". The community tool crave_aosp_builder drives crave from GitHub Actions and needs a foss.crave.io account. — [shipuguidesandlearn blog (Dec 2025)](https://shipuguidesandlearn.blogspot.com/2025/12/building-custom-android-roms-without.html); [fossontop crave intro](https://fossontop-aosp.pages.dev/crave/getting-started/introduction); [gitea Gtajisan/crave_aosp_builder](https://gitea.com/Gtajisan/crave_aosp_builder); [opendroid wiki](https://edf60947.opendroid-web.pages.dev/wiki)
- GitHub-hosted runners: public runners have about 25–29 GB free disk according to one source (an older community answer says under 20 GB). Cleanup actions (`jlumbroso/free-disk-space`, `insightsengineering/disk-space-reclaimer`) free up to about 31 GB in about 3 min. `easimon/maximize-build-space` merges the disks via LVM and can resize swap. Larger runners have more disk, but the sources gave no specs or prices. — [dzombak (Sep 2024)](https://www.dzombak.com/blog/2024/09/freeing-disk-space-on-github-actions-runners/); [disk-space-reclaimer](https://github.com/insightsengineering/disk-space-reclaimer); [maximize-build-space](https://github.com/oslook/maximize-build-space); [GitHub community discussion 26351](https://github.com/orgs/community/discussions/26351); [Porter KB](https://kb.porter.run/articles/6068105326-how-do-i-resolve-no-space-left-on-device-error-during-github-builds)
- Hetzner CCX63 (48 dedicated AMD vCPU, 192 GB RAM, 960 GB NVMe, billed hourly with a monthly cap): about €1.37/h after the June 2026 price increase (€853.49/mo). Before the increase it was about €0.60/h (€374.49/mo). Third-party price sites disagree, so check hetzner.com. — [bitdoze Hetzner precios 2026](https://www.bitdoze.com/es/hetzner-cloud-precios-2026/); [privatedevops: Hetzner June 2026 price increase](https://privatedevops.com/news/hetzner-june-2026-cloud-price-increase-what-to-do); [sparecores CCX63](https://sparecores.com/server/hcloud/ccx63); [Hetzner cloud](https://www.hetzner.com/cloud/general-purpose)

### Inferences
- HAL via NDK: the Waydroid HAL is a legacy `audio_hw_device` module (`HAL_MODULE_INFO_SYM`) loaded by the stock `android.hardware.audio.service` or AIDL shim. It needs only `<hardware/audio.h>`, `<system/audio.h>` (headers from AOSP `hardware/libhardware` and `system/media/audio`, which you can copy or sparse-clone) and runtime libs `liblog`, `libcutils`, plus the ALSA or tinyalsa or pulse libs the HAL already links. `libcutils` is not in the NDK, so either link it against a stub or `.so` pulled from the running image (`/vendor/lib64` or `/system/lib64` via `waydroid shell` or the mounted image), or replace the property calls with `__system_property_get` from libc (NDK-public). The AUR PKGBUILD is the concrete template to copy. Target `x86_64-linux-android<API>` with the NDK clang. Also check what Android 17's audio HAL service expects: if LOS 24 Waydroid moved to an AIDL audio HAL, the module interface differs. Read the lineage-24.0 vendor tree's device manifest.
- libaudioflinger is impractical out of tree because it depends on libaudioclient, libmedia*, binder AIDL-generated code and private headers. Options:
  - (a) Full-tree `m libaudioflinger` locally with zram plus swap, as in Q2. Expect a slow first analysis.
  - (b) A Hetzner CCX43/CCX53/CCX63 for a few hours. Sync (about 1 h with a shallow checkout) plus analysis plus a module build is likely 2–3 h, so roughly €3–5 on CCX63 at post-increase prices, plus about €0.0x/h for extra volume if the 960 GB is not enough. Delete the server afterwards. (This is an estimate.)
  - (c) crave.io, if an account is granted and LineageOS 24 is in its clone list.
  - (d) Free GitHub-hosted runners are not viable for an Android 17 tree: about 30 GB disk even after cleanup and about 7–16 GB RAM. They work only for the NDK HAL build.
- A smaller alternative to patching AudioFlinger: check whether the forced-DIRECT behavior can come from `audio_policy_configuration.xml` alone, by declaring a direct or hifi mixPort with `AUDIO_OUTPUT_FLAG_DIRECT` and FLOAT/24-bit profiles. The AUR package claims bit-perfect output with only "patched audio HAL, container properties, and app settings", with no framework patch mentioned. That suggests the system/AudioFlinger patch may be avoidable.

### Gaps
- Could not read the AUR PKGBUILD or the kanya-approve repo (WebFetch blocked), so the exact NDK build commands, linked libs and supported Android versions are unconfirmed.
- No sourced current specs or prices for GitHub larger runners, no Gitpod data, no crave.io quotas, and no crave.io measured build times.

## Q4: Deploying rebuilt libs into Waydroid without reflashing

### Takeaway
Files under `/var/lib/waydroid/overlay/` (mirroring `/system`) and `/var/lib/waydroid/overlay/vendor/` (mirroring `/vendor`) are layered over the images with overlayfs when `mount_overlays` is enabled in `waydroid.cfg`. Copy the rebuilt `.so` files there at the matching path and restart the container. The libs must match the exact image build (VNDK and symbol ABI), or the service fails to load them.

### Cited Findings
- The `mount_overlays` key sits in the `[waydroid]` section of `/var/lib/waydroid/waydroid.cfg`. Most new installs enable it automatically; if not, remove `/var/lib/waydroid` and run `waydroid init` again. — [aljustiet gist](https://gist.github.com/aljustiet/92ccbed4d0b1be9b97c30a673ee01c37)
- The mount logs show the system overlay as `lowerdir=/var/lib/waydroid/overlay:/var/lib/waydroid/rootfs, upperdir=/var/lib/waydroid/overlay_rw/system`, plus a matching vendor overlay with `/var/lib/waydroid/overlay/vendor` over the vendor image. A porter replaced `libhidlbase.so` by placing it in `/var/lib/waydroid/overlay/vendor/lib64/`, and `overlay/system/lib64/egl/libEGL.so` fixed EGL for them. Another user said a `system/lib64` overlay did not take effect for them. A case where a different partition's copy was loaded instead, and a missing-symbol failure, were both traced to a version mismatch. A Waydroid dev noted "you can't run newer vndk with older system". — [SailfishOS porters IRC log 2025-08-29](https://irclogs.sailfishos.org/logs/%23sailfishos-porters/2025/%23sailfishos-porters.2025-08-29.log.html)
- The original fix used exactly this method: `vendor/` and `system/` folders dropped into `/var/lib/waydroid/overlay/`. — /home/akamamara/Apps/fork-waydroid-hires/waydroid_high-res_audio_fix_and_apple_music_fix.md (local file)
- `overlay_rw` is also how manual overlayfs approaches keep the base image untouched. — [kirbylife alien-everywhere running.txt](https://git.kirbylife.dev/kirbylife/alien-everywhere/src/branch/main/running.txt)

### Inferences (verify)
- Deploy steps:
  ```
  sudo install -Dm644 out/.../vendor/lib64/hw/audio.primary.waydroid.so /var/lib/waydroid/overlay/vendor/lib64/hw/audio.primary.waydroid.so
  sudo install -Dm644 out/.../system/lib64/libaudioflinger.so /var/lib/waydroid/overlay/system/lib64/libaudioflinger.so
  sudo install -Dm644 audio_policy_configuration.xml /var/lib/waydroid/overlay/vendor/etc/audio_policy_configuration.xml
  waydroid session stop && sudo systemctl restart waydroid-container
  ```
  Then verify:
  ```
  sudo waydroid shell -- ls -l /vendor/lib64/hw/ /system/lib64/libaudioflinger.so
  sudo waydroid shell -- dumpsys media.audio_flinger   # check output threads: Format, Sample rate, Flags (DIRECT)
  sudo waydroid shell -- dumpsys media.audio_policy
  sudo waydroid shell -- logcat -b all | grep -iE 'audio|linker|avc'
  ```
- Note the path asymmetry: the system lowerdir is the overlay root itself. Whether `/system/...` maps to `overlay/system/...` (system-as-root rootfs layout) is the likely reason for the conflicting reports above. Confirm with `waydroid shell -- mount | grep overlay`.
- SELinux: Waydroid normally runs permissive or with SELinux off, so contexts on overlay files rarely matter. Check with `getenforce` in the shell.
- Linker namespaces and VNDK: a vendor HAL `.so` must link only VNDK or LL-NDK libs (it lives in the sphal or vendor namespace). A `.so` built out of tree that links a non-VNDK system lib will fail with `dlopen ... not accessible for the namespace`. AudioFlinger in `/system/lib64` must match the exact LOS 24 build of the image (same libaudioclient and AIDL versions), so build from the same manifest snapshot or tag as the installed image. The WayDroid-ATV release you run should identify it.
- Rollback: delete the files from the overlay and restart. Do not delete `overlay_rw` unless you mean to discard runtime changes.

### Gaps
- Could not confirm the current Waydroid docs page on overlays or its exact `/system` mapping rule.
- No source found on waydroid_script handling custom libs, or on community guides that build single modules for Waydroid. waydroid_script (casualsnek) is known for installing GApps, Magisk, libhoudini and libndk via the overlay, but this was not verified in this session.
