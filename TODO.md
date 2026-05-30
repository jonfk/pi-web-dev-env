# Root

- rename pipane-docker to the new pi-web-dev-env

# Wede

- Clear wede lint errors
- Add a dockerfile for reproducible builds in wede
- Add link to pipane
- Add markdown preview view

# pipane

- Investigate implementing pipane with pi AgentRuntime instead of rpc mode.
- Add link to wede

# pi-webui

- Add `@` file handler support
- Remove `PI_WEBUI_CWD_ALLOW_ANY` and `ALLOW_ANY_CWD` and any of the behaviour that attempts to validat paths for cwd
- add status or notification when a version newer than the current pi version is available

## Better steering/followup support

Currently the send button becomes an interrupt button and enter on the input field is treated as interrupt when the assistant is streaming output. 
I would like to make this behaviour more similar to the TUI. Inputting something when the assistant is streaming should do a steer or follow up. 
We could keep the interrupt button but not trigger it on enter on the input field. Also we could add a keybind for interrupting. I am thinking pressing Esc twice.

## Better steering/followup UI support

The TUI currently shows a queued message for the steer or followup prompt while the assistant is still streaming and until it is actually used.
The webui should do the same.
This could also add support for editing the queued followup or steer prompt.

## No cwd state. picker fallback

Start pi-webui without an agent runtime when no persisted `lastCwd` or valid session cwd exists.

- Add an explicit “no cwd selected” server/client state.
- Disable agent commands until a cwd is selected.
- Let the user pick/add a cwd from the UI.
- Create the runtime only after cwd selection.
- Persist the selected cwd as `lastCwd`.
- Remove the `process.cwd()` startup fallback once this flow exists.
