#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
PRESETS=$CFG_DIR/presets.conf
TUNER=$(cd "${0%/*}" 2>/dev/null && pwd)/tuner.sh

mkdir -p "$CFG_DIR" 2>/dev/null
[ -f "$PRESETS" ] || : > "$PRESETS"

clean() {
  printf '%s' "$1" | tr -d '\n\r' | tr -d '|'
}

valid_name() {
  n=$(printf '%s' "$1" | tr -d '\n\r')
  [ -n "$n" ] || return 1
  case "$n" in
    powersave|balanced|performance|gaming) return 1 ;;
  esac
  case "$n" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  [ "${#n}" -le 24 ] || return 1
  return 0
}

exists() {
  awk -F'|' -v n="$1" '$1==n {f=1} END {exit !f}' "$PRESETS" 2>/dev/null
}

do_save() {
  name=$(clean "$1")
  base=$(clean "$2")
  valid_name "$name" || { printf 'ERR 名称无效（仅字母数字下划线连字符，不能与内置档重名）\n'; exit 1; }
  [ -n "$base" ] || base=balanced
  case "$base" in
    powersave|balanced|performance|gaming) ;;
    *) printf 'ERR 基准档无效\n'; exit 1 ;;
  esac
  exists "$name" && { printf 'ERR 已存在\n'; exit 1; }
  printf '%s|%s|%s\n' "$name" "$base" "$(date '+%Y-%m-%d %H:%M' 2>/dev/null)" >> "$PRESETS"
  printf 'OK 已保存预设 %s（基准 %s）\n' "$name" "$base"
}

do_del() {
  name=$(clean "$1")
  valid_name "$name" || { printf 'ERR 名称无效\n'; exit 1; }
  exists "$name" || { printf 'ERR 不存在\n'; exit 1; }
  awk -F'|' -v n="$name" '$1!=n {print}' "$PRESETS" > "$PRESETS.t" 2>/dev/null
  mv -f "$PRESETS.t" "$PRESETS" 2>/dev/null
  printf 'OK\n'
}

do_list() {
  while IFS='|' read -r n b t; do
    [ -n "$n" ] || continue
    printf '%s|%s|%s\n' "$n" "$b" "$t"
  done < "$PRESETS"
}

do_apply() {
  name=$(clean "$1")
  valid_name "$name" || { printf 'ERR 名称无效\n'; exit 1; }
  line=$(awk -F'|' -v n="$name" '$1==n {print; exit}' "$PRESETS" 2>/dev/null)
  [ -n "$line" ] || { printf 'ERR 预设不存在\n'; exit 1; }
  base=$(printf '%s' "$line" | cut -d'|' -f2)
  [ -n "$base" ] || base=balanced
  [ -x "$TUNER" ] || { printf 'ERR 找不到引擎\n'; exit 1; }
  sh "$TUNER" apply "$base" >/dev/null 2>&1
  printf 'OK 已应用 %s（基准 %s）\n' "$name" "$base"
}

case "$1" in
  list)
    do_list
    ;;
  save)
    do_save "$2" "$3"
    ;;
  del)
    do_del "$2"
    ;;
  apply)
    do_apply "$2"
    ;;
  *)
    printf 'usage: presets.sh {list|save <name> <base>|del <name>|apply <name>}\n'
    ;;
esac
