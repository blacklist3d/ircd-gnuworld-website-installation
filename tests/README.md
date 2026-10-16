This directory contains helper files used by the CI workflow to build a test Docker image and run the repository's installer script inside that container.

Files:
- Dockerfile: Builds an Ubuntu-based image with required packages and a mock systemctl so the installer can run without systemd.

Notes:
- The GitHub Actions workflow (.github/workflows/docker-test.yml) builds this image and runs the installer using --network host so it can reach the Postgres service provided by the Actions runner.
- Logs from the installer run are uploaded as an artifact named "installer-logs".