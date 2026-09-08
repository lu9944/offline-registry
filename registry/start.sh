#!/bin/sh
set -e
nginx
exec verdaccio --config /opt/verdaccio/config.yaml --listen 0.0.0.0:4873
