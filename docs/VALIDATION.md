# Validation

## Automated, no account access

Run ` .\tests\Regression.ps1 ` in Windows PowerShell 5.1. The tests cover parser checks, removal of credential-sharing and remote-installer paths, profile ID traversal and reserved names, private ACLs, junction refusal, distinct profile directories, child process environment and exact process-argument matching, and parallel profile creation. The scratch directory is unique to the test run.

Run ` .\ChatGPT-Switcher.ps1 -Diagnose ` to verify the official installed package and signature without starting it.

## Authenticated integration gate (not yet executed)

1. Confirm the official installed app signature and record its version. Close no existing sessions automatically. Review source and hash.
2. With a non-sensitive authorized test account, add one fresh profile and launch it. Verify that the official app uses its profile directories and does not alter the default login. Inspect process and file activity without printing credentials.
3. Launch a second independent profile. Verify account identities and separate data paths; check unexpected process creation, network activity and changes outside the intended profile paths. Do not copy session tokens or share login data.
4. If successful, repeat for the third profile, then restart and verify persistence and simultaneous access.
5. Verify one harmless local Codex task and one benign Orca CLI task per authorized Dot, with separate task identifiers and worktrees. Verify that each Dot can address its intended local session without cross-account access.
6. Stop if any account, device connection, profile or task is mixed up. Do not approve Business use until this gate succeeds.

The regression suite does not establish that Dots, Codex Desktop or Orca support simultaneous connections. No test against live accounts is implied by passing static checks.

## Implementation evidence (2026-11-25)

- Upstream RED: 1 passed, 8 failed. Only the pure upstream path function was extracted from its AST; no upstream entrypoint was executed.
- Intermediate GREEN: 18 passed, 0 failed. An initial ACL test fixture used a cmdlet requiring an unavailable Windows privilege; the fixture was corrected to edit only the synthetic directory DACL via .NET.
- Additional RED: 21 passed, 2 failed (inherited Node/Electron overrides and quoted Windows argument variants).
- Final GREEN: 23 passed, 0 failed, Windows PowerShell 5.1, including parallel additions in independent jobs and launch-refusal tests with mocked process/package lookups.
- Read-only diagnosis: installed Store package 26.1120.6357.0; executable Authenticode Valid, OpenAI OpCo, LLC; zero registered production profiles. E: NTFS, healthy.
- Independent review: eight workers were requested but did not start; the implementation was self-reviewed. No real app instance, authentication, Dot or Orca integration was tested. The manual gate remains open.

## Follow-up validation (2026-11-25, secure.2)

- Per owner instruction, this phase used no subagents.
- Additional RED: 24 passed, 3 failed (embedded argument false match, writable process working directory, missing launch verification).
- GREEN: 27 passed, 0 failed, Windows PowerShell 5.1. The suite includes a real benign PowerShell child that verifies inherited profile paths and absence of the OpenAI API key, without accessing any account.
- Read-only inspection of the installed application's package confirmed that the current version uses the explicit Electron data-path environment variable to set its user-data path. No application files were modified.
- Unauthenticated smoke test on the installed, signed ChatGPT Desktop 26.1120.6357.0: created two new profiles, probe-one and probe-two, and started both while the original main process remained alive. Main process IDs at observation: original 23492, probe-one 26080, probe-two 31708. The two probe profiles had distinct process groups with zero overlapping PIDs, separate Electron and Codex directories, and four top-level Codex entries each. The status command observed the first profile and a second launch of the same profile was refused as already running.
- TCP connections were observed per matching process group (7 and 10 at one sample). This is a connection-count observation only, not a destination or traffic-content audit.
- The first probe's application diagnostics indicated absence of MSIX package identity and bundled-runtime fallback; update/restart preference registration failed. Dot/device registration may depend on this identity. Do not treat the process smoke test as proof of full desktop feature compatibility.
- No test-account login, token inspection, default profile content comparison, full network capture, or Dot/Orca communication was performed. The two blank probe profiles were left available for the owner's next test; the original application was not stopped.
