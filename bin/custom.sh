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

is_num() {
  case "$1" in
    ''|*[!0-9-]*) return 1 ;;
    -) return 1 ;;
    --*|-*-*) return 1 ;;
  esac
  return 0
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

read1() {
  head -n 1 "$1" 2>/dev/null | tr -d '\n\r'
}

limit_of() {
  p=$1
  k=$2
  d=${p%/*}
  b=${p##*/}
  for c in "$d/$k" "$d/${b}_$k"; do
    [ -f "$c" ] || continue
    v=$(read1 "$c")
    is_num "$v" && { printf '%s' "$v"; return 0; }
  done
  case "$b" in
    scaling_max_freq|scaling_min_freq|cpuinfo_max_freq|cpuinfo_min_freq)
      for c in "$d/cpuinfo_${k}_freq" "$d/scaling_${k}_freq"; do
        [ -f "$c" ] || continue
        v=$(read1 "$c")
        is_num "$v" && { printf '%s' "$v"; return 0; }
      done
      ;;
  esac
  return 1
}

range_check() {
  p=$1
  v=$2
  is_num "$v" || return 0
  lo=$(limit_of "$p" min)
  hi=$(limit_of "$p" max)
  [ -n "$lo" ] || [ -n "$hi" ] || return 0
  if [ -n "$lo" ] && [ "$v" -lt "$lo" ]; then
    printf 'ERR 低于下限 %s' "$lo"
    return 1
  fi
  if [ -n "$hi" ] && [ "$v" -gt "$hi" ]; then
    printf 'ERR 高于上限 %s' "$hi"
    return 1
  fi
  if [ -n "$lo" ] && [ -n "$hi" ]; then
    printf 'OK 范围内 %s-%s' "$lo" "$hi"
  else
    printf 'OK 范围 %s' "${lo:-?}-${hi:-?}"
  fi
  return 0
}

bk_save() {
  [ -f "$1" ] || return 0
  grep -qF "$1|" "$BAK" 2>/dev/null && return 0
  v=$(read1 "$1")
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
    cur=$(read1 "$SYS$p")
    exists=0
    [ -f "$SYS$p" ] && exists=1
    lo=$(limit_of "$SYS$p" min)
    hi=$(limit_of "$SYS$p" max)
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$p" "$v" "$l" "$cur" "$exists" "$lo" "$hi"
  done < "$CUSTOM"
}

do_check() {
  p=$(clean "$1")
  v=$(clean "$2")
  valid_path "$p" || { printf 'ERR 路径无效\n'; exit 1; }
  [ -f "$SYS$p" ] || { printf 'ERR 节点不存在\n'; exit 1; }
  out=$(range_check "$SYS$p" "$v")
  printf '%s\n' "$out"
  case "$out" in ERR*) exit 1 ;; esac
}

do_add() {
  p=$(clean "$1")
  v=$(clean "$2")
  l=$(clean "$3")
  force=$(clean "$4")
  valid_path "$p" || { printf 'ERR 路径无效\n'; exit 1; }
  has_path "$p" && { printf 'ERR 已存在\n'; exit 1; }
  [ -n "$l" ] || l="$p"
  note=""
  if [ ! -f "$SYS$p" ]; then
    note=" 节点当前不存在，已记录待应用"
  elif [ "$force" != "force" ]; then
    out=$(range_check "$SYS$p" "$v")
    case "$out" in
      ERR*) printf '%s（加 force 可忽略）\n' "$out"; exit 1 ;;
      *) note=" $out" ;;
    esac
  fi
  printf '%s|%s|%s\n' "$p" "$v" "$l" >> "$CUSTOM"
  printf 'OK%s\n' "$note"
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
  force=$(clean "$3")
  valid_path "$p" || { printf 'ERR 路径无效\n'; exit 1; }
  has_path "$p" || { printf 'ERR 不存在\n'; exit 1; }
  note=""
  if [ -f "$SYS$p" ] && [ "$force" != "force" ]; then
    out=$(range_check "$SYS$p" "$v")
    case "$out" in
      ERR*) printf '%s（加 force 可忽略）\n' "$out"; exit 1 ;;
      *) note=" $out" ;;
    esac
  fi
  awk -F'|' -v p="$p" -v v="$v" 'BEGIN{OFS="|"} {if ($1==p) $2=v; print}' "$CUSTOM" > "$CUSTOM.t" 2>/dev/null
  mv -f "$CUSTOM.t" "$CUSTOM" 2>/dev/null
  printf 'OK%s\n' "$note"
}

do_read() {
  p=$(clean "$1")
  valid_path "$p" || exit 1
  read1 "$SYS$p"
  printf '\n'
}

do_apply() {
  n=0
  f=0
  s=0
  while IFS='|' read -r p v l; do
    [ -n "$p" ] || continue
    valid_path "$p" || continue
    if [ ! -f "$SYS$p" ]; then
      s=$((s + 1))
      continue
    fi
    if wr "$SYS$p" "$v"; then
      n=$((n + 1))
    else
      f=$((f + 1))
    fi
  done < "$CUSTOM"
  printf '已应用 %s 项，失败 %s 项，跳过 %s 项\n' "$n" "$f" "$s"
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
  check)
    do_check "$2" "$3"
    ;;
  add)
    do_add "$2" "$3" "$4" "$5"
    ;;
  del)
    do_del "$2"
    ;;
  set)
    do_set "$2" "$3" "$4"
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
    printf 'usage: custom.sh {list|check <path> <value>|add <path> <value> [label] [force]|del <path>|set <path> <value> [force]|read <path>|apply|revert}\n'
    ;;
esac
