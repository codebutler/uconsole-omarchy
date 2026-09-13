# Contributor guidance

## Project

`codebutler/uconsole-omarchy` builds a universal Arch Linux ARM / Omarchy raw
image for the ClockworkPi uConsole with Raspberry Pi CM4 or CM5. It derives from
`fabiiw05/uconsole-archlinux`; preserve that project's history and license.
Read `README.md`, `MAINTAINING.md`, and `HANDHELD.md` for the current architecture,
hardware verification checklist, and user-facing integrations.

Use English for code comments and logs. Japanese documentation currently links
to the authoritative English documentation rather than maintaining a separate
technical specification.

## Build and tests

```sh
./scripts/build-in-docker.sh   # macOS: native arm64 Docker image build
sudo ./build.sh               # Linux: privileged image assembly
./tests/test-static.sh        # Bash 4+, Python 3; ShellCheck/Lua when available
python3 tests/test-platform.py
sudo ./scripts/verify-image.sh out/uconsole-omarchy-universal-YYYYMMDD.img
```

The Docker volume keeps case-sensitive kernel/module files and loop-backed disk
images off macOS APFS. `out/`, `cache/`, `work/`, `kernel/`, `logs/`, and `tmp/`
are local artifacts, not source. Do not commit credentials, private signing keys,
wireless profiles, Tailscale state, SSH host keys, or device diagnostics.

## Invariants

- Use ALARM's package-managed 4K `linux-rpi` kernel, not file injection or the
  removed kernel tarball updater. `uconsole-modules-linux-rpi` depends on the
  exact kernel package version; do not bypass that lock or add kernel IgnorePkg.
- Extra modules go in `/usr/lib/modules/<release>/updates/uconsole`. Kernel
  updates require matching modules, depmod, and an updated Plymouth initramfs.
- On-device preparation downloads signature-verified kernel/headers, builds
  modules unprivileged, and signs with a device-local root-only key. Fresh images
  never contain that secret. Failed preparation must leave the old kernel intact.
- Preserve both CM4/CM5 boot sections, DTBs, overlays, and panel variants. Boot
  and root use PARTUUIDs. Expansion supports SD/eMMC/NVMe but must never format
  or migrate to a secondary drive automatically.
- Keep chroot bind mounts private so cleanup cannot unmount host filesystems.
- Install upstream Omarchy from its official aarch64 repository. Prefer native
  configuration/plugins over recreating shell features. The bounded adaptations
  in `uconsole-configure-omarchy-*` preserve backups and reject unknown layouts;
  test them against upstream changes rather than silently accepting drift.
- Optional AIO rails remain off until explicitly configured by the user.
- Battery/CPU/PMIC telemetry is not a safety certification or a cell-temperature
  measurement. Do not increase charging limits or bypass protection for tests.
- Physical tests and structural image checks are distinct. Do not call CM5,
  eMMC, upgrade-kit hardware, or a newly built artifact verified without testing
  that exact configuration. Do not reboot or flash a live device implicitly.

For read-only recovery logs from an offline card:

```sh
sudo ./scripts/collect-logs.sh /dev/sdX
```

Resolve the exact device before any mount, flash, or partition operation.
