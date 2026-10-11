#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CUSTOM=$CFG_DIR/custom.conf
BAK=$CFG_DIR/backup.conf
SYS=${KSU_SYS:-}

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$CUSTOM" ] || : > "$CUSTOM"
[ -f "$BAK" ] || : > "$BAK"

clean() {
  printf '%s' "$1" | tr -d '\n\r'
}

valid_path() {
  case "$1" in
    /sys/*|/proc/*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *".."*) return 1 ;;
  esac
  case "$1" in
    *"|"*) return 1 ;;
  esac
  return 0
}

has_path() {
  awk -F'|' -v p="$1" '$1==p {f=1} END {exit !f}' "$CUSTOM" 2>/dev/null
}

bk_save() {
  [ -f "$1" ] || return 0
  grep -qF "$1|" "$BAK" 2>/dev/null && return 0
  v=$(head -n 1 "$1" 2>/dev/null)
  [ -n "$v" ] || return 0
  printf '%s|%s\n' "$1" "$v" >> "$BAK"
}

wr() {
  [ -f "$1" ] || return 1
  bk_save "$1"
  chmod 0644 "$1" 2>/dev/null
  ( printf '%s' "$2" > "$1" ) 2>/dev/null || return 1
  return 0
}

do_list() {
  while IFS='|' read -r p v l; do
    [ -n "$p" ] || continue
    cur=$(head -n 1 "$SYS$p" 2>/dev/null)
    exists=0
    [ -f "$SYS$p" ] && exists=1
    printf '%s|%s|%s|%s|%s\n' "$p" "$v" "$l" "$cur" "$exists"
  done < "$CUSTOM"
}

do_add() {
  p=$(clean "$1")
  v=$(clean "$2")
  l=$(clean "$3")
  valid_path "$p" || { printf 'ERR 路径无效\n'; exit 1; }
  has_path "$p" && { printf 'ERR 已存在\n'; exit 1; }
  [ -n "$l" ] || l="$p"
  printf '%s|%s|%s\n' "$p" "$v" "$l" >> "$CUSTOM"
  printf 'OK\n'
}

do_del() {
  p=$(clean "$1")
  valid_path "$p" || { printf 'ERR 路径无效\n'; exit 1; }
  awk -F'|' -v p="$p" '$1!=p {print}' "$CUSTOM" > "$CUSTOM.t" 2>/dev/null
  mv -f "$CUSTOM.t" "$CUSTOM" 2>/dev/null
  printf 'OK\n'
}

do_set() {
  p=$(clean "$1")
  v=$(clean "$2")
  valid_path "$p" || { printf 'ERR 路径无效\n'; exit 1; }
  has_path "$p" || { printf 'ERR 不存在\n'; exit 1; }
  awk -F'|' -v p="$p" -v v="$v" 'BEGIN{OFS="|"} {if ($1==p) $2=v; print}' "$CUSTOM" > "$CUSTOM.t" 2>/dev/null
  mv -f "$CUSTOM.t" "$CUSTOM" 2>/dev/null
  printf 'OK\n'
}

do_read() {
  p=$(clean "$1")
  valid_path "$p" || exit 1
  head -n 1 "$SYS$p" 2>/dev/null
  printf '\n'
}

do_apply() {
  n=0
  f=0
  while IFS='|' read -r p v l; do
    [ -n "$p" ] || continue
    valid_path "$p" || continue
    if wr "$SYS$p" "$v"; then
      n=$((n + 1))
    else
      f=$((f + 1))
    fi
  done < "$CUSTOM"
  printf '已应用 %s 项，失败 %s 项\n' "$n" "$f"
}

do_revert() {
  [ -s "$BAK" ] || { printf '无备份可还原\n'; return 0; }
  n=0
  : > "$BAK.t"
  while IFS='|' read -r bp bv; do
    [ -n "$bp" ] || continue
    rp="$bp"
    [ -n "$SYS" ] && rp=${bp#"$SYS"}
    if awk -F'|' -v q="$rp" '$1==q {f=1} END {exit !f}' "$CUSTOM" 2>/dev/null; then
      chmod 0644 "$bp" 2>/dev/null
      ( printf '%s' "$bv" > "$bp" ) 2>/dev/null
      n=$((n + 1))
    else
      printf '%s|%s\n' "$bp" "$bv" >> "$BAK.t"
    fi
  done < "$BAK"
  mv -f "$BAK.t" "$BAK" 2>/dev/null
  printf '已还原 %s 项自定义参数\n' "$n"
}

case "$1" in
  list)
    do_list
    ;;
  add)
    do_add "$2" "$3" "$4"
    ;;
  del)
    do_del "$2"
    ;;
  set)
    do_set "$2" "$3"
    ;;
  read)
    do_read "$2"
    ;;
  apply)
    do_apply
    ;;
  revert)
    do_revert
    ;;
  *)
    printf 'usage: custom.sh {list|add <path> <value> [label]|del <path>|set <path> <value>|read <path>|apply|revert}\n'
    ;;
esac