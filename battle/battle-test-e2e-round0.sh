#!/usr/bin/env bash

set -u

API="http://localhost:3001"
FRONTEND="http://localhost:5173"

fail() {
  echo
  echo "❌ E2E FAILED — $1"
  exit 1
}

echo
echo "============================================================"
echo "⚔️  BATTLE 1B.7.3d — E2E ROUND 0"
echo "============================================================"

echo
echo "[1] Vérification backend..."
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" "$API/" 2>/dev/null) || \
  fail "Backend inaccessible sur $API"

[[ "$HTTP_CODE" != "000" ]] || fail "Backend inaccessible sur $API"

echo "✅ Backend accessible (HTTP $HTTP_CODE)"

echo
echo "[2] Authentification Teachers..."
source toolbox/battle-test-auth.sh || fail "Authentification impossible"

echo
echo "[3] Création de la Battle..."
source toolbox/battle-test-create.sh || fail "Création Battle impossible"

[[ -n "${BATTLE_ID:-}" ]] || fail "BATTLE_ID absent"
[[ -n "${PARTICIPANT_A_ID:-}" ]] || fail "PARTICIPANT_A_ID absent"
[[ -n "${PARTICIPANT_B_ID:-}" ]] || fail "PARTICIPANT_B_ID absent"
[[ -n "${JOIN_CODE_A:-}" ]] || fail "JOIN_CODE_A absent"
[[ -n "${JOIN_CODE_B:-}" ]] || fail "JOIN_CODE_B absent"

echo
echo "------------------------------------------------------------"
echo "👤 ÉTAPE MANUELLE — connecter les élèves"
echo "------------------------------------------------------------"
echo
echo "Classe A :"
echo "$FRONTEND/battle/student?code=$JOIN_CODE_A"
echo
echo "Classe B :"
echo "$FRONTEND/battle/student?code=$JOIN_CODE_B"
echo
echo "Connecte au moins UN élève de chaque classe."
echo "Arrête-toi lorsque les deux élèves sont dans leur lobby Battle."
echo
read -r -p "👉 Appuie sur ENTER quand les 2 élèves sont connectés... "

echo
echo "✅ Pause manuelle terminée."
echo
echo "BATTLE_ID=$BATTLE_ID"
echo "PARTICIPANT_A_ID=$PARTICIPANT_A_ID"
echo "PARTICIPANT_B_ID=$PARTICIPANT_B_ID"
echo
echo "[4] Vérification état PRE-START..."

HQ_JSON=$(curl -sS \
  -H "Authorization: Bearer $TOKEN_A" \
  "$API/api/teacher/battles/$BATTLE_ID/hq") || fail "Lecture HQ impossible"

echo "$HQ_JSON" | jq -e '
  .battle.status == "PREPARING"
  and .readiness.activeParticipants == 2
  and .readiness.readyParticipants == 0
  and .readiness.allReady == false
' >/dev/null || {
  echo "$HQ_JSON" | jq .
  fail "État PRE-START inattendu"
}

echo "✅ PREPARING — 2 participants actifs — 0/2 READY"

echo
echo "[5] Passage READY Teacher A..."

READY_A_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles/$BATTLE_ID/ready" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json") || fail "READY Teacher A impossible"

echo "$READY_A_JSON" | jq -e \
  --arg participant "$PARTICIPANT_A_ID" \
  '.id == $participant and .status == "READY" and .readyAt != null' \
  >/dev/null || {
    echo "$READY_A_JSON" | jq .
    fail "Réponse READY Teacher A invalide"
  }

echo "✅ Teacher A READY"

echo
echo "[6] Passage READY Teacher B..."

READY_B_JSON=$(curl -sS -X POST \
  "$API/api/teacher/battles/$BATTLE_ID/ready" \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Type: application/json") || fail "READY Teacher B impossible"

echo "$READY_B_JSON" | jq -e \
  --arg participant "$PARTICIPANT_B_ID" \
  '.id == $participant and .status == "READY" and .readyAt != null' \
  >/dev/null || {
    echo "$READY_B_JSON" | jq .
    fail "Réponse READY Teacher B invalide"
  }

echo "✅ Teacher B READY"

echo
echo "[7] Vérification 2/2 READY..."

HQ_JSON=$(curl -sS \
  -H "Authorization: Bearer $TOKEN_A" \
  "$API/api/teacher/battles/$BATTLE_ID/hq") || fail "Lecture HQ impossible"

echo "$HQ_JSON" | jq -e \
  --arg pa "$PARTICIPANT_A_ID" \
  --arg pb "$PARTICIPANT_B_ID" '
    .battle.status == "PREPARING"
    and .readiness.activeParticipants == 2
    and .readiness.readyParticipants == 2
    and .readiness.allReady == true
    and ([.participants[] | select(.id == $pa and .status == "READY")] | length) == 1
    and ([.participants[] | select(.id == $pb and .status == "READY")] | length) == 1
  ' >/dev/null || {
    echo "$HQ_JSON" | jq .
    fail "Battle non prête pour START"
  }

echo "✅ Battle PREPARING — 2/2 READY — allReady=true"

echo
echo "------------------------------------------------------------"
echo "👀 CONTRÔLE MANUEL AVANT START"
echo "------------------------------------------------------------"
echo
echo "Vérifie que les DEUX élèves sont toujours dans leur lobby Battle."
echo
read -r -p "Les deux lobbies sont-ils corrects ? [y/N] " CONFIRM

case "$CONFIRM" in
  y|Y)
    echo "✅ Contrôle visuel PRE-START validé"
    ;;
  *)
    fail "Contrôle visuel PRE-START refusé"
    ;;
esac

echo
echo "------------------------------------------------------------"
echo "🚀 ÉTAPE MANUELLE — START"
echo "------------------------------------------------------------"
echo
echo "Sur l'écran Teacher A (HOST) :"
echo "  1. Clique sur « Démarrer la Battle »"
echo "  2. Observe immédiatement les DEUX écrans élèves"
echo
read -r -p "👉 Appuie sur ENTER juste après avoir cliqué START... "

echo
echo "------------------------------------------------------------"
echo "👀 CONTRÔLE COUNTDOWN / HANDOFF / ROUND 0"
echo "------------------------------------------------------------"
echo
echo "Vérifie sur les DEUX élèves :"
echo "  - countdown Battle visible"
echo "  - décompte correct"
echo "  - aucun second countdown"
echo "  - aucun écran « Resynchronisation... »"
echo "  - arrivée directe sur MatchUp"
echo "  - Round 0 jouable"
echo
read -r -p "Countdown + handoff + Round 0 corrects sur A ET B ? [y/N] " CONFIRM_HANDOFF

case "$CONFIRM_HANDOFF" in
  y|Y)
    echo "✅ Countdown / handoff / Round 0 validés visuellement"
    ;;
  *)
    fail "Countdown / handoff / Round 0 invalides"
    ;;
esac

echo
echo "------------------------------------------------------------"
echo "🎮 ACTIONS ÉLÈVES — ROUND 0"
echo "------------------------------------------------------------"
echo
echo "Pendant un round jouable :"
echo "  1. Effectue au moins UNE action avec l'élève de Classe A"
echo "  2. Effectue au moins UNE action avec l'élève de Classe B"
echo
echo "Peu importe ici que la réponse soit correcte ou incorrecte."
echo
read -r -p "👉 Appuie sur ENTER lorsque A ET B ont chacun joué... "

echo
echo "✅ Actions élèves A/B effectuées"

echo
echo "------------------------------------------------------------"
echo "🏁 FIN DU TEST VISUEL"
echo "------------------------------------------------------------"
echo
echo "Laisse maintenant MatchUp poursuivre normalement jusqu'à"
echo "l'écran final sur les deux élèves."
echo
read -r -p "Les deux jeux sont-ils arrivés normalement à leur fin ? [y/N] " CONFIRM_END

case "$CONFIRM_END" in
  y|Y)
    echo "✅ Cycle runtime complet validé visuellement"
    ;;
  *)
    fail "Fin de runtime incorrecte"
    ;;
esac

echo
echo "============================================================"
echo "🔎 VALIDATION AUTOMATIQUE DB / RUNTIME"
echo "============================================================"

if [[ -z "${DEV_DB_URL:-}" ]]; then
  [[ -f toolbox/.env.toolbox ]] || fail "toolbox/.env.toolbox introuvable"

  set -a
  source toolbox/.env.toolbox
  set +a
fi

[[ -n "${DEV_DB_URL:-}" ]] || fail "DEV_DB_URL absent"
command -v psql >/dev/null 2>&1 || fail "psql introuvable"

echo
echo "[DB1] Vérification des 2 runtimes..."

DB_RUNTIME=$(psql "$DEV_DB_URL" -X --no-psqlrc -At -F '|' -v ON_ERROR_STOP=1 \
  -v battle_id="$BATTLE_ID" \
  -v participant_a="$PARTICIPANT_A_ID" \
  -v participant_b="$PARTICIPANT_B_ID" <<'SQL'
SELECT
  COUNT(*) FILTER (
    WHERE bp.id IN (:'participant_a'::uuid, :'participant_b'::uuid)
  ),
  COUNT(DISTINCT bp.game_session_id) FILTER (
    WHERE bp.id IN (:'participant_a'::uuid, :'participant_b'::uuid)
      AND bp.game_session_id IS NOT NULL
  ),
  COUNT(*) FILTER (
    WHERE bp.id IN (:'participant_a'::uuid, :'participant_b'::uuid)
      AND gs.game_id = 'matchup_ws'
  ),
  COUNT(*) FILTER (
    WHERE bp.id IN (:'participant_a'::uuid, :'participant_b'::uuid)
      AND gs.completed_at IS NOT NULL
  ),
  COUNT(DISTINCT gs.total_rounds) FILTER (
    WHERE bp.id IN (:'participant_a'::uuid, :'participant_b'::uuid)
  )
FROM public.battle_participants bp
LEFT JOIN public.game_sessions gs
  ON gs.id = bp.game_session_id
WHERE bp.battle_id = :'battle_id'::uuid;
SQL
) || fail "Requête DB runtimes impossible"

IFS='|' read -r PARTICIPANT_COUNT SESSION_COUNT MATCHUP_COUNT COMPLETED_COUNT ROUNDCOUNT_VARIANTS <<< "$DB_RUNTIME"

[[ "$PARTICIPANT_COUNT" == "2" ]] || fail "DB: participants attendus=2, obtenu=$PARTICIPANT_COUNT"
[[ "$SESSION_COUNT" == "2" ]] || fail "DB: 2 game_sessions distinctes attendues, obtenu=$SESSION_COUNT"
[[ "$MATCHUP_COUNT" == "2" ]] || fail "DB: les 2 runtimes ne sont pas matchup_ws"
[[ "$COMPLETED_COUNT" == "2" ]] || fail "DB: les 2 game_sessions ne sont pas terminées"
[[ "$ROUNDCOUNT_VARIANTS" == "1" ]] || fail "DB: total_rounds différent entre A et B"

echo "✅ 2 participants → 2 sessions distinctes → matchup_ws → completed"

echo
echo "[DB2] Vérification de la persistance des réponses..."

DB_ANSWERS=$(psql "$DEV_DB_URL" -X --no-psqlrc -At -F '|' -v ON_ERROR_STOP=1 \
  -v battle_id="$BATTLE_ID" \
  -v participant_a="$PARTICIPANT_A_ID" \
  -v participant_b="$PARTICIPANT_B_ID" <<'SQL'
SELECT
  COUNT(*) FILTER (WHERE bp.id = :'participant_a'::uuid),
  COUNT(*) FILTER (WHERE bp.id = :'participant_b'::uuid),
  COUNT(*) FILTER (
    WHERE bp.id = :'participant_a'::uuid
      AND COALESCE((a.answer->>'attemptCount')::integer, 0) > 0
  ),
  COUNT(*) FILTER (
    WHERE bp.id = :'participant_b'::uuid
      AND COALESCE((a.answer->>'attemptCount')::integer, 0) > 0
  ),
  COUNT(DISTINCT a.round_index) FILTER (WHERE bp.id = :'participant_a'::uuid),
  COUNT(DISTINCT a.round_index) FILTER (WHERE bp.id = :'participant_b'::uuid)
FROM public.battle_participants bp
JOIN public.game_session_answers a
  ON a.session_id = bp.game_session_id
WHERE bp.battle_id = :'battle_id'::uuid
  AND bp.id IN (:'participant_a'::uuid, :'participant_b'::uuid);
SQL
) || fail "Requête DB réponses impossible"

IFS='|' read -r ANSWERS_A ANSWERS_B ACTIONS_A ACTIONS_B ROUNDS_A ROUNDS_B <<< "$DB_ANSWERS"

(( ANSWERS_A > 0 )) || fail "DB: aucune réponse persistée pour A"
(( ANSWERS_B > 0 )) || fail "DB: aucune réponse persistée pour B"
(( ACTIONS_A > 0 )) || fail "DB: aucune action réelle MatchUp persistée pour A"
(( ACTIONS_B > 0 )) || fail "DB: aucune action réelle MatchUp persistée pour B"
(( ROUNDS_A > 0 )) || fail "DB: aucun round persisté pour A"
(( ROUNDS_B > 0 )) || fail "DB: aucun round persisté pour B"

echo "✅ Réponses persistées A : $ANSWERS_A"
echo "✅ Réponses persistées B : $ANSWERS_B"
echo "✅ Actions réelles A..... : $ACTIONS_A"
echo "✅ Actions réelles B..... : $ACTIONS_B"
echo "✅ Rounds persistés A/B.. : $ROUNDS_A / $ROUNDS_B"

echo
echo "[DB3] Mesure de synchronisation des fins de runtime..."

END_DELTA_MS=$(psql "$DEV_DB_URL" -X --no-psqlrc -At -v ON_ERROR_STOP=1 \
  -v battle_id="$BATTLE_ID" \
  -v participant_a="$PARTICIPANT_A_ID" \
  -v participant_b="$PARTICIPANT_B_ID" <<'SQL'
SELECT ROUND(
  EXTRACT(EPOCH FROM (MAX(gs.completed_at) - MIN(gs.completed_at))) * 1000
)::bigint
FROM public.battle_participants bp
JOIN public.game_sessions gs
  ON gs.id = bp.game_session_id
WHERE bp.battle_id = :'battle_id'::uuid
  AND bp.id IN (:'participant_a'::uuid, :'participant_b'::uuid)
  AND gs.completed_at IS NOT NULL;
SQL
) || fail "Mesure synchronisation impossible"

[[ -n "$END_DELTA_MS" ]] || fail "Écart de fin des runtimes non calculable"

echo "ℹ️  Écart de fin des runtimes : ${END_DELTA_MS} ms"
echo "    (diagnostic uniquement — pas de seuil PASS/FAIL en 1B.7.3d)"

echo
echo "============================================================"
echo "⚔️  BATTLE 1B.7.3d — RÉSULTAT FINAL"
echo "============================================================"
echo "Participants A/B............. PASS"
echo "Ready 2/2.................... PASS"
echo "Countdown.................... PASS (visuel)"
echo "Handoff...................... PASS (visuel)"
echo "Round 0 jouable.............. PASS (visuel)"
echo "Runtimes A/B créés........... PASS (DB)"
echo "Sessions distinctes.......... PASS (DB)"
echo "Game matchup_ws A/B.......... PASS (DB)"
echo "Sessions terminées........... PASS (DB)"
echo "Réponses persistées A/B...... PASS (DB)"
echo "Actions réelles A/B.......... PASS (DB)"
echo "Rounds persistés A/B......... PASS (DB)"
echo "Écart fin runtimes............ ${END_DELTA_MS} ms (info)"
echo "------------------------------------------------------------"
echo "RÉSULTAT...................... ✅ PASS"
echo "============================================================"
echo
echo "BATTLE_ID=$BATTLE_ID"
