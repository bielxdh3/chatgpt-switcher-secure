# Orca status plugin

A narrowly scoped local desktop MCP test package. The server exposes one read-only status tool, accepts no command or path arguments, and runs the fixed installed Orca CLI with a ten-second timeout and an environment allowlist. It returns only status booleans and a bounded state label, not raw CLI output or identifiers. No listener, credentials, firewall changes, privilege elevation, or automatic agent launches.

Installation requires the official local marketplace and user approval in the desktop plugin UI. Local marketplace support in Codex does not by itself demonstrate availability to Dots. If the product does not allow the plugin in the Dot, stop; do not change sandbox or workspace requirements to make it work.

Sources: https://developers.openai.com/plugins/build/plugins and https://developers.openai.com/plugins/deploy/desktop-only.

Validation: run `python -B -m unittest discover -s integrations/orca-status/tests -v` from the repository root.

On 2026-11-26, initial tests failed before the server existed; all seven tests then passed. A live stdio session successfully negotiated MCP 2025-11-25, listed one tool, and returned `ok=true`, `app_running=true`, `runtime_state=ready`, `reachable=true`, `connected=true` against Orca 1.4.277. The official `codex plugin marketplace add` command registered this marketplace for probe-one only. Installation/approval in the desktop plugin interface and the Dot invocation remain pending.

To try the plugin, select the Orca Local Diagnostics marketplace in the Probe 1 desktop Plugins Directory and review/install Orca Status. If the marketplace is not visible, refresh or restart only that profile. Test with the Dot only after installation and explicit authorization. To remove the marketplace from that profile, use `codex plugin marketplace remove orca-local-diagnostics` with its CODEX_HOME. No broader workspace publication is needed for the initial test.
