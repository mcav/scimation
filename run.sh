#!/usr/bin/env bash

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
# Start 'em up


mkdir -p ~/.processing
cat > ~/.processing/preferences.txt << EOF
run.options=
run.options.memory=true
run.options.memory.maximum=512
run.options.memory.initial=128
EOF

echo "memory set."
processing-java --sketch=$SCRIPTPATH --run