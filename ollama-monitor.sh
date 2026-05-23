#!/usr/bin/env bash
set -Eeuo pipefail

INTERVAL="${INTERVAL:-3}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-monitor}"
TEMP_WARN="${TEMP_WARN:-83}"
TEMP_SPIKE="${TEMP_SPIKE:-8}"
PWR_SPIKE="${PWR_SPIKE:-80}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
CSV="$OUT_DIR/gpu-$RUN_ID.csv"
REPORT="$OUT_DIR/report-$RUN_ID.md"
mkdir -p "$OUT_DIR"

BASE_Q="timestamp,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw"
FULL_Q="$BASE_Q,clocks.gr,clocks.mem"
QUERY="$FULL_Q"; EXTRA=""
if ! nvidia-smi --query-gpu="$QUERY" --format=csv,noheader,nounits >/dev/null 2>&1; then
  QUERY="$BASE_Q"; EXTRA=",,"
  nvidia-smi --query-gpu="$QUERY" --format=csv,noheader,nounits >/dev/null
fi
echo "timestamp,name,temp_c,gpu_util_pct,mem_util_pct,vram_used_mib,vram_total_mib,power_w,graphics_clock_mhz,mem_clock_mhz" > "$CSV"

make_report() {
  {
    echo "# Ollama GPU Monitor Report"
    echo "- run_id: $RUN_ID"
    echo "- csv: $CSV"
    echo "- interval_sec: $INTERVAL"
    echo "- temp_warn_c: $TEMP_WARN"
    echo "- temp_spike_c: $TEMP_SPIKE"
    echo "- power_spike_w: $PWR_SPIKE"
    echo
    echo "## System snapshot"
    echo '```text'
    date -Is; uname -a
    command -v lsb_release >/dev/null && lsb_release -ds || true
    nvidia-smi -L || true
    echo; echo "Ollama processes:"; pgrep -a ollama || true
    echo; echo "Ollama loaded models:"; ollama ps 2>/dev/null || true
    echo '```'
    echo
    awk -F',' -v int="$INTERVAL" -v tw="$TEMP_WARN" -v tsg="$TEMP_SPIKE" -v psg="$PWR_SPIKE" '
      function trim(s){gsub(/^[ \t]+|[ \t]+$/,"",s); return s}
      function none(x){return (x=="" ? "none" : x)}
      NR==1 {next}
      NF>=8 {
        ts=trim($1); temp=$3+0; gpu=$4+0; mem=$5+0; vram=$6+0; pwr=$8+0; cg=$9+0; cm=$10+0
        n++
        if(n==1){first=ts; mint=maxt=temp; minp=maxp=pwr; minu=maxu=gpu; minv=maxv=vram; maxmem=mem; maxcg=cg; maxcm=cm; maxts=maxpts=maxuts=maxvts=ts}
        last=ts; sumt+=temp; sump+=pwr; sumu+=gpu; summ+=mem; sumv+=vram; sumcg+=cg; sumcm+=cm
        if(temp<mint) mint=temp; if(temp>maxt){maxt=temp; maxts=ts}
        if(pwr<minp) minp=pwr; if(pwr>maxp){maxp=pwr; maxpts=ts}
        if(gpu<minu) minu=gpu; if(gpu>maxu){maxu=gpu; maxuts=ts}
        if(vram<minv) minv=vram; if(vram>maxv){maxv=vram; maxvts=ts}
        if(mem>maxmem) maxmem=mem; if(cg>maxcg) maxcg=cg; if(cm>maxcm) maxcm=cm
        if(temp>=tw && ht<20) hight[++ht]=ts " temp=" temp "C gpu=" gpu "% power=" pwr "W"
        if(gpu>=90) highu++; if(temp>=tw) hott++; if(gpu<20 && pwr>150) inefficient++
        if(prev!=""){
          dt=temp-prev_t; dp=pwr-prev_p
          if(dt>=tsg && tc<20) tsp[++tc]=prev " -> " ts " +" dt "C (" prev_t "C -> " temp "C)"
          if(dp>=psg && pc<20) psp[++pc]=prev " -> " ts " +" dp "W (" prev_p "W -> " pwr "W)"
        }
        prev=ts; prev_t=temp; prev_p=pwr
      }
      END {
        if(n==0){print "## Summary\nNo GPU samples captured."; exit}
        printf "## Summary\n- samples: %d\n- approx_duration_sec: %d\n- first_sample: %s\n- last_sample: %s\n", n,n*int,first,last
        printf "- gpu_util_avg_pct: %.1f; max: %.0f at %s\n", sumu/n,maxu,none(maxuts)
        printf "- temp_avg_c: %.1f; min/max: %.0f/%.0f; max_at: %s\n", sumt/n,mint,maxt,none(maxts)
        printf "- power_avg_w: %.1f; min/max: %.1f/%.1f; max_at: %s\n", sump/n,minp,maxp,none(maxpts)
        printf "- vram_avg_mib: %.0f; min/max: %.0f/%.0f; max_at: %s\n", sumv/n,minv,maxv,none(maxvts)
        printf "- mem_controller_util_avg_pct: %.1f; max: %.0f\n", summ/n,maxmem
        if(sumcg>0) printf "- graphics_clock_avg_mhz: %.0f; max: %.0f\n", sumcg/n,maxcg
        if(sumcm>0) printf "- memory_clock_avg_mhz: %.0f; max: %.0f\n", sumcm/n,maxcm
        printf "- hot_samples_ge_warn: %d/%d\n- high_gpu_util_samples_ge_90pct: %d/%d\n- low_util_high_power_samples: %d/%d\n", hott,n,highu,n,inefficient,n
        print "\n## Temperature warning samples"; if(ht==0) print "- none"; else for(i=1;i<=ht;i++) print "- " hight[i]
        print "\n## Temperature spikes"; if(tc==0) print "- none"; else for(i=1;i<=tc;i++) print "- " tsp[i]
        print "\n## Power spikes"; if(pc==0) print "- none"; else for(i=1;i<=pc;i++) print "- " psp[i]
      }' "$CSV"
    echo; echo "## Raw CSV tail"; echo '```csv'; tail -n 20 "$CSV"; echo '```'
  } > "$REPORT"
  echo "Report: $REPORT"; echo "CSV:    $CSV"
}
trap 'echo; echo "Stopping monitor..."; make_report; exit 0' INT TERM
echo "Monitoring GPU every ${INTERVAL}s. Press Ctrl+C to stop."; echo "CSV: $CSV"
while true; do
  nvidia-smi --query-gpu="$QUERY" --format=csv,noheader,nounits |
    while IFS= read -r row; do echo "$row$EXTRA" >> "$CSV"; done
  sleep "$INTERVAL"
done