
This project aims to build a web environment for working on projects in various workspaces with AI.

It currently uses the following components:
- `wede`: a lightweight vscode like web app
- `pipane`: a web UI for the Pi coding agent. Uses pi in rpc mode. Allows switching between workspaces. Running multiple sessions.
- `pi-webui`: a web UI for the pi coding agent. Uses the pi sdk with createAgentSessionRuntime.

The following vendored code is available to consult for reference:
- `vendored/pi`: The pi coding agent code and associated libraries
