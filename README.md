# XAOS Runtime

Public, pinned runtime artifacts used by the XAOS Android client.

The Android APK intentionally does not embed the Linux/Node/Pi payload. The app downloads a versioned artifact on first Pi use, verifies its exact size and SHA-256, extracts it transactionally, and only then activates it.

## runtime-v1

- Architecture: `arm64`
- Base: Debian bookworm-slim
- Node: 22.23.2 runtime (builder pinned to Node 22 bookworm-slim)
- Pi coding agent: 0.85.1
- XAOS Pi extension: Android Tool Bridge only
- Artifact: `xaos-pi-runtime-arm64-v1.tar.gz`
- SHA-256: `700435f1e57b92b1221706f9161410a85aa93f8d916c0cf649515125b7ee012e`
- Bytes: `98609969`

The release archive retains Node/Debian license notices and includes the Pi MIT license. Android-side PRoot is distributed by the XAOS APK separately and is not part of this artifact.
