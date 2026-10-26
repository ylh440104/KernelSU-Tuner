#!/system/bin/sh

CFG_DIR=/data/adb/ksu_tuner
CFG=$CFG_DIR/config.conf
RULES=$CFG_DIR/apprules.conf
CUSTOM=$CFG_DIR/custom.conf
WL=$CFG_DIR/whitelist.txt
EXPORT_DIR=/sdcard/KernelSU-Tuner-Backup

mkdir -p "$EXPORT_DIR" 2>/dev/null

stamp() {
  date '+%Y%m%d-%H%M%S' 2>/dev/null
}

jesc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'
}

file_lines() {
  [ -f "$1" ] || { printf '0'; return 0; }
  n=$(wc -l "$1" 2>/dev/null | awk '{print $1}')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

emit_lines() {
  [ -f "$1" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '      "%s"' "$(jesc "$line")"
    last=$(tail -n 1 "$1" 2>/dev/null)
    if [ "$line" != "$last" ]; then
      printf ',\n'
    else
      printf '\n'
    fi
  done < "$1"
}

do_export() {
  out="$1"
  [ -n "$out" ] || out="$EXPORT_DIR/ksu-tuner-$(stamp).json"

  {
    printf '{\n'
    printf '  "format": "ksu-tuner-backup",\n'
    printf '  "version": 1,\n'
    printf '  "moduleId": "KernelSU-Tuner",\n'
    printf '  "exportedAt": "%s",\n' "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)"
    printf '  "config": [\n'
    if [ -f "$CFG" ]; then
      first=1
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        k=$(printf '%s' "$line" | cut -d= -f1)
        v=$(printf '%s' "$line" | cut -d= -f2-)
        case "$k" in
          LAST_APPLY|LAST_TRIM|GUARD_ANSWER) continue ;;
        esac
        if [ "$first" = "1" ]; then first=0; else printf ',\n'; fi
        printf '    {"k": "%s", "v": "%s"}' "$(jesc "$k")" "$(jesc "$v")"
      done < "$CFG"
    fi
    printf '\n  ],\n'
    printf '  "apprules": [\n'
    emit_lines "$RULES"
    printf '  ],\n'
    printf '  "custom": [\n'
    emit_lines "$CUSTOM"
    printf '  ],\n'
    printf '  "whitelist": [\n'
    emit_lines "$WL"
    printf '  ]\n'
    printf '}\n'
  } > "$out" 2>/dev/null

  if [ -s "$out" ]; then
    sz=$(wc -c "$out" 2>/dev/null | awk '{print $1}')
    printf '已导出: %s (%s 字节)\n' "$out" "$sz"
    printf 'CFG=%s RULES=%s CUSTOM=%s WL=%s\n' "$(file_lines "$CFG")" "$(file_lines "$RULES")" "$(file_lines "$CUSTOM")" "$(file_lines "$WL")"
  else
    printf 'ERR 导出失败\n'
    rm -f "$out" 2>/dev/null
    return 1
  fi
}

jget() {
  printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

do_import() {
  src="$1"
  [ -f "$src" ] || { printf 'ERR 文件不存在: %s\n' "$src"; return 1; }

  fmt=$(jget "$(cat "$src")" format)
  if [ "$fmt" != "ksu-tuner-backup" ]; then
    printf 'ERR 格式不匹配: %s\n' "${fmt:-unknown}"
    return 1
  fi

  python3 - "$src" "$CFG" "$RULES" "$CUSTOM" "$WL" <<'PYEOF'
import json, sys, io, os

src, cfg, rules, custom, wl = sys.argv[1:6]
try:
    d = json.load(io.open(src, encoding="utf-8"))
except Exception as e:
    print("ERR 解析失败: %s" % e)
    sys.exit(1)

n_cfg = n_rules = n_custom = n_wl = 0

cfg_pairs = []
for item in d.get("config", []):
    k = str(item.get("k", "")).strip()
    v = str(item.get("v", ""))
    if not k or "=" in k or "|" in k:
        continue
    cfg_pairs.append((k, v))

if cfg_pairs:
    existing = []
    if os.path.isfile(cfg):
        for line in io.open(cfg, encoding="utf-8"):
            line = line.rstrip("\n")
            if not line or "=" not in line:
                continue
            k = line.split("=", 1)[0]
            existing.append(line)
    newkeys = dict(cfg_pairs)
    out = []
    for line in existing:
        k = line.split("=", 1)[0]
        if k in newkeys:
            out.append("%s=%s" % (k, newkeys[k]))
            n_cfg += 1
        else:
            out.append(line)
    have = set(x.split("=", 1)[0] for x in out)
    for k, v in cfg_pairs:
        if k not in have:
            out.append("%s=%s" % (k, v))
            n_cfg += 1
    with io.open(cfg, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

for key, path, counter in (("apprules", rules, "rules"), ("custom", custom, "custom"), ("whitelist", wl, "wl")):
    items = d.get(key, [])
    if not items:
        continue
    clean = []
    for it in items:
        s = str(it).strip()
        if not s or "\n" in s:
            continue
        clean.append(s)
    if clean:
        with io.open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(clean) + "\n")
        if counter == "rules":
            n_rules = len(clean)
        elif counter == "custom":
            n_custom = len(clean)
        else:
            n_wl = len(clean)

for p in (cfg, rules, custom, wl):
    try:
        os.chmod(p, 0o600)
    except Exception:
        pass

print("已导入: config=%d rules=%d custom=%d whitelist=%d" % (n_cfg, n_rules, n_custom, n_wl))
PYEOF
}

case "$1" in
  export)
    do_export "$2"
    ;;
  import)
    do_import "$2"
    ;;
  list)
    ls -1t "$EXPORT_DIR" 2>/dev/null | head -n 20
    ;;
  path)
    printf '%s\n' "$EXPORT_DIR"
    ;;
  *)
    printf 'usage: backup.sh {export [file]|import <file>|list|path}\n'
    ;;
esac
