#!/usr/bin/env bash
# Starts the Procedural World dedicated server (Linux). Settings: server.cfg beside this
# script (made on first start). Any flags are passed on, e.g. --port=24600 --name="My World".
cd "$(dirname "$0")"
exec ./ProceduralWorldServer.x86_64 --headless -- --server "$@"
