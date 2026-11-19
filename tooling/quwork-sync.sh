#!/usr/bin/env bash
# 把 fork（origin = Jlnvv-tom/quwork-mobile）与源项目（ccch1mneyyy/dsh-go）同步：
#   1. 配置 upstream 远端（已存在则校验地址）；
#   2. fetch upstream 与 origin；
#   3. 把本地 main 快进到 upstream/main；
#   4. 把 upstream/main 合入工作分支（默认当前分支，通常是 quwork）；
#   5. 加 --push 时才推送到 origin。
# 工作区有未提交改动时直接停住，不 stash、不 reset。
set -euo pipefail

ROOT=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -f "$ROOT/tooling/env.sh" ]] && source "$ROOT/tooling/env.sh"
CONFIG_FILE="${QUWORK_CONFIG_FILE:-$ROOT/tooling/quwork.env}"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
cd "$ROOT"

UPSTREAM_REMOTE="${QUWORK_UPSTREAM_REMOTE:-upstream}"
UPSTREAM_URL="${QUWORK_UPSTREAM_URL:-https://github.com/ccch1mneyyy/dsh-go.git}"
BASE_BRANCH="${QUWORK_SYNC_BASE:-main}"
UPSTREAM_BRANCH="${QUWORK_SYNC_UPSTREAM_BRANCH:-main}"
TARGET_BRANCH=""
CHECK_ONLY=0
MERGE=1
PUSH=0

usage() {
  cat <<'EOF'
用法：tooling/quwork-sync.sh [选项]

  --check              只 fetch 并报告差距，不改任何分支
  --branch NAME        合入的目标分支，默认当前分支
  --no-merge           只更新 main，不合入工作分支
  --push               同步后推送到 origin（默认只改本地）
  -h, --help           显示帮助

环境变量：
  QUWORK_UPSTREAM_URL     源仓库地址，默认 https://github.com/ccch1mneyyy/dsh-go.git
  QUWORK_UPSTREAM_REMOTE  远端名，默认 upstream
  QUWORK_SYNC_BASE        本地基线分支，默认 main
EOF
}

while (($#)); do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --branch) TARGET_BRANCH="${2:?--branch 需要分支名}"; shift 2 ;;
    --branch=*) TARGET_BRANCH="${1#*=}"; shift ;;
    --no-merge) MERGE=0; shift ;;
    --push) PUSH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "不在 git 仓库里" >&2; exit 1; }

# 1. upstream 远端：缺失则添加，地址不符则让人显式确认，不偷偷改
have_url=$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null || true)
if [[ -z "$have_url" ]]; then
  # 只跟踪目标分支：上游有几百个分支，全量 fetch 又慢又没必要
  git remote add -t "$UPSTREAM_BRANCH" "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
  echo "已添加远端 $UPSTREAM_REMOTE -> $UPSTREAM_URL"
elif [[ "${have_url%.git}" != "${UPSTREAM_URL%.git}" ]]; then
  echo "远端 $UPSTREAM_REMOTE 已指向 $have_url，与期望的 $UPSTREAM_URL 不一致。" >&2
  echo "确认后执行：git remote set-url $UPSTREAM_REMOTE $UPSTREAM_URL" >&2
  exit 1
fi

if [[ -z "$TARGET_BRANCH" ]]; then
  TARGET_BRANCH=$(git symbolic-ref --quiet --short HEAD) || {
    echo "当前是 detached HEAD，请用 --branch 指定要同步的分支" >&2
    exit 1
  }
fi
git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH" || { echo "本地没有分支 $TARGET_BRANCH" >&2; exit 1; }

# 2. 有未提交改动就不动分支：用户的工作不归脚本处理
if ((!CHECK_ONLY)); then
  dirty=$(git status --porcelain)
  if [[ -n "$dirty" ]]; then
    echo "工作区有未提交改动，同步会覆盖合并结果，先自行提交或备份：" >&2
    git status --short --untracked-files=no >&2
    exit 1
  fi
fi

echo "== fetch $UPSTREAM_REMOTE 和 origin"
git fetch --prune --no-tags "$UPSTREAM_REMOTE" \
  "+refs/heads/$UPSTREAM_BRANCH:refs/remotes/$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
git fetch --prune --no-tags origin

upstream_ref="refs/remotes/$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
git show-ref --verify --quiet "$upstream_ref" || { echo "源仓库没有 $UPSTREAM_BRANCH 分支" >&2; exit 1; }
head_of=$UPSTREAM_REMOTE/$UPSTREAM_BRANCH

behind_ahead() { git rev-list --left-right --count "$1...$2"; }

echo "== 差距"
echo "  $head_of: $(git log -1 --format='%h %s' "$upstream_ref")"
if git show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
  read -r base_ahead base_behind <<<"$(behind_ahead "refs/heads/$BASE_BRANCH" "$upstream_ref")"
  echo "  $BASE_BRANCH: 领先 $base_ahead，落后 $base_behind"
fi
read -r tgt_ahead tgt_behind <<<"$(behind_ahead "refs/heads/$TARGET_BRANCH" "$upstream_ref")"
echo "  $TARGET_BRANCH: 领先 $tgt_ahead，落后 $tgt_behind"

if ((CHECK_ONLY)); then
  echo "只检查，未改动任何分支。确认无误后去掉 --check 再跑一次。"
  exit 0
fi

# 3. 本地 main 只做快进；有本地独有提交时保持原样并提示
if git show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
  base_ref="refs/heads/$BASE_BRANCH"
  if git merge-base --is-ancestor "$base_ref" "$upstream_ref"; then
    if [[ "$BASE_BRANCH" == "$TARGET_BRANCH" ]]; then
      git merge --ff-only "$head_of"
    else
      git update-ref -m "quwork-sync: fast-forward to $head_of" "$base_ref" "$upstream_ref"
      echo "已把 $BASE_BRANCH 快进到 $head_of"
    fi
  else
    echo "$BASE_BRANCH 有源仓库没有的提交，跳过快进，未改动它。" >&2
  fi
fi

# 4. 把源项目合入工作分支：冲突就停住，留给人工解决
if ((MERGE)) && [[ "$TARGET_BRANCH" != "$BASE_BRANCH" ]]; then
  if [[ "$(git symbolic-ref --quiet --short HEAD || true)" != "$TARGET_BRANCH" ]]; then
    git checkout "$TARGET_BRANCH"
  fi
  if git merge-base --is-ancestor "$upstream_ref" HEAD; then
    echo "$TARGET_BRANCH 已包含 $head_of，无需合并"
  elif git merge --no-edit "$upstream_ref"; then
    echo "已把 $head_of 合入 $TARGET_BRANCH"
  else
    if git rev-parse -q --verify MERGE_HEAD >/dev/null && [[ -n "$(git ls-files --unmerged)" ]]; then
      cat >&2 <<'EOF'
合并停在冲突状态，改动没有丢。
  解决冲突后：git add <文件> && git commit
  放弃这次合并：git merge --abort
EOF
      exit 3
    fi
    echo "合并没有完成，也没有留下合并状态；按上面 git 的报错处理，工作区未提交改动。" >&2
    exit 4
  fi
fi

# 5. 推送需要显式 --push，且只做快进推送
if ((PUSH)); then
  git push origin "refs/heads/$BASE_BRANCH:refs/heads/$BASE_BRANCH"
  if [[ "$TARGET_BRANCH" != "$BASE_BRANCH" ]]; then
    git push origin "refs/heads/$TARGET_BRANCH:refs/heads/$TARGET_BRANCH"
  fi
  echo "已推送 $BASE_BRANCH 与 $TARGET_BRANCH 到 origin"
else
  echo "未推送。需要时加 --push，或手动 git push origin $TARGET_BRANCH"
fi

cat <<EOF
== 同步后按改动面验证
  (cd app && flutter pub get && flutter analyze && flutter test)
  python3 app/tool/l10n_merge.py --check
  python3 app/tool/guide_sync.py --check
  引擎补丁有变化时先看 runtime/patches/pins.json 与 runtime/tests/*.test.mjs
EOF
