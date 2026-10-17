# Security review — 2026-10-17

Target: the current Radioform source, locally installed app and HAL driver, and the recent 32-filter / Fixed Spatial changes. This was a focused code review and regression sweep, not an independent audit or a guarantee of safety.

## Findings addressed in source

| Finding | Effect before fix | Change |
| --- | --- | --- |
| Invalid signed or oversized JSON filter type | Swift's `UInt32` conversion could trap and terminate the host before DSP validation | Check the enum range before conversion and validate all DSP parameters before returning a preset |
| Unbounded preset file reads | A huge file could exhaust memory; a FIFO could block the monitor; a symlink could redirect reads | Open with `O_NOFOLLOW`, `O_NONBLOCK`, `O_CLOEXEC`; inspect the opened inode; require a regular file owned by this user and not group/world writable; cap reads at 1 MiB even if it grows |
| Concurrent DSP updates and rendering | Control-thread preset/sample-rate changes could race with audio-thread filter state | Serialize changes; the audio thread tries the lock and emits a silent block if busy, without waiting; also check Swift input/output buffer sizes |
| Integer audio conversion and non-finite samples | Full-scale float-to-int32 conversion could overflow; NaN/infinity could reach integer casts or poison DSP state | Scale int32 in double precision and replace non-finite samples with silence on both ring read and write, including peer-injected samples |
| Temporary C-string pointer lifetime | Preset logging used a pointer returned from a scoped unsafe-bytes closure | Construct the Swift string inside the closure |

The driver/host shared protocol layout is unchanged. Spatial coefficients and EQ settings are unchanged by this sweep.

## Verification

- `tools/test_security.sh`: shared-header parity, AddressSanitizer/UndefinedBehaviorSanitizer bounds and corrupted-header tests, ACL and symlink checks, plus six adversarial shell/AppleScript path round trips. Privileged install commands are compiled in this test, never executed. Sanitizer findings now fail the test immediately.
- Additional ring regression tests: full-scale and out-of-range audio, NaN and infinities in all five sample formats, and invalid floating samples injected directly into shared memory. Passed with AddressSanitizer/UndefinedBehaviorSanitizer.
- `tools/test_features.sh`: passed, including preset file restrictions, invalid parameters/types/counts, 1/10/12/32-filter round trips, editor behavior, output selection, configuration tests, DSP suite, and concurrent DSP updates/rendering.
- All 41 DSP cases passed in a separate Debug build with AddressSanitizer and UndefinedBehaviorSanitizer.
- A separate ThreadSanitizer-instrumented Swift/C++ build ran 2,000 render blocks concurrently with 2,000 preset updates and periodic sample-rate resets without a race report. This exercises the DSP wrapper, not every host/UI concurrency path.
- Release app, host and universal HAL driver builds succeeded. `git diff --check` passed.
- Installed app and driver passed `codesign --verify --deep --strict`. These are local ad-hoc signatures, not Developer ID signing/notarization or proof of trusted provenance.
- Two live control/audio IPC files checked were regular, single-link files owned by the current user with no group/other mode permissions. All seven installed driver entries were root-owned and not group/world writable. Tests verified the ACL grants only the intended CoreAudio service principal.

## Updater

The source lockfile and installed framework both report Sparkle 2.10.0. The feed uses HTTPS and configures an Ed25519 public key; automatic installation is disabled. The minimum dependency requirement now also specifies 2.10.0, so older versions are not accepted by a fresh resolution. The published Sparkle advisories were checked against this version; this is not a complete supply-chain audit.

References: [Sparkle security advisories](https://github.com/sparkle-project/Sparkle/security/advisories), [releases](https://github.com/sparkle-project/Sparkle/releases), [root-cache cleanup advisory, fixed in 2.9.6](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-4v99-qgq9-6pxp), [update path advisory](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-3x7w-j75x-ppq5).

## Remaining limits

The file-backed audio IPC trusts the active console account. A malicious process running as that same account can tamper with or truncate its own shared files and disrupt audio; validated layout snapshots do not eliminate file-truncation/mapping hazards. This sweep does not redesign that transport, audit all vendored libASPL/Sparkle code, or prove every driver/host concurrency path safe. It does not establish safe listening volume for every EQ and input.

## Build and installation status

The fixes are in the workspace and verified builds. A patched app with the new host and bundled driver is staged at `/private/tmp/radioform-security-build-xmmu8l2b/Radioform.app`; its complete bundle signature verifies. The existing app executable/UI is preserved because app executable source did not change.

**The running installed app/host and system HAL driver have not been replaced during this sweep.** Installing the patched host and driver is still required to apply these fixes to the running system. Updating the system HAL driver requires administrator authorization and a CoreAudio restart, which interrupts audio.

Logs: `/private/tmp/radioform-sweep-features.log`, `/private/tmp/radioform-sweep-sanitizers.log`, `/private/tmp/radioform-sweep-host-build.log`, `/private/tmp/radioform-sweep-driver-build.log`, `/private/tmp/radioform-sweep-app-build.log`. The separate sanitizer build/run script is `/private/tmp/radioform-sweep-so4y9yy6/run-sanitizers.sh`.
