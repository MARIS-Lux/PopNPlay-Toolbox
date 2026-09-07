#!/usr/bin/env bash

BATTLE_ENV="toolbox/.env.battle-test"
FRONTEND_ENV="frontend/.env"

if [ ! -f "$BATTLE_ENV" ]; then
  echo "❌ $BATTLE_ENV introuvable"
  return 1 2>/dev/null || exit 1
fi

if [ ! -f "$FRONTEND_ENV" ]; then
  echo "❌ $FRONTEND_ENV introuvable"
  return 1 2>/dev/null || exit 1
fi

set -a
source "$BATTLE_ENV"
set +a

SUPABASE_URL=$(grep '^VITE_SUPABASE_URL=' "$FRONTEND_ENV" | head -1 | cut -d= -f2- | tr -d '"')
SUPABASE_ANON_KEY=$(grep '^VITE_SUPABASE_ANON_KEY=' "$FRONTEND_ENV" | head -1 | cut -d= -f2- | tr -d '"')

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "❌ Configuration Supabase introuvable dans $FRONTEND_ENV"
  return 1 2>/dev/null || exit 1
fi

get_token() {
  local email="$1"
  local password="$2"

  curl -sS \
    -X POST \
    "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    --data "$(printf '{"email":"%s","password":"%s"}' "$email" "$password")" \
  | python3 -c '
import sys, json

try:
    data = json.load(sys.stdin)
except Exception:
    print("AUTH_ERROR: réponse Supabase invalide", file=sys.stderr)
    sys.exit(1)

token = data.get("access_token")

if not token:
    msg = (
        data.get("msg")
        or data.get("message")
        or data.get("error_description")
        or str(data)
    )
    print("AUTH_ERROR: " + msg, file=sys.stderr)
    sys.exit(1)

sys.stdout.write(token)
'
}

echo "🔐 Authentification Teacher A..."
TOKEN_A=$(get_token "$TEACHER_A_EMAIL" "$TEACHER_A_PASSWORD") || {
  echo "❌ Échec authentification Teacher A"
  unset TOKEN_A TOKEN_B
  return 1 2>/dev/null || exit 1
}

echo "🔐 Authentification Teacher B..."
TOKEN_B=$(get_token "$TEACHER_B_EMAIL" "$TEACHER_B_PASSWORD") || {
  echo "❌ Échec authentification Teacher B"
  unset TOKEN_A TOKEN_B
  return 1 2>/dev/null || exit 1
}

export TOKEN_A
export TOKEN_B

echo "✅ TOKEN_A OK"
echo "✅ TOKEN_B OK"
