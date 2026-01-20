#!/usr/bin/env bash
set -euo pipefail

# Edit this when putting the real ver to GACRC
#BASE_DIR="$PWD"
WORK_DIR="/work/ling4570/$USER"
BASE_DIR="$WORK_DIR"

NOTES_REPO_URL="https://github.com/uga-ling4570/notes.git"
NOTES_DIR="$BASE_DIR/notes"
NOTES_GH_DIR="${NOTES_DIR}/.gh_ver"

CONDA_SH="/apps/eb/Miniforge3/24.11.3-0/etc/profile.d/conda.sh"
CONDA_ENV="/work/kyllab/ling4570_env/conda_env_ling"

ASSIGN_DIR="$BASE_DIR/assignments"

# 1. Get GitHub credentials (with PAT)
git config --global credential.helper store

echo "GitHub authentication"
read -p "Name: " NAME
read -p "GitHub username: " GH_USER
MYID="$USER"
read -p "GitHub Personal Access Token (PAT): " GH_PAT
echo

cat > $HOME/.gitconfig <<EOF
[user]
        name = $NAME
        email = $MYID@uga.edu
        username = $GH_USER
[core]
        excludesfile = $HOME/.gitignore
[credential]
        helper = store
EOF

printf "protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n" \
  "$GH_USER" "$GH_PAT" | git credential approve

unset GH_PAT
chmod 600 $HOME/.git-credentials

echo "Credentials stored in ~/.git-credentials"
echo

# 2. Clone the main notes repo
mkdir -p "$NOTES_DIR"

if [[ ! -d "$NOTES_GH_DIR/.git" ]]; then
  git clone "$NOTES_REPO_URL" "$NOTES_GH_DIR"
else
  echo "Repo already exists at $NOTES_GH_DIR"
fi

# 3. Copy repo content to parent
rsync -av --exclude='.git' "$NOTES_GH_DIR"/ "$NOTES_DIR"/

# 4. Write update notes script
cat > "${NOTES_DIR}/update_notes.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="/work/ling4570/$USER"
BASE_DIR="$WORK_DIR/notes"

# BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
GH_DIR="${BASE_DIR}/.gh_ver"

cd "$GH_DIR"

OLD_HEAD="$(git rev-parse HEAD)"

git reset --hard
git clean -fd
git pull

NEW_HEAD="$(git rev-parse HEAD)"

mapfile -t UPDATED_FILES < <(
  git diff --name-only --diff-filter=M "$OLD_HEAD" "$NEW_HEAD"
)

rsync -av \
  --exclude='.git' \
  --ignore-existing \
  "$GH_DIR"/ "$BASE_DIR"/

for rel in "${UPDATED_FILES[@]}"; do
  src="$GH_DIR/$rel"
  target="$BASE_DIR/$rel"

  # only if student already has the file
  if [[ -f "$target" ]]; then
    dir="$(dirname "$target")"
    name="$(basename "$target")"

    if [[ "$name" == *.* ]]; then
      base="${name%.*}"
      ext="${name##*.}"
      newfile="${dir}/${base}_new.${ext}"
    else
      newfile="${dir}/${name}_new"
    fi

    # copy the NEW version only
    if [[ ! -f "$newfile" ]]; then
      cp "$src" "$newfile"
    fi
  fi
done

echo "notes updated."
EOF

chmod +x "${NOTES_DIR}/update_notes.sh"

if ! grep -q "alias update_notes=" ~/.bashrc; then
  echo "alias update_notes='${NOTES_DIR}/update_notes.sh'" >> ~/.bashrc
fi


# 5. Set up assignments
mkdir -p "${ASSIGN_DIR}"

cat > "${ASSIGN_DIR}/get_assignment.sh" << 'EOF'
WORK_DIR="/work/ling4570/$USER"
BASE_DIR="$WORK_DIR"
ASSIGN_DIR="$BASE_DIR/assignments"

# 1. Get username from git config
GH_USER=$(git config user.username | tr -d ' ')

# 2. Get PA number
read -p "Enter assignment number (1-6): " PA_NUM
if [[ ! "$PA_NUM" =~ ^[1-6]$ ]]; then
    echo "Error: Assignment number must be between 1 and 6."
    exit 1
fi

REPO_NAME="pa${PA_NUM}-${GH_USER}"
REPO_URL="https://github.com/uga-ling4570/${REPO_NAME}.git"
TARGET_DIR="${ASSIGN_DIR}/pa${PA_NUM}"

# 3. Create parent directory and clone
echo "Cloning $REPO_NAME into $TARGET_DIR..."

git clone "$REPO_URL" "$TARGET_DIR"

if [ $? -eq 0 ]; then
    echo "------------------------------------------------"
    echo "Setup complete. Your files are in: $TARGET_DIR"
else
    echo "Error: Clone failed. Verify the repo exists and your SSH keys/PAT are set."
fi
EOF

chmod +x "${ASSIGN_DIR}/get_assignment.sh"

if ! grep -q "alias get_assignment=" ~/.bashrc; then
  echo "alias get_assignment='${ASSIGN_DIR}/get_assignment.sh'" >> ~/.bashrc
fi

echo
echo "Setup complete."
echo "Please run 'source ~/.bashrc' now."
