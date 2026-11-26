# Security model

## Scope

Upstream source: kociden/chatgpt-switcher, commit `497bc5516d1fc0795d9312b30103bc887b4bf759` (v1.2.0), MIT. This derivative keeps the separate Electron user-data and Codex-home launch mechanism, removes the GUI/tray/shortcut features, and replaces shared mutable account configuration with directory-backed profile IDs.

- Only the expected Microsoft Store package family is accepted, with Store signature kind and healthy package status. The selected executable must also have a valid Authenticode signature from OpenAI OpCo, LLC.
- No credential file access, copying, swapping, remote installation, publishing helper, execution-policy bypass, persistence or destructive profile deletion.
- Fixed data root on E:, canonical strict IDs, reserved-name rejection and reparse-point checks. Each created directory has a protected ACL allowing the current Windows user and SYSTEM only; existing incompatible ACLs are rejected rather than silently rewritten.
- A per-Windows-user global mutex serializes profile creation, listing and launch operations. No shared mutable JSON registry.
- Separate process environment; provider, Electron, Node and TLS key-log overrides are removed from the child environment, and only profile-specific Codex/Electron paths are set. Parent environment is unchanged.
- Diagnostics report package version, signature status and profile count, not raw process command lines or tokens.

## Limitations

Local profile separation is not a security boundary against another process running as the same Windows user, an administrator, SYSTEM or a compromised application. The filesystem checks are not an atomic defense against an adversary who can rename or modify the same directories concurrently. Use independent OS accounts and tighter agent permissions if a genuine trust boundary is required. The installed application, its account store, its updater and its remote service are outside this launcher audit. Direct process launch and profile-directory overrides are not a supported OpenAI API and may change. Do not use this launcher to bypass account, workspace, or service restrictions.

No runtime downloads or third-party binaries are distributed. Use the reviewed checkout and official application only.
