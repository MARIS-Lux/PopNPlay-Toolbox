#!/usr/bin/env bash
set -euo pipefail

TOOLBOX_ROOT="/Users/steph/Documents/AI/PopNPlay-Toolbox"
PROJECT_ROOT="/Users/steph/Documents/AI/PopAndPlayRealTimeWebGamev5"
BACKUP_ROOT="/Users/steph/Documents/AI/bck_env"

echo "============================================================"
echo " PopNPlay — Bolt apply + restauration environnement"
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. Import / apply du dernier ZIP Bolt
# ------------------------------------------------------------

echo "==> [1/6] Import du dernier ZIP Bolt..."

cd "$PROJECT_ROOT"
time "$TOOLBOX_ROOT/bolt/import-bolt.sh" --apply

# IMPORTANT:
# import-bolt.sh recrée le repo. Revenir explicitement dedans.
cd "$PROJECT_ROOT"

echo
echo "==> Repository recréé."


# ------------------------------------------------------------
# 2. Protections post-Bolt
# ------------------------------------------------------------

echo
echo "==> [2/6] Restauration des fichiers protégés..."

git restore frontend/package.json
git restore frontend/package-lock.json
git restore server/package.json
git restore server/package-lock.json

# Migration analytics : Bolt simplifie ce nom alors que Git suit
# volontairement le nom historique avec double timestamp / .sql.sql.
BAD_ANALYTICS_MIGRATION="supabase/migrations/20260718210006_sprint_3_2_1_identity_rattachement_analytics.sql"
GOOD_ANALYTICS_MIGRATION="supabase/migrations/20260718210006_20260718120000_sprint_3_2_1_identity_rattachement_analytics.sql.sql"

if [[ -f "$BAD_ANALYTICS_MIGRATION" ]]; then
  mv "$BAD_ANALYTICS_MIGRATION" "$GOOD_ANALYTICS_MIGRATION"
  echo "    ✓ Migration analytics remise sous son nom Git"
else
  echo "    - Migration analytics déjà correctement nommée"
fi

# Migration 1 : normalisation du nom
BAD_MIGRATION_1="supabase/migrations/20260830104628_20260830120000_add_battle_round_advancement_mode.sql.sql"
GOOD_MIGRATION_1="supabase/migrations/20260830104628_add_battle_round_advancement_mode.sql"

if [[ -f "$BAD_MIGRATION_1" ]]; then
  mv "$BAD_MIGRATION_1" "$GOOD_MIGRATION_1"
  echo "    ✓ Migration battle round advancement renommée"
else
  echo "    - Migration battle round advancement déjà correcte"
fi

# Migration 2 : normalisation du nom
BAD_MIGRATION_2="supabase/migrations/20260904213702_20260904_rollback_battle_start_rpc.sql.sql"
GOOD_MIGRATION_2="supabase/migrations/20260904213702_rollback_battle_start_rpc.sql"

if [[ -f "$BAD_MIGRATION_2" ]]; then
  mv "$BAD_MIGRATION_2" "$GOOD_MIGRATION_2"
  echo "    ✓ Migration rollback renommée"
else
  echo "    - Migration rollback déjà correctement nommée"
fi

# Toujours restaurer la version Git validée de cette migration.
# Elle contient notamment :
#   AND round_index = 0
git restore "$GOOD_MIGRATION_2"

echo "    ✓ Migration rollback restaurée depuis Git"


# ------------------------------------------------------------
# 3. Restauration environnement local
# ------------------------------------------------------------

echo
echo "==> [3/6] Restauration des fichiers locaux..."

cp "$BACKUP_ROOT/server/.env.staging" server/.env
cp "$BACKUP_ROOT/frontend/.env.staging" frontend/.env

cp "$BACKUP_ROOT"/frontend/.env.* frontend/
cp "$BACKUP_ROOT"/server/.env.* server/

echo "    ✓ Environnement local restauré"


# ------------------------------------------------------------
# 4. Installation des dépendances
# ------------------------------------------------------------

echo
echo "==> [4/6] Installation des dépendances..."

cd "$PROJECT_ROOT"
npm install

cd "$PROJECT_ROOT/shared"
npm install

cd "$PROJECT_ROOT/server"
npm install

cd "$PROJECT_ROOT/frontend"
npm install

cd "$PROJECT_ROOT"

echo "    ✓ Dépendances installées"


# ------------------------------------------------------------
# 5. Contrôles de sécurité
# ------------------------------------------------------------

echo
echo "==> [5/6] Contrôles post-apply..."

if grep -q '"@testing-library/jest-dom": "\^7' frontend/package.json; then
  echo "ERREUR: jest-dom 7.x détecté dans frontend/package.json"
  exit 1
fi

if grep -q '"history":' frontend/package.json; then
  echo "ERREUR: dépendance history détectée dans frontend/package.json"
  exit 1
fi

if find supabase/migrations -name '*.sql.sql' | grep -q .; then
  echo "ERREUR: migration *.sql.sql détectée :"
  find supabase/migrations -name '*.sql.sql'
  exit 1
fi

if ! grep -A5 -B5 "phase = 'PREPARED'" "$GOOD_MIGRATION_2" | grep -q 'round_index = 0'; then
  echo "ERREUR: protection round_index = 0 absente de la migration rollback"
  exit 1
fi

echo "    ✓ Contrôles OK"


# ------------------------------------------------------------
# 6. État Git final
# ------------------------------------------------------------

echo
echo "==> [6/6] État Git final"
echo

git status --short

echo
echo "============================================================"
echo " Bolt apply terminé."
echo " Repository : $PROJECT_ROOT"
echo "============================================================"
