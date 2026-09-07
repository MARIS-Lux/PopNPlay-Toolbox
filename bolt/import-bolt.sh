#!/opt/homebrew/bin/bash
set -Eeuo pipefail

# ============================================================
# PopNPlay - Bolt Import V5 SIMPLE
#
# Usage:
#   import-bolt.sh
#   import-bolt.sh --preview
#   import-bolt.sh --apply
#   import-bolt.sh --rollback
#
# PREVIEW:
#   - sélectionne le dernier project-bolt-*.zip
#   - décompresse
#   - affiche un diff informatif
#   - ne modifie rien
#
# APPLY:
#   - affiche le diff
#   - demande confirmation
#   - supprime l'ancien rollback éventuel
#   - MOVE du V5 actuel -> V5.rollback
#   - crée le nouveau V5 depuis le ZIP Bolt
#   - restaure depuis rollback :
#       .git/
#       tous les fichiers .env et .env.*
#
# ROLLBACK:
#   - supprime le nouveau V5
#   - remet V5.rollback -> V5
#
# Un seul rollback.
# Aucun git add / commit / push automatique.
# ============================================================


# ------------------------------------------------------------
# MODE
# ------------------------------------------------------------

MODE="preview"

case "${1:-}" in
  ""|--preview)
    MODE="preview"
    ;;
  --apply)
    MODE="apply"
    ;;
  --rollback)
    MODE="rollback"
    ;;
  -h|--help)
    echo "Usage: import-bolt.sh [--preview|--apply|--rollback]"
    exit 0
    ;;
  *)
    echo "Option inconnue : ${1}" >&2
    exit 1
    ;;
esac


die() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}


# ------------------------------------------------------------
# DEPENDANCES
# ------------------------------------------------------------

for cmd in git unzip rsync find mv rm mkdir cp mktemp; do

  command -v "$cmd" >/dev/null 2>&1 \
    || die "$cmd introuvable."

done


# ------------------------------------------------------------
# CHEMINS
# ------------------------------------------------------------

PROJECT_ROOT="$(
  git -C "$PWD" rev-parse --show-toplevel 2>/dev/null
)" || die "Lance le script depuis le repo PopNPlay."


PROJECT_PARENT="$(dirname "$PROJECT_ROOT")"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"


SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
)"


TOOLBOX_ROOT="$(
  cd "$SCRIPT_DIR/.." && pwd
)"


DOWNLOADS="$HOME/Downloads"

WORKDIR="$TOOLBOX_ROOT/.bolt-work-v5"

EXTRACT_DIR="$WORKDIR/extracted"

ROLLBACK_DIR="$PROJECT_PARENT/${PROJECT_NAME}.rollback"


mkdir -p "$WORKDIR"


# ------------------------------------------------------------
# TROUVER LE DERNIER ZIP BOLT
# ------------------------------------------------------------

find_latest_zip() {

  local latest

  latest="$(
    find "$DOWNLOADS" \
      -maxdepth 1 \
      -type f \
      -name 'project-bolt-*.zip' \
      -print0 |
    xargs -0 ls -1t 2>/dev/null |
    head -n 1 || true
  )"


  [[ -n "$latest" ]] \
    || die "Aucun project-bolt-*.zip trouvé dans $DOWNLOADS."


  printf '%s\n' "$latest"
}


# ------------------------------------------------------------
# EXTRACTION ZIP
# ------------------------------------------------------------

extract_zip() {

  local zip="$1"


  rm -rf "$EXTRACT_DIR"

  mkdir -p "$EXTRACT_DIR"


  unzip -qq \
    "$zip" \
    -d "$EXTRACT_DIR"


  # Format Bolt habituel :
  #
  # project/
  #   frontend/
  #   server/
  #   ...


  if [[ -d "$EXTRACT_DIR/project" ]]; then

    EXPORT_ROOT="$EXTRACT_DIR/project"

  else

    local dirs=()

    while IFS= read -r -d '' dir; do

      dirs+=("$dir")

    done < <(
      find "$EXTRACT_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -print0
    )


    if (( ${#dirs[@]} == 1 )); then

      EXPORT_ROOT="${dirs[0]}"

    else

      EXPORT_ROOT="$EXTRACT_DIR"

    fi

  fi


  [[ -d "$EXPORT_ROOT/frontend" ]] \
    || die "frontend/ absent du ZIP."


  [[ -d "$EXPORT_ROOT/server" ]] \
    || die "server/ absent du ZIP."
}


# ------------------------------------------------------------
# DIFF INFORMATIF
# ------------------------------------------------------------

show_diff() {

  echo
  echo "=============================================="
  echo " Différences Bolt -> Local"
  echo "=============================================="
  echo

  rsync \
    -r \
    -n \
    -c \
    --delete \
    --itemize-changes \
    --no-times \
    --no-perms \
    --no-owner \
    --no-group \
    --omit-dir-times \
    --exclude='.git/' \
    --exclude='.env' \
    --exclude='.env.*' \
    --exclude='**/.env' \
    --exclude='**/.env.*' \
    --exclude='node_modules/' \
    --exclude='**/node_modules/' \
    --exclude='dist/' \
    --exclude='**/dist/' \
    --exclude='build/' \
    --exclude='**/build/' \
    --exclude='coverage/' \
    --exclude='**/coverage/' \
    "$EXPORT_ROOT/" \
    "$PROJECT_ROOT/" \
  | grep -v '^\.f\.\.T\.\.\.\.' \
  || true

  echo
}


# ------------------------------------------------------------
# RESTAURER .GIT
# ------------------------------------------------------------

restore_git() {

  local old_git="$ROLLBACK_DIR/.git"
  local new_git="$PROJECT_ROOT/.git"


  [[ -d "$old_git" ]] \
    || die ".git absent du rollback."


  rm -rf "$new_git"


  cp -a \
    "$old_git" \
    "$new_git"


  echo "  ✓ .git/"
}


# ------------------------------------------------------------
# RESTAURER TOUS LES .ENV*
# ------------------------------------------------------------

restore_env_files() {

  echo
  echo "Restauration des fichiers locaux .env*"
  echo


  local file
  local rel
  local target
  local count=0


  while IFS= read -r -d '' file; do

    rel="${file#"$ROLLBACK_DIR/"}"


    # Sécurité supplémentaire
    [[ "$rel" == .git/* ]] && continue


    target="$PROJECT_ROOT/$rel"


    mkdir -p "$(dirname "$target")"


    cp -a \
      "$file" \
      "$target"


    echo "  ✓ $rel"


    count=$((count + 1))


  done < <(

    find "$ROLLBACK_DIR" \

      \( \
        -name node_modules \
        -o -name dist \
        -o -name build \
        -o -name coverage \
        -o -name .git \
      \) \
      -prune \

      -o \

      \( \
        -name '.env' \
        -o -name '.env.*' \
      \) \
      -type f \
      -print0

  )


  echo
  echo "Fichiers .env* restaurés : $count"
}


# ------------------------------------------------------------
# APPLY
# ------------------------------------------------------------

apply_project() {

  echo
  echo "=============================================="
  echo " Application du ZIP Bolt"
  echo "=============================================="
  echo


  # ----------------------------------------------------------
  # Vérifications AVANT de toucher au projet
  # ----------------------------------------------------------


  [[ -d "$PROJECT_ROOT/.git" ]] \
    || die ".git absent du projet local."


  [[ -d "$EXPORT_ROOT/frontend" ]] \
    || die "frontend/ absent de l'export Bolt."


  [[ -d "$EXPORT_ROOT/server" ]] \
    || die "server/ absent de l'export Bolt."


  # ----------------------------------------------------------
  # Ancien rollback
  # ----------------------------------------------------------


  if [[ -e "$ROLLBACK_DIR" ]]; then

    echo "Suppression de l'ancien rollback :"
    echo "  $ROLLBACK_DIR"
    echo

    rm -rf "$ROLLBACK_DIR"

  fi


  # ----------------------------------------------------------
  # Backup complet
  # ----------------------------------------------------------


  echo "Backup complet du V5 actuel :"
  echo
  echo "  $PROJECT_ROOT"
  echo "      ->"
  echo "  $ROLLBACK_DIR"
  echo


  mv \
    "$PROJECT_ROOT" \
    "$ROLLBACK_DIR"


  # ----------------------------------------------------------
  # Création nouveau V5
  # ----------------------------------------------------------


  echo "Création du nouveau V5 depuis Bolt..."
  echo


  mkdir -p "$PROJECT_ROOT"


  rsync \
    -a \
    "$EXPORT_ROOT/" \
    "$PROJECT_ROOT/"


  # ----------------------------------------------------------
  # Restauration des données locales
  # ----------------------------------------------------------


  echo "Restauration des éléments locaux..."
  echo


  restore_git

  restore_env_files


  # ----------------------------------------------------------
  # Vérification
  # ----------------------------------------------------------


  [[ -d "$PROJECT_ROOT/.git" ]] \
    || die ".git n'a pas été restauré."


  echo
  echo "=============================================="
  echo " Import terminé"
  echo "=============================================="
  echo


  echo "Nouveau projet :"
  echo "  $PROJECT_ROOT"
  echo


  echo "Rollback :"
  echo "  $ROLLBACK_DIR"
  echo


  echo "Git status :"
  echo


  git -C "$PROJECT_ROOT" status --short || true


  echo
  echo "Tu peux maintenant démarrer et tester PopNPlay."
  echo


  echo "Pour annuler complètement cet import :"
  echo
  echo "  $SCRIPT_DIR/import-bolt.sh --rollback"
  echo
}


# ------------------------------------------------------------
# ROLLBACK
# ------------------------------------------------------------

rollback_project() {

  [[ -d "$ROLLBACK_DIR" ]] \
    || die "Aucun rollback disponible."


  echo
  echo "=============================================="
  echo " PopNPlay - ROLLBACK"
  echo "=============================================="
  echo


  echo "Le projet actuel :"
  echo
  echo "  $PROJECT_ROOT"
  echo


  echo "sera remplacé par :"
  echo
  echo "  $ROLLBACK_DIR"
  echo


  echo "Le rollback remettra EXACTEMENT"
  echo "le dossier qui existait avant le dernier --apply."
  echo


  read -r -p \
    "Effectuer le rollback ? [y/N] " \
    answer


  case "$answer" in

    y|Y|yes|YES)
      ;;

    *)
      echo
      echo "Rollback annulé."
      exit 0
      ;;

  esac


  # ----------------------------------------------------------
  # Sécurité :
  #
  # On déplace d'abord le projet actuel.
  # On ne le supprime qu'après restauration réussie.
  # ----------------------------------------------------------


  FAILED_DIR="${PROJECT_ROOT}.failed"


  rm -rf "$FAILED_DIR"


  mv \
    "$PROJECT_ROOT" \
    "$FAILED_DIR"


  if mv \
      "$ROLLBACK_DIR" \
      "$PROJECT_ROOT"
  then

    rm -rf "$FAILED_DIR"


    echo
    echo "✓ Rollback terminé."
    echo


    echo "Git status :"
    echo


    git -C "$PROJECT_ROOT" status --short || true


    echo
    echo "Il n'y a maintenant plus de rollback disponible."
    echo

  else

    echo
    echo "ERREUR pendant le rollback."
    echo "Remise en place du projet courant..."


    [[ -e "$PROJECT_ROOT" ]] \
      && rm -rf "$PROJECT_ROOT"


    mv \
      "$FAILED_DIR" \
      "$PROJECT_ROOT"


    die "Rollback impossible."

  fi
}


# ============================================================
# MAIN
# ============================================================


echo
echo "=============================================="
echo " PopNPlay - Bolt Import V5 SIMPLE"
echo "=============================================="
echo

echo "PopNPlay repo : $PROJECT_ROOT"
echo "Toolbox       : $TOOLBOX_ROOT"
echo "Mode          : $MODE"


# ------------------------------------------------------------
# ROLLBACK
# ------------------------------------------------------------

if [[ "$MODE" == "rollback" ]]; then

  rollback_project

  exit 0

fi


# ------------------------------------------------------------
# ZIP
# ------------------------------------------------------------

ZIP_FILE="$(find_latest_zip)"


echo "ZIP           : $(basename "$ZIP_FILE")"


extract_zip "$ZIP_FILE"


# ------------------------------------------------------------
# DIFF
# ------------------------------------------------------------

show_diff


# ------------------------------------------------------------
# PREVIEW
# ------------------------------------------------------------

if [[ "$MODE" == "preview" ]]; then

  echo "Preview uniquement."
  echo "Le projet local n'a PAS été modifié."
  echo


  echo "Pour appliquer ce ZIP :"
  echo

  echo "  $SCRIPT_DIR/import-bolt.sh --apply"
  echo


  exit 0

fi


# ------------------------------------------------------------
# CONFIRMATION APPLY
# ------------------------------------------------------------

echo "=============================================="
echo " Remplacement complet"
echo "=============================================="
echo

echo "Si tu continues :"
echo
echo "  1. le V5 actuel sera sauvegardé EN ENTIER"
echo "  2. le contenu Bolt deviendra le nouveau V5"
echo "  3. .git/ sera récupéré depuis l'ancien V5"
echo "  4. tous les .env et .env.* seront récupérés"
echo
echo "Un seul rollback sera conservé."
echo

echo "Rollback :"
echo "  $ROLLBACK_DIR"
echo


read -r -p \
  "Remplacer le projet local par le ZIP Bolt ? [y/N] " \
  answer


case "$answer" in

  y|Y|yes|YES)
    ;;

  *)
    echo
    echo "Import annulé."
    exit 0
    ;;

esac


apply_project