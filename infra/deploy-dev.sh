#!/usr/bin/env bash
# Deploy the latest omni-dev branch to the dev environment on this VPS.
# Invoked by the GitHub Actions workflow .github/workflows/deploy-dev.yml on
# every push to omni-dev, and runnable by hand for ad-hoc redeploys.
#
# Assumes the dev clone lives at /opt/chatwoot-dev and a populated .env.dev
# is present alongside docker-compose.dev.yaml.

set -euo pipefail

cd /opt/chatwoot-dev

echo "==> Fetching omni-dev"
git fetch origin omni-dev
git checkout omni-dev
git reset --hard origin/omni-dev

COMPOSE=(docker compose -p chatwoot-dev -f docker-compose.dev.yaml --env-file .env.dev)

echo "==> Building rails image"
"${COMPOSE[@]}" build rails

echo "==> Starting stack"
"${COMPOSE[@]}" up -d

echo "==> Running migrations"
"${COMPOSE[@]}" run --rm rails bundle exec rails db:chatwoot_prepare

echo "==> Pruning unused docker layers"
docker image prune -f
docker builder prune -af

echo "==> Done"
