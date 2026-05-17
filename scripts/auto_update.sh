#!/bin/bash
# Dexter 自動更新スクリプト
#
# フロー:
#   1. upstream/main を fetch
#   2. ローカル main と diff が無ければ exit 0
#   3. merge を試行 → 衝突したら abort + 通知して exit 1
#   4. bun install → 失敗で rollback
#   5. bun run typecheck → 失敗で rollback
#   6. origin/main に push
#   7. 全工程を logs/auto_update.log に追記
#
# 失敗時のロールバック: ORIG_HEAD に hard reset
# launchd: com.dexter.autoupdate (週次, 日曜 04:00 JST)

set -u

DEXTER_DIR="/Library/claude/agent/dexter"
LOG_FILE="$DEXTER_DIR/logs/auto_update.log"
LOCK_FILE="$DEXTER_DIR/logs/auto_update.lock"

# bun は ~/.bun/bin にあるので PATH に追加
export PATH="$HOME/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*" >> "$LOG_FILE"
}

cleanup_lock() {
    rm -f "$LOCK_FILE"
}

# 多重起動防止
if [ -e "$LOCK_FILE" ]; then
    log "ERROR: lock file exists ($LOCK_FILE) — previous run may still be active. abort."
    exit 1
fi
touch "$LOCK_FILE"
trap cleanup_lock EXIT

cd "$DEXTER_DIR" || { log "ERROR: cannot cd to $DEXTER_DIR"; exit 1; }

log "=== auto_update start ==="

# 作業ツリーがクリーンか確認（dirty なら触らない）
if [ -n "$(git status --porcelain)" ]; then
    log "ERROR: working tree is dirty. skip update."
    git status --porcelain >> "$LOG_FILE"
    exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    log "ERROR: not on main branch (current: $CURRENT_BRANCH). skip update."
    exit 1
fi

BEFORE_HEAD=$(git rev-parse HEAD)
log "current HEAD: $BEFORE_HEAD"

# upstream fetch
if ! git fetch upstream 2>>"$LOG_FILE"; then
    log "ERROR: git fetch upstream failed."
    exit 1
fi

UPSTREAM_HEAD=$(git rev-parse upstream/main)
log "upstream/main: $UPSTREAM_HEAD"

# 既に最新なら何もしない
if git merge-base --is-ancestor "$UPSTREAM_HEAD" HEAD; then
    log "already up to date. exit."
    exit 0
fi

BEHIND_COUNT=$(git rev-list --count HEAD..upstream/main)
log "behind upstream by $BEHIND_COUNT commits. merging."

# merge
if ! git merge upstream/main --no-edit --no-ff 2>>"$LOG_FILE"; then
    log "ERROR: merge conflict. aborting."
    git merge --abort 2>>"$LOG_FILE"
    log "merge aborted. manual intervention required."
    exit 1
fi

AFTER_MERGE_HEAD=$(git rev-parse HEAD)
log "merged. new HEAD: $AFTER_MERGE_HEAD"

# bun install
if ! bun install 2>>"$LOG_FILE"; then
    log "ERROR: bun install failed. rolling back."
    git reset --hard "$BEFORE_HEAD" 2>>"$LOG_FILE"
    exit 1
fi
log "bun install OK"

# typecheck
if ! bun run typecheck 2>>"$LOG_FILE"; then
    log "ERROR: typecheck failed. rolling back."
    git reset --hard "$BEFORE_HEAD" 2>>"$LOG_FILE"
    exit 1
fi
log "typecheck OK"

# push to origin (fork)
if ! git push origin main 2>>"$LOG_FILE"; then
    log "ERROR: git push origin main failed. local main は更新済み、手動で push してください。"
    exit 1
fi
log "pushed to origin/main"

NEW_VERSION=$(grep '"version"' package.json | head -1 | sed -E 's/.*"version": "([^"]+)".*/\1/')
log "=== auto_update complete: $BEFORE_HEAD → $AFTER_MERGE_HEAD (v$NEW_VERSION) ==="
exit 0
