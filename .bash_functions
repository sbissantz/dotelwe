# --------------------------------------------------
# ~/.bash_functions
# --------------------------------------------------

# ---- helpers ----
_slurm_blue()  { printf "\033[94m"; }
_slurm_reset() { printf "\033[0m"; }

# ---- lsjobs ----
lsjobs() {
  local who="${1:-$USER}"
  local BLUE="$(_slurm_blue)"
  local RESET="$(_slurm_reset)"

  squeue -u "$who" -h -o "%i|%t|%P|%j|%C|%m|%M|%D|%R" |
  awk -F'|' -v BLUE="$BLUE" -v RESET="$RESET" '
    BEGIN {
      printf "%-10s %-5s %-14s %-26s %-4s %-6s %-10s %-5s %s\n",
             "JOBID","ST","PARTITION","NAME","CPU","MEM","TIME","NODES","WHERE/REASON"
    }
    {
      printf "%s%-10s%s %-5s %-14s %-26.26s %-4s %-6s %-10s %-5s %s\n",
             BLUE, $1, RESET,
             $2, $3, $4, $5, $6, $7, $8, $9
    }'
}

# ---- lsnodes ----
lsnodes() {
  local part="$1"
  local BLUE="$(_slurm_blue)"
  local RESET="$(_slurm_reset)"
  local fmt="%15N %4c %7m %46f %18G"
  local cmd=(sinfo -h -o "$fmt")
  [[ -n "$part" ]] && cmd+=(-p "$part")

  printf "%-15s %-4s %-7s %-46s %-18s\n" \
         "NODELIST" "CPUS" "MEM" "FEATURES" "RESOURCES"

  "${cmd[@]}" |
  awk -v BLUE="$BLUE" -v RESET="$RESET" '
    function trim(s){ sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }

    function human_mem(m, gb){
      if (m !~ /^[0-9]+$/) return m
      gb = m/1024.0
      if (gb >= 1024.0) return sprintf("%.1fT", gb/1024.0)
      return sprintf("%.0fG", gb)
    }

    function human_gres_with_raw(g,   out,n,i,raw,base,tok,parts){
      g = trim(g)
      if (g=="" || g=="(null)" || g=="N/A") return "-"

      n = split(g, parts, ",")
      out = ""
      for (i=1; i<=n; i++) {
        raw = trim(parts[i]); if (raw=="") continue
        base = raw; sub(/\(.*/, "", base)

        tok = raw
        if (match(base, /^gpu:([^:]+):([0-9]+)$/, m)) {
          tok = m[2] "_" toupper(m[1]) " (" raw ")"
        } else if (match(base, /^gpu:([^:]+)$/, m2)) {
          tok = toupper(m2[1]) " (" raw ")"
        }

        if (out!="") out = out ", "
        out = out tok
      }
      return out
    }

    {
      nl   = trim(substr($0, 1, 15))
      cpus = trim(substr($0, 17, 4))
      mem  = trim(substr($0, 22, 7))
      feat = trim(substr($0, 30, 46))
      gres = trim(substr($0, 77, 18))

      printf("%s%-15s%s %-4s %-7s %-46s %s\n",
             BLUE, nl, RESET,
             cpus,
             human_mem(mem),
             feat,
             human_gres_with_raw(gres))
    }'
}

# ---- lsparts ----
lsparts() {
  local BLUE="$(_slurm_blue)"
  local RESET="$(_slurm_reset)"

  sinfo -h -o "%P|%D|%C" |
  awk -F'|' -v BLUE="$BLUE" -v RESET="$RESET" '
    {
      pname=$1; nodes=$2; c=$3
      suffix=""
      if (pname ~ /\*$/) { sub(/\*$/, "", pname); suffix=" (default)" }

      split(c, a, "/")

      printf("%s%-20s%s %4s nodes, %4s idle CPUs / %s%s\n",
             BLUE, pname, RESET,
             nodes, a[2], a[4], suffix)
    }'
}

# ---- sumjob ----
sumjob() {
  local jobid="$1"
  [[ -z "$jobid" ]] && { echo "Usage: sumjob <jobid>"; return 1; }

  local BLUE="$(_slurm_blue)"
  local RESET="$(_slurm_reset)"

  local live
  live="$(scontrol show job "$jobid" 2>/dev/null)"
  if [[ -n "$live" ]]; then
    printf '%s\n' "$live" |
    awk -v BLUE="$BLUE" -v RESET="$RESET" -v jobid="$jobid" '
      {
        for (i=1; i<=NF; i++) {
          split($i, kv, "=")
          if (kv[1] && kv[2]) v[kv[1]] = kv[2]
        }
      }
      END {
        if (!v["JobId"]) { print "Job not found:", jobid; exit }
        printf("%sJob:%s %s\n", BLUE, RESET, v["JobId"])
        for (k in v) printf("%s%s:%s %s\n", BLUE, k, RESET, v[k])
      }'
    return
  fi

  sacct -j "$jobid" -n -X \
    -o JobID,JobName%26,User,Partition,State,ExitCode,Elapsed,Timelimit,AllocCPUS,ReqMem,MaxRSS,NodeList%30
}

# ---- lastjob ----
lastjob() {
  sacct -u "$USER" -n -X -o JobID,Submit |
  awk '$1 ~ /^[0-9]+(_[0-9]+)?$/ && $2 ~ /^[0-9]{4}-/ {
         if ($2 > bestt) { bestt=$2; best=$1 }
       }
       END { if (best) print best }'
}

# ---- effjob ----
effjob() {
  local jobid="$1"
  [[ -z "$jobid" ]] && { echo "Usage: effjob <jobid>"; return 1; }

  [[ "$jobid" == "last" || "$jobid" == "lastjob" ]] && jobid="$(lastjob)"

  command -v seff >/dev/null || { echo "seff not found"; return 127; }

  seff "$jobid" |
  awk -v BLUE="$(_slurm_blue)" -v RESET="$(_slurm_reset)" '
    {
      line=$0
      if (match(line, /^[[:space:]]*[^:]+:/)) {
        label=substr(line,RSTART,RLENGTH-1)
        rest=substr(line,RLENGTH+1)
        printf "%s%s%s:%s%s\n", BLUE,label,RESET,RESET,rest
      } else print
    }'
}

# ---- sec2human ----
sec2human() {
  : "${1:?seconds required}"
  local s=$1 d h m
  (( d=s/86400, h=s/3600%24, m=s/60%60, s%=60 ))

  (( d>0 )) && printf '%dd %02dh %02dm %02ds' "$d" "$h" "$m" "$s" ||
  (( h>0 )) && printf '%02dh %02dm %02ds' "$h" "$m" "$s" ||
  (( m>0 )) && printf '%02dm %02ds' "$m" "$s" ||
               printf '%02ds' "$s"

  [[ -t 1 ]] && printf '\n'
}

