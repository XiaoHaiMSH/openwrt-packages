#!/usr/bin/env bash

set -euo pipefail

UPSTREAM="${UPSTREAM:?UPSTREAM is required}"
PACKAGES="${PACKAGES:?PACKAGES is required}"
DRY_RUN="${DRY_RUN:-0}"
TODAY="${SYNC_DATE:-$(date +%Y%m%d)}"

die() { echo "::error::$*"; exit 1; }

has_var() { grep -qE "^$2[[:space:]]*:?=" "$1"; }

get_var() {
  grep -m1 -E "^$2[[:space:]]*:?=" "$1" \
    | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]+$//' || true
}

set_var() { sed -i -E "s|^$2[[:space:]]*:?=.*|$2:=$3|" "$1"; }

insert_after() {
  local tmp; tmp="$(mktemp)"
  RE="$2" TXT="$3" awk '{ print } !done && $0 ~ ENVIRON["RE"] { print ENVIRON["TXT"]; done = 1 }' "$1" > "$tmp"
  cat "$tmp" > "$1"; rm -f "$tmp"
}

ensure_fields() {
  local mk="$1" date_mode="$2" p="$3"
  if ! has_var "$mk" PKG_VERSION; then
    if [[ "$date_mode" == 1 ]]; then
      insert_after "$mk" '^include .*rules\.mk' 'PKG_VERSION:=0'
    else
      echo "::warning::$p has no PKG_VERSION and @date is not used, skipping field patching"
      return 1
    fi
  fi
  has_var "$mk" PKG_RELEASE \
    || insert_after "$mk" '^PKG_VERSION[[:space:]]*:?=' 'PKG_RELEASE:=1'
  has_var "$mk" PKG_PO_VERSION \
    || insert_after "$mk" '^PKG_RELEASE[[:space:]]*:?=' 'PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)'
  return 0
}

targets=()

sync_one() {
  local item="$1" v="" p src mk old_ver="" old_rel="" is_luci=0 new_rel

  if [[ "$item" == *@* ]]; then v="${item#*@}"; item="${item%%@*}"; fi
  p="${item%%=*}"; src="$p"
  if [[ "$item" == *=* ]]; then src="${item#*=}"; fi

  [[ "$p" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid package name: '$p'"
  if [[ "$src" != . ]]; then
    [[ "$src" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$src" != *..* ]] || die "invalid upstream path: '$src'"
  fi
  [[ -d "$up/$src" ]] || die "$src not found in upstream"

  mk="$p/Makefile"
  if [[ -f "$mk" ]]; then
    old_ver="$(get_var "$mk" PKG_VERSION)"
    old_rel="$(get_var "$mk" PKG_RELEASE)"
  fi

  rm -rf -- "$p"
  mkdir -p -- "$p"
  cp -a -- "$up/$src/." "$p/"
  rm -rf -- "$p/.git" "$p/.github"

  [[ -f "$mk" ]] || die "$mk not found"

  if grep -q 'luci\.mk' "$mk"; then is_luci=1; fi
  targets+=("$p")

  if [[ "$v" == date ]]; then
    [[ "$is_luci" == 1 ]] || die "$p is not a luci package (no luci.mk in Makefile), @date is not allowed"
    ensure_fields "$mk" 1 "$p"

    if [[ -n "$old_ver" ]]; then
      set_var "$mk" PKG_VERSION "$old_ver"
      if [[ -n "$old_rel" ]]; then set_var "$mk" PKG_RELEASE "$old_rel"; fi
    fi
    git add -A -- "$p"
    if git diff --cached --quiet -- "$p"; then
      echo "$p: no upstream update, version stays ${old_ver}-r${old_rel}"
      return 0
    fi

    if [[ "$old_ver" == "$TODAY" && "$old_rel" =~ ^[0-9]+$ ]]; then
      new_rel=$((old_rel + 1))
    else
      new_rel=1
    fi
    set_var "$mk" PKG_VERSION "$TODAY"
    set_var "$mk" PKG_RELEASE "$new_rel"
    echo "$p: updated, version -> ${TODAY}-r${new_rel}"
  else
    if [[ -n "$v" ]]; then set_var "$mk" PKG_VERSION "$v"; fi
    if [[ "$is_luci" == 1 ]]; then ensure_fields "$mk" 0 "$p" || true; fi
    echo "$p: synced${v:+, version pinned to $v}"
  fi
}

commit_and_push() {
  local label="$1" sha="$2" branch i
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git add -A -- "${targets[@]}"
  if git diff --cached --quiet; then
    echo "nothing to commit"
    return 0
  fi
  git commit -q -m "chore: 同步 ${label} (${sha})"

  branch="$(git rev-parse --abbrev-ref HEAD)"
  for i in 1 2 3; do
    if git push; then return 0; fi
    echo "::warning::push failed (attempt $i/3), rebasing onto origin/$branch and retrying"
    git pull --rebase --quiet origin "$branch" || { git rebase --abort 2>/dev/null || true; }
    sleep $((i * 3))
  done
  die "push failed after 3 attempts"
}

up="$(mktemp -d)"
trap 'rm -rf "$up"' EXIT

read -r url ref extra <<<"$UPSTREAM"
[[ -z "$extra" ]] || die "UPSTREAM should be '<url> [branch-or-tag]', got: $UPSTREAM"

clone_args=(--quiet --depth=1)
if [[ -n "$ref" ]]; then clone_args+=(--branch "$ref"); fi
git -c advice.detachedHead=false clone "${clone_args[@]}" "$url" "$up" || die "clone failed: $url${ref:+ (ref: $ref)}"
sha="$(git -C "$up" rev-parse --short=7 HEAD)"
label="$(sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#/+$##; s#\.git$##' <<<"$url")"

set -f; items=($PACKAGES); set +f
[[ ${#items[@]} -gt 0 ]] || die "PACKAGES is empty"

for item in "${items[@]}"; do
  sync_one "$item"
done

if [[ "$DRY_RUN" == 1 ]]; then
  git add -A -- "${targets[@]}"
  echo "DRY_RUN: staged changes, skipping commit/push"
  git status --short
  exit 0
fi

commit_and_push "$label" "$sha"
