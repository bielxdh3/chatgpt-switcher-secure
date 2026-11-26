# Local Work recovery on Windows

This is a version-specific, unofficial workaround for the packaged-resource copy failure described in upstream Codex issues #49582 and #55440. It does not modify WindowsApps, weaken Windows encryption policy, or change workspace authorization.

From the checkout in Windows PowerShell 5.1:

    .\Repair-LocalWork.ps1 -Prepare
    .\Repair-LocalWork.ps1 -Launch

Before Launch, exit the original ChatGPT from its tray menu. Leave the isolated profiles running if desired. The launcher refuses to start while an unrecognized main ChatGPT process is present. It preserves the user's configured CODEX_HOME and does not set a profile data-directory override. It supplies the verified resource mirror only in the new child process environment. Ordinary launches do not receive the override.

The preparation step reads the signed Store installation's bundled plugins and stages byte-identical files under the private profile root, in a directory keyed by package version. It rejects reparse points, unexpected entries and hash mismatches. Each launch verifies the mirror against the installed version. The mirror is local data, never committed. If a future package update changes the resource tree, prepare again; do not reuse old files or modify a rejected mirror to bypass verification.

## Evidence on 2026-11-25

- Original desktop PID 20832 repeatedly failed before executor registration, while copying the codex-app-tools manifest. The destination directory accepted writes. The source was readable but marked Encrypted. Both Node copy and .NET File.Copy failed, including when a byte-identical destination already existed. Win32 error 6000 (0x80071770); Node UNKNOWN/-4094.
- Reading and writing bytes and the documented CopyFileEx decrypted-destination option succeeded with identical SHA-256. A synthetic EFS encryption test succeeded and generated one valid personal EFS certificate; the packaged-file copy still failed. No encryption policy was changed. The synthetic files were removed; the personal certificate was left intact.
- The installed package 26.1120.6357.0 contains the bundled-resource path override. Upstream reports of the same issue describe successful use of a verified resource mirror (https://github.com/openai/codex/issues/49582 and https://github.com/openai/codex/issues/55440).
- Real preparation: 314 plugin files, 17,350,305 source bytes, verified against the installed package by SHA-256.
- Tests: RED helper absent; GREEN 7/7 mirror and process-environment tests, plus 27/27 existing regressions.
- The authenticated original-app relaunch and end-to-end Dot task remain pending. A matching resource mirror is not proof that an executor is connected, and this workaround is not an official product fix.
