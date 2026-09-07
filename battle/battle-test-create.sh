#!/usr/bin/env bash

API="http://localhost:3001"

ACTIVITY_ID="fdd39fe9-d0de-4b13-aa2a-220f89944174"
TEACHER_B_ID="bcea1a43-231b-400f-8a3d-115353e60657"
CLASS_A_ID="6d9e87ca-4c2c-4123-a47f-cc8ddd329006"
CLASS_B_ID="50d835c9-ec98-4e54-990c-09567a1a6069"

if [[ -z "${TOKEN_A:-}" || -z "${TOKEN_B:-}" ]]; then
  echo "❌ TOKEN_A / TOKEN_B absents."
  echo "Lance d'abord :"
  echo "  . toolbox/battle-test-auth.sh"
  return 1 2>/dev/null || exit 1
fi

echo "⚔️ Création Battle DEV..."

echo
echo "=== 1. CREATE BATTLE ==="

BATTLE_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles" \
  -H "Authorization: Bearer $TOKEN_A" \
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
echo "=== 2. INVITE TEACHER B ==="

INVITATION_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles/$BATTLE_ID/invitations" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"invitedTeacherId\":\"$TEACHER_B_ID\"}")

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
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Type: application/json")

echo "✅ Invitation acceptée"

echo
echo "=== 4. ADD CLASS A ==="

PARTICIPANT_A_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles/$BATTLE_ID/participants" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"classId\":\"$CLASS_A_ID\"}")

PARTICIPANT_A_ID=$(echo "$PARTICIPANT_A_JSON" | jq -r '.id // empty')
JOIN_CODE_A=$(echo "$PARTICIPANT_A_JSON" | jq -r '.studentJoinCode // empty')

if [[ -z "$PARTICIPANT_A_ID" || -z "$JOIN_CODE_A" ]]; then
  echo "❌ Ajout classe A impossible :"
  echo "$PARTICIPANT_A_JSON" | jq . 2>/dev/null || echo "$PARTICIPANT_A_JSON"
  return 1 2>/dev/null || exit 1
fi

echo "✅ Classe A ajoutée"

echo
echo "=== 5. ADD CLASS B ==="

PARTICIPANT_B_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles/$BATTLE_ID/participants" \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Type: application/json" \
  -d "{\"classId\":\"$CLASS_B_ID\"}")

PARTICIPANT_B_ID=$(echo "$PARTICIPANT_B_JSON" | jq -r '.id // empty')
JOIN_CODE_B=$(echo "$PARTICIPANT_B_JSON" | jq -r '.studentJoinCode // empty')

if [[ -z "$PARTICIPANT_B_ID" || -z "$JOIN_CODE_B" ]]; then
  echo "❌ Ajout classe B impossible :"
  echo "$PARTICIPANT_B_JSON" | jq . 2>/dev/null || echo "$PARTICIPANT_B_JSON"
  return 1 2>/dev/null || exit 1
fi

echo "✅ Classe B ajoutée"

echo
echo "============================================================"
echo "⚔️  BATTLE DEV PRÊTE"
echo "============================================================"
echo "BATTLE_ID=$BATTLE_ID"
echo "BATTLE_CODE=$BATTLE_CODE"
echo
echo "Classe A"
echo "  PARTICIPANT_A_ID=$PARTICIPANT_A_ID"
echo "  JOIN_CODE_A=$JOIN_CODE_A"
echo "  http://localhost:5173/battle/student?code=$JOIN_CODE_A"
echo
echo "Classe B"
echo "  PARTICIPANT_B_ID=$PARTICIPANT_B_ID"
echo "  JOIN_CODE_B=$JOIN_CODE_B"
echo "  http://localhost:5173/battle/student?code=$JOIN_CODE_B"
echo "============================================================"
