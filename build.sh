#!/bin/bash
set -e

# If Flutter is not present in the environment (e.g. Cloudflare Pages runner), install it
if ! command -v flutter &> /dev/null; then
    echo "=== Installing Flutter SDK on Cloudflare Runner ==="
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 $HOME/flutter
    export PATH="$PATH:$HOME/flutter/bin"
    flutter --version
fi

# Run the standard web build
bash build_web.sh
