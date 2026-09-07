#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLBOX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="${POPNPLAY_PROJECT_ROOT:-"$TOOLBOX_ROOT/../PopAndPlayRealTimeWebGamev5"}"

BATTLE_ENV="$SCRIPT_DIR/.env.battle-test"
FRONTEND_ENV="$PROJECT_ROOT/frontend/.env"

battle_auth_finish() {
  return "$1" 2>/dev/null || exit "$1"
}

if [ ! -f "$BATTLE_ENV" ]; then
  echo "❌ Credentials Battle introuvables : $BATTLE_ENV"
  battle_auth_finish 1
fi

if [ ! -f "$FRONTEND_ENV" ]; then
  echo "❌ Configuration frontend PopNPlay introuvable : $FRONTEND_ENV"
  battle_auth_finish 1
fi

set -a
source "$BATTLE_ENV"
set +a

SUPABASE_URL=$(grep '^VITE_SUPABASE_URL=' "$FRONTEND_ENV" | head -1 | cut -d= -f2- | tr -d '"')
SUPABASE_ANON_KEY=$(grep '^VITE_SUPABASE_ANON_KEY=' "$FRONTEND_ENV" | head -1 | cut -d= -f2- | tr -d '"')

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "❌ Configuration Supabase introuvable dans $FRONTEND_ENV"
  battle_auth_finish 1
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

# Découvre automatiquement TEACHER_A_EMAIL, TEACHER_B_EMAIL, etc.
TEACHER_ALIASES=$(
  grep -E '^TEACHER_[A-Za-z0-9]+_EMAIL=' "$BATTLE_ENV" \
    | sed -E 's/^TEACHER_([A-Za-z0-9]+)_EMAIL=.*/\1/' \
    | sort -u
)

if [ -z "$TEACHER_ALIASES" ]; then
  echo "❌ Aucun compte TEACHER_<ALIAS>_EMAIL trouvé dans $BATTLE_ENV"
  battle_auth_finish 1
fi

echo "🔐 Authentification des comptes Battle DEV..."
echo

tokens_ok=0
auth_errors=0
incomplete=0

for alias in $TEACHER_ALIASES; do
  email_var="TEACHER_${alias}_EMAIL"
  password_var="TEACHER_${alias}_PASSWORD"
  token_var="TOKEN_${alias}"

  email="${!email_var:-}"
  password="${!password_var:-}"

  unset "$token_var"

  if [ -z "$email" ] || [ -z "$password" ]; then
    echo "⚠️  Teacher $alias — ${email:-email manquant} — credentials incomplets"
    incomplete=$((incomplete + 1))
    continue
  fi

  token=$(get_token "$email" "$password")
  if [ $? -ne 0 ] || [ -z "$token" ]; then
    echo "❌ Teacher $alias — $email — échec authentification"
    auth_errors=$((auth_errors + 1))
    continue
  fi

  printf -v "$token_var" '%s' "$token"
  export "$token_var"

  echo "✅ Teacher $alias — $email — TOKEN_$alias OK"
  tokens_ok=$((tokens_ok + 1))
done

echo
echo "Tokens disponibles      : $tokens_ok"
echo "Comptes en erreur       : $auth_errors"
echo "Credentials incomplets  : $incomplete"

if [ "$tokens_ok" -eq 0 ]; then
  battle_auth_finish 1
fi

battle_auth_finish 0
