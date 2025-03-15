#!/bin/sh
# Copyright 2013 The Chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
set -e
DIR="$( cd "$( dirname "$0" )" && pwd )"
if [ "$(uname -s)" = "Darwin" ]; then
  if [ "$(whoami)" = "root" ]; then
    TARGET_DIR="/Library/Application Support/Mozilla/NativeMessagingHosts"
  else
    TARGET_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
  fi
else
  if [ "$(whoami)" = "root" ]; then
    TARGET_DIR="/usr/lib/mozilla/native-messaging-hosts"
  else
    TARGET_DIR="$HOME/.mozilla/native-messaging-hosts"
  fi
fi
HOST_NAME=com.a9t9.kantu.file_access
HOST_EXECUTABLE=kantu-file-access-host

# Create directory to store native messaging host.
mkdir -p "$TARGET_DIR"
# Copy native messaging host manifest.
cp "$DIR/$HOST_NAME.firefox.json" "$TARGET_DIR/$HOST_NAME.json"

# Update host path in the manifest.
HOST_PATH=$DIR/$HOST_EXECUTABLE
ESCAPED_HOST_PATH=${HOST_PATH////\\/}
sed -i -e "s/HOST_PATH/$ESCAPED_HOST_PATH/" "$TARGET_DIR/$HOST_NAME.json"

# Set permissions for the manifest so that all users can read it.
chmod o+r "$TARGET_DIR/$HOST_NAME.json"
echo "Native messaging host $HOST_NAME for FIREFOX has been installed."