#!/usr/bin/env bash

API="${POPNPLAY_API_URL:-http://localhost:3001}"
ACTIVITY_ID="${ACTIVITY_ID:-fdd39fe9-d0de-4b13-aa2a-220f89944174}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLBOX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BATTLE_ENV="$SCRIPT_DIR/.env.battle-test"

fail() {
  echo "❌ $1"
  return 1 2>/dev/null || exit 1
}

if [[ -z "${DEV_DB_URL:-}" ]]; then
  fail "DEV_DB_URL absent. Lance d'abord : source init_config.sh"
fi

if [[ ! -f "$BATTLE_ENV" ]]; then
  fail "Credentials Battle introuvables : $BATTLE_ENV"
fi

command -v psql >/dev/null 2>&1 || fail "psql introuvable."
command -v curl >/dev/null 2>&1 || fail "curl introuvable."
command -v jq >/dev/null 2>&1 || fail "jq introuvable."

set -a
source "$BATTLE_ENV"
set +a

find_alias_for_email() {
  local target_email="$1"
  local var alias configured_email configured_email_lc target_email_lc

  target_email_lc="$(printf '%s' "$target_email" | tr '[:upper:]' '[:lower:]')"

  while IFS= read -r var; do
    alias="${var#TEACHER_}"
    alias="${alias%_EMAIL}"

    configured_email="${!var:-}"
    configured_email_lc="$(printf '%s' "$configured_email" | tr '[:upper:]' '[:lower:]')"

    if [[ "$configured_email_lc" == "$target_email_lc" ]]; then
      echo "$alias"
      return 0
    fi
  done < <(
    grep -E '^TEACHER_[A-Z0-9]+_EMAIL=' "$BATTLE_ENV" \
      | cut -d= -f1 \
      | sort -u
  )

  return 1
}
CLASSES=()

while IFS='|' read -r db_class_id db_class_name db_school_name db_teacher_id db_teacher_email; do
  db_teacher_alias="$(find_alias_for_email "$db_teacher_email" || true)"
  CLASSES+=("$db_class_id|$db_class_name|$db_school_name|$db_teacher_id|$db_teacher_email|$db_teacher_alias")
done < <(
  psql "$DEV_DB_URL" -X --no-psqlrc -At -F '|' -c "
    SELECT
      c.id,
      c.name,
      COALESCE(NULLIF(s.name, ''), '—'),
      c.owner_id,
      COALESCE(u.email, '')
    FROM public.classes c
    LEFT JOIN public.schools s ON s.id = c.school_id
    LEFT JOIN auth.users u ON u.id = c.owner_id
    WHERE c.status = 'active'
    ORDER BY c.name;
  "
)

if [[ ${#CLASSES[@]} -lt 2 ]]; then
  fail "Il faut au moins 2 classes actives en DEV."
fi

echo
echo "⚔️ Classes Battle DEV"
echo

eligible_indexes=()

i=1
for row in "${CLASSES[@]}"; do
  IFS='|' read -r display_class_id display_class_name display_school_name display_teacher_id display_teacher_email display_teacher_alias <<< "$row"

  if [[ -n "$display_teacher_alias" ]]; then
    auth="✅ Teacher $display_teacher_alias"
    eligible_indexes+=("$i")
  else
    auth="⚠️ credentials absents"
  fi

  printf "%d) %s\n" "$i" "$display_class_name"
  echo "   École   : $display_school_name"
  echo "   Teacher : $display_teacher_email"
  echo "   Auth    : $auth"
  echo

  i=$((i + 1))
done

if [[ ${#eligible_indexes[@]} -lt 2 ]]; then
  fail "Moins de 2 classes disposent de credentials Battle."
fi

# Mode rapide par défaut : Teacher A vs Teacher B, HOST = A.
default_a=""
default_b=""

i=1
for row in "${CLASSES[@]}"; do
  IFS='|' read -r _ _ _ _ _ configured_alias <<< "$row"

  [[ "$configured_alias" == "A" ]] && default_a="$i"
  [[ "$configured_alias" == "B" ]] && default_b="$i"

  i=$((i + 1))
done

if [[ -n "$default_a" && -n "$default_b" ]]; then
  echo "Sélectionne 2 classes."
  echo "Entrée = Teacher A vs Teacher B (HOST A)"
else
  default_a="${eligible_indexes[0]}"
  default_b="${eligible_indexes[1]}"
  echo "Sélectionne 2 classes."
  echo "Entrée = classes $default_a et $default_b"
fi

read -r -p "Classes [ex: 1 3] : " selection

quick_mode=false

if [[ -z "$selection" ]]; then
  selected_a="$default_a"
  selected_b="$default_b"

  if [[ -n "$default_a" && -n "$default_b" ]]; then
    quick_mode=true
  fi
else
  read -r selected_a selected_b extra <<< "$selection"

  if [[ -n "${extra:-}" || -z "${selected_a:-}" || -z "${selected_b:-}" ]]; then
    fail "Sélection invalide : indique exactement 2 numéros."
  fi
fi

case "$selected_a" in
  ''|*[!0-9]*) fail "Numéro de classe invalide : $selected_a" ;;
esac

case "$selected_b" in
  ''|*[!0-9]*) fail "Numéro de classe invalide : $selected_b" ;;
esac

if (( selected_a < 1 || selected_a > ${#CLASSES[@]} ||
      selected_b < 1 || selected_b > ${#CLASSES[@]} )); then
  fail "Numéro de classe hors liste."
fi

if [[ "$selected_a" == "$selected_b" ]]; then
  fail "Choisis deux classes différentes."
fi

ROW_1="${CLASSES[$((selected_a - 1))]}"
ROW_2="${CLASSES[$((selected_b - 1))]}"

IFS='|' read -r CLASS_1_ID CLASS_1_NAME SCHOOL_1 TEACHER_1_ID TEACHER_1_EMAIL ALIAS_1 <<< "$ROW_1"
IFS='|' read -r CLASS_2_ID CLASS_2_NAME SCHOOL_2 TEACHER_2_ID TEACHER_2_EMAIL ALIAS_2 <<< "$ROW_2"

if [[ -z "$ALIAS_1" ]]; then
  echo "❌ $CLASS_1_NAME ($TEACHER_1_EMAIL) n'a pas de credentials dans battle/.env.battle-test. Aucune Battle créée."
  return 1 2>/dev/null || exit 1
fi

if [[ -z "$ALIAS_2" ]]; then
  echo "❌ $CLASS_2_NAME ($TEACHER_2_EMAIL) n'a pas de credentials dans battle/.env.battle-test. Aucune Battle créée."
  return 1 2>/dev/null || exit 1
fi

TOKEN_VAR_1="TOKEN_${ALIAS_1}"
TOKEN_VAR_2="TOKEN_${ALIAS_2}"

TOKEN_1="${!TOKEN_VAR_1:-}"
TOKEN_2="${!TOKEN_VAR_2:-}"

if [[ -z "$TOKEN_1" || -z "$TOKEN_2" ]]; then
  echo
  echo "❌ Tokens Battle absents."
  echo "   Lance d'abord : source battle/battle-test-auth.sh"
  echo
  echo "   Attendus : $TOKEN_VAR_1 et $TOKEN_VAR_2"
  return 1 2>/dev/null || exit 1
fi

if [[ "$quick_mode" == true && "$ALIAS_1" == "A" ]]; then
  host_choice=1
elif [[ "$quick_mode" == true && "$ALIAS_2" == "A" ]]; then
  host_choice=2
else
  echo
  echo "Host de la Battle :"
  echo "1) $CLASS_1_NAME — Teacher $ALIAS_1"
  echo "2) $CLASS_2_NAME — Teacher $ALIAS_2"
  read -r -p "Host [1] : " host_choice
  host_choice="${host_choice:-1}"
fi

case "$host_choice" in
  1)
    HOST_CLASS_ID="$CLASS_1_ID"
    HOST_CLASS_NAME="$CLASS_1_NAME"
    HOST_TEACHER_ID="$TEACHER_1_ID"
    HOST_ALIAS="$ALIAS_1"
    HOST_TOKEN="$TOKEN_1"

    GUEST_CLASS_ID="$CLASS_2_ID"
    GUEST_CLASS_NAME="$CLASS_2_NAME"
    GUEST_TEACHER_ID="$TEACHER_2_ID"
    GUEST_ALIAS="$ALIAS_2"
    GUEST_TOKEN="$TOKEN_2"
    ;;
  2)
    HOST_CLASS_ID="$CLASS_2_ID"
    HOST_CLASS_NAME="$CLASS_2_NAME"
    HOST_TEACHER_ID="$TEACHER_2_ID"
    HOST_ALIAS="$ALIAS_2"
    HOST_TOKEN="$TOKEN_2"

    GUEST_CLASS_ID="$CLASS_1_ID"
    GUEST_CLASS_NAME="$CLASS_1_NAME"
    GUEST_TEACHER_ID="$TEACHER_1_ID"
    GUEST_ALIAS="$ALIAS_1"
    GUEST_TOKEN="$TOKEN_1"
    ;;
  *)
    fail "Host invalide."
    ;;
esac

echo
echo "============================================================"
echo "⚔️  CONFIGURATION BATTLE DEV"
echo "============================================================"
echo "HOST  : $HOST_CLASS_NAME — Teacher $HOST_ALIAS"
echo "GUEST : $GUEST_CLASS_NAME — Teacher $GUEST_ALIAS"
echo "ACTIVITY_ID=$ACTIVITY_ID"
echo "============================================================"
echo

echo "=== 1. CREATE BATTLE ==="

BATTLE_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles" \
  -H "Authorization: Bearer $HOST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"activityId\":\"$ACTIVITY_ID\",
    \"name\":\"Battle DEV diagnostic $(date +%H:%M:%S)\"
  }")

BATTLE_ID=$(echo "$BATTLE_JSON" | jq -r '.id // empty')
BATTLE_CODE=$(echo "$BATTLE_JSON" | jq -r '.battleCode // empty')

if [[ -z "$BATTLE_ID" ]]; then
  echo "❌ Création Battle impossible :"
  echo "$BATTLE_JSON" | jq . 2>/dev/null || echo "$BATTLE_JSON"
  return 1 2>/dev/null || exit 1
fi

echo "✅ Battle créée : $BATTLE_ID"

echo
echo "=== 2. INVITE TEACHER $GUEST_ALIAS ==="

INVITATION_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles/$BATTLE_ID/invitations" \
  -H "Authorization: Bearer $HOST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"invitedTeacherId\":\"$GUEST_TEACHER_ID\"}")

INVITATION_ID=$(echo "$INVITATION_JSON" | jq -r '.id // empty')

if [[ -z "$INVITATION_ID" ]]; then
  echo "❌ Invitation impossible :"
  echo "$INVITATION_JSON" | jq . 2>/dev/null || echo "$INVITATION_JSON"
  return 1 2>/dev/null || exit 1
fi

echo "✅ Invitation créée : $INVITATION_ID"

echo
echo "=== 3. ACCEPT INVITATION ==="

ACCEPT_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battle-invitations/$INVITATION_ID/accept" \
  -H "Authorization: Bearer $GUEST_TOKEN" \
  -H "Content-Type: application/json")

ACCEPT_ERROR=$(echo "$ACCEPT_JSON" | jq -r '.message // empty' 2>/dev/null)

if [[ -n "$ACCEPT_ERROR" ]]; then
  echo "❌ Acceptation impossible :"
  echo "$ACCEPT_JSON" | jq . 2>/dev/null || echo "$ACCEPT_JSON"
  return 1 2>/dev/null || exit 1
fi

echo "✅ Invitation acceptée"

echo
echo "=== 4. ADD HOST CLASS ==="

HOST_PARTICIPANT_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles/$BATTLE_ID/participants" \
  -H "Authorization: Bearer $HOST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"classId\":\"$HOST_CLASS_ID\"}")

HOST_PARTICIPANT_ID=$(echo "$HOST_PARTICIPANT_JSON" | jq -r '.id // empty')
HOST_JOIN_CODE=$(echo "$HOST_PARTICIPANT_JSON" | jq -r '.studentJoinCode // empty')

if [[ -z "$HOST_PARTICIPANT_ID" || -z "$HOST_JOIN_CODE" ]]; then
  echo "❌ Ajout classe HOST impossible :"
  echo "$HOST_PARTICIPANT_JSON" | jq . 2>/dev/null || echo "$HOST_PARTICIPANT_JSON"
  return 1 2>/dev/null || exit 1
fi

echo "✅ $HOST_CLASS_NAME ajoutée"

echo
echo "=== 5. ADD GUEST CLASS ==="

GUEST_PARTICIPANT_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles/$BATTLE_ID/participants" \
  -H "Authorization: Bearer $GUEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"classId\":\"$GUEST_CLASS_ID\"}")

GUEST_PARTICIPANT_ID=$(echo "$GUEST_PARTICIPANT_JSON" | jq -r '.id // empty')
GUEST_JOIN_CODE=$(echo "$GUEST_PARTICIPANT_JSON" | jq -r '.studentJoinCode // empty')

if [[ -z "$GUEST_PARTICIPANT_ID" || -z "$GUEST_JOIN_CODE" ]]; then
  echo "❌ Ajout classe GUEST impossible :"
  echo "$GUEST_PARTICIPANT_JSON" | jq . 2>/dev/null || echo "$GUEST_PARTICIPANT_JSON"
  return 1 2>/dev/null || exit 1
fi

echo "✅ $GUEST_CLASS_NAME ajoutée"

echo
echo "============================================================"
echo "⚔️  BATTLE DEV PRÊTE"
echo "============================================================"
echo "BATTLE_ID=$BATTLE_ID"
echo "BATTLE_CODE=$BATTLE_CODE"
echo
echo "HOST — $HOST_CLASS_NAME (Teacher $HOST_ALIAS)"
echo "  PARTICIPANT_ID=$HOST_PARTICIPANT_ID"
echo "  JOIN_CODE=$HOST_JOIN_CODE"
echo "  http://localhost:5173/battle/student?code=$HOST_JOIN_CODE"
echo
echo "GUEST — $GUEST_CLASS_NAME (Teacher $GUEST_ALIAS)"
echo "  PARTICIPANT_ID=$GUEST_PARTICIPANT_ID"
echo "  JOIN_CODE=$GUEST_JOIN_CODE"
echo "  http://localhost:5173/battle/student?code=$GUEST_JOIN_CODE"
echo "============================================================"
