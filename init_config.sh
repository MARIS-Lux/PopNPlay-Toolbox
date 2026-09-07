#!/usr/bin/env bash

# PopNPlay Toolbox — initialisation de l'environnement local.
# Usage :
#   source /Users/steph/Documents/AI/PopNPlay-Toolbox/init_config.sh
# ou depuis la Toolbox :
#   source init_config.sh

TOOLBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POPNPLAY_PROJECT_ROOT="${POPNPLAY_PROJECT_ROOT:-"$TOOLBOX_ROOT/../PopAndPlayRealTimeWebGamev5"}"
TOOLBOX_ENV="$TOOLBOX_ROOT/.env.toolbox"

if [ ! -f "$TOOLBOX_ENV" ]; then
  echo "❌ Configuration Toolbox introuvable : $TOOLBOX_ENV"
  return 1 2>/dev/null || exit 1
fi

set -a
source "$TOOLBOX_ENV"
set +a

export TOOLBOX_ROOT
export POPNPLAY_PROJECT_ROOT
export DEV_DB_URL
export PROD_DB_URL

echo "🔧 PopNPlay Toolbox"
echo

if [ -d "$POPNPLAY_PROJECT_ROOT/.git" ]; then
  echo "✅ Projet       : $POPNPLAY_PROJECT_ROOT"
else
  echo "❌ Projet       : introuvable ($POPNPLAY_PROJECT_ROOT)"
fi

if [ -n "${DEV_DB_URL:-}" ]; then
  echo "✅ DEV_DB_URL   : configurée"
else
  echo "❌ DEV_DB_URL   : absente"
fi

if [ -n "${PROD_DB_URL:-}" ]; then
  echo "✅ PROD_DB_URL  : configurée"
else
  echo "⚠️  PROD_DB_URL  : absente"
fi

if command -v psql >/dev/null 2>&1; then
  echo "✅ psql         : disponible"
else
  echo "❌ psql         : introuvable"
fi

echo
echo "Toolbox prête."
