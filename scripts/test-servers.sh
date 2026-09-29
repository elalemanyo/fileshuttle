#!/usr/bin/env bash
# Starts throwaway SFTP (port 2222) and FTP (port 2121) servers for integration tests.
# User: foo / pass. Stop with: docker stop fs-sftp fs-ftp
set -euo pipefail
docker run -d --rm --name fs-sftp -p 2222:22 atmoz/sftp foo:pass:::upload
docker run -d --rm --name fs-ftp -p 2121:21 -p 21000-21010:21000-21010 \
  -e USERS="foo|pass" -e ADDRESS=127.0.0.1 -e MIN_PORT=21000 -e MAX_PORT=21010 \
  delfer/alpine-ftp-server
echo "Run: (cd Packages/ShuttleKit && SHUTTLE_INTEGRATION=1 swift test)"
