# Install Coordinator — agent notes

- **Repo:** `dev-centr/install-coordinator` (D; adoption path vs `dlang-supplemental` libs).
- **Binary:** `install-coordinator` (CLI + daemon); `install-coordinator-gui` (`dub --config=gui`).
- **Default UX:** `thinStub` — `submit` then exit; user commits at `http://127.0.0.1:17420/ui` or native GUI.
- **IPC:** Windows named pipe `\\.\pipe\dev-centr-install-coordinator`; HTTP JSON on port `17420` (`INSTALL_COORD_HTTP_PORT`).
- **State machine:** `installcoordinator/statemachine.d` — collecting → ready → queued → blocked/executing → terminal.
- **MSI lane:** `installcoordinator/msi_lane.d` — waits on `Global\_MSIExecute`, single-flight execute.
- **Session:** `--lock-elevation`, `--batch-terms`, `--scope=perMachine` via `session` command.
- **Related:** `dev-centr/easy-installer` (Ibex), `dev-centr/msi-generator`, UniGetUI/winget as external job sources.
