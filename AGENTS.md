# Install Coordinator — agent notes

- **Repo:** `dev-centr/install-coordinator` (Dev-Centr org — adoption over dlang-supplemental-only).
- **Binary:** `install-coordinator` (CLI + daemon + HTTP UI on port 17420).
- **Default UX:** thin stub (`submit` → exit); unified UI at `/ui` when daemon runs.
- **IPC:** named pipe `\\.\pipe\dev-centr-install-coordinator` (Windows) or Unix socket under data dir.
- **Data:** `%LOCALAPPDATA%\DevCentr\InstallCoordinator\` on Windows.
- **MSI:** internal lane + `Global\_MSIExecute` wait before `msiexec`.
- **Ibex:** sibling `easy-installer`; manifests can be emitted from installer projects later.
- **Presentation:** manifest field `presentation`: `thinStub` | `detachedCollect` | `embeddedQueue`.
