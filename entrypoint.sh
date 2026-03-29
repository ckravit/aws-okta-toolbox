#!/bin/bash
# Ensure AWS config dir exists (it's mounted from host)
mkdir -p /root/.aws

exec "$@"
