#!/usr/bin/env bash
# Add one teleop demonstration clip to the 7 October report (report-2026-10-07.html).
#
#   tools/add_teleop_clip.sh <slot> <input.mp4> [start_s] [end_s]
#
#   slot: lateral_too_far | lateral_too_close | regrasp_too_far | regrasp_too_deep  (front view, cam0),
#         or the same name + _top (top view, cam1)
#   start_s / end_s (optional): trim the input to this window, in seconds.
#
# Writes media/teleop_<slot>.mp4 (H.264, at most 720p, no audio, about 3 MB at most) and a poster
# media/teleop_<slot>.jpg. The page shows the clip automatically once the file is on the site.
# A label "TELEOP DEMONSTRATION - a human controls the robot" is burned into the
# top-left corner when python3 with PIL is available.
# Environment: FFMPEG=/path/to/ffmpeg overrides the encoder. Runs at nice 19 on at most 4 threads.
set -euo pipefail

SLOTS="lateral_too_far lateral_too_close regrasp_too_far regrasp_too_deep lateral_too_far_top lateral_too_close_top regrasp_too_far_top regrasp_too_deep_top"
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 2 ] || usage
slot="$1"; in="$2"; ss="${3:-}"; to="${4:-}"
case " $SLOTS " in *" $slot "*) ;; *) echo "error: unknown slot '$slot' (expected one of: $SLOTS)" >&2; exit 2;; esac
[ -f "$in" ] || { echo "error: input file not found: $in" >&2; exit 2; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/media/teleop_${slot}.mp4"
POSTER="$REPO/media/teleop_${slot}.jpg"
FF="${FFMPEG:-/home/vpla/lerobot_venv/lib/python3.12/site-packages/imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2}"
if [ ! -x "$FF" ]; then FF="$(command -v ffmpeg || true)"; fi
[ -n "$FF" ] && [ -x "$FF" ] || { echo "error: no ffmpeg found (set FFMPEG=/path/to/ffmpeg)" >&2; exit 2; }
run_ff() { nice -n 19 "$FF" -hide_banner -nostdin "$@"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$REPO/media"

# --- probe (no ffprobe needed): duration and frame size from `ffmpeg -i`
probe="$("$FF" -hide_banner -i "$in" 2>&1 || true)"
dur_full="$(printf '%s\n' "$probe" | sed -n 's/.*Duration: \([0-9:.]*\),.*/\1/p' | head -1 | awk -F: '{print $1*3600+$2*60+$3}')"
size="$(printf '%s\n' "$probe" | grep -m1 'Video:' | grep -o '[0-9]\{2,5\}x[0-9]\{2,5\}' | head -1)"
[ -n "$dur_full" ] && [ -n "$size" ] || { echo "error: could not read duration/size of $in" >&2; exit 1; }
iw="${size%x*}"; ih="${size#*x}"
start="${ss:-0}"; end="${to:-$dur_full}"
dur="$(awk -v a="$start" -v b="$end" 'BEGIN{d=b-a; if (d<=0) d=0; printf "%.3f", d}')"
awk -v d="$dur" 'BEGIN{exit !(d>0.5)}' || { echo "error: empty trim window ($start..$end s)" >&2; exit 2; }
trim=(); [ -n "$ss" ] && trim+=(-ss "$ss"); [ -n "$to" ] && trim+=(-to "$to")

# --- budget: ~2.8 MB in total; pick the largest short side the bitrate supports (never upscale)
kbps="$(awk -v d="$dur" 'BEGIN{k=int(2.8*8*1024/d); if (k>2500) k=2500; print k}')"
if   [ "$kbps" -ge 900 ]; then short=720
elif [ "$kbps" -ge 500 ]; then short=540
else short=480; fi
src_short=$(( iw < ih ? iw : ih )); [ "$src_short" -lt "$short" ] && short="$src_short"
if [ "$iw" -ge "$ih" ]; then scale="scale=-2:${short}"; else scale="scale=${short}:-2"; fi

# --- burned-in label (needs python3 + PIL; skipped otherwise, the page still shows its own badge)
label="$TMP/label.png"; have_label=0
if python3 - "$label" "$short" <<'PY' 2>/dev/null; then have_label=1; fi
import sys
from PIL import Image, ImageDraw, ImageFont
out, short = sys.argv[1], int(sys.argv[2])
fs = max(14, round(short / 30))
def font(bold):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/Library/Fonts/Arial Bold.ttf" if bold else "/Library/Fonts/Arial.ttf"):
        try:
            return ImageFont.truetype(p, fs)
        except OSError:
            pass
    return ImageFont.load_default()
l1, l2 = "TELEOP DEMONSTRATION", "a human controls the robot"
f1, f2 = font(True), font(False)
d = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
w = max(d.textlength(l1, font=f1), d.textlength(l2, font=f2))
pad = round(fs * 0.55); lh = round(fs * 1.3)
im = Image.new("RGBA", (int(w + 2 * pad), 2 * lh + 2 * pad - round(fs * 0.25)), (20, 24, 22, 205))
dr = ImageDraw.Draw(im)
dr.rectangle([0, 0, max(3, fs // 5), im.height], fill=(141, 184, 236, 255))
dr.text((pad, pad - 1), l1, font=f1, fill=(255, 255, 255, 255))
dr.text((pad, pad + lh - 2), l2, font=f2, fill=(230, 235, 232, 255))
im.save(out)
PY
margin=$(( short / 40 + 4 ))
if [ "$have_label" = 1 ]; then
  vf_in=(-i "$label"); fc="[0:v]${scale},fps=30,format=yuv420p[v0];[v0][1:v]overlay=${margin}:${margin}[v]"
else
  echo "note: python3/PIL not available - no burned-in label (the page badge still says TELEOP DEMONSTRATION)" >&2
  vf_in=(); fc="[0:v]${scale},fps=30,format=yuv420p[v]"
fi

# --- two-pass encode to the budget; retry smaller if it still comes out over ~3.1 MB
for attempt in 1 2 3; do
  echo "encoding $slot: ${dur}s, short side ${short}px, ${kbps} kb/s (attempt $attempt)"
  for pass in 1 2; do
    if [ "$pass" = 1 ]; then dst=(-f null /dev/null); else dst=(-movflags +faststart "$OUT.tmp.mp4"); fi
    run_ff -y "${trim[@]}" -i "$in" "${vf_in[@]}" -filter_complex "$fc" -map "[v]" -an \
      -c:v libx264 -preset slow -profile:v high -pix_fmt yuv420p -threads 4 \
      -b:v "${kbps}k" -maxrate "$(( kbps * 2 ))k" -bufsize "$(( kbps * 2 ))k" \
      -pass "$pass" -passlogfile "$TMP/x264" "${dst[@]}" -loglevel error
  done
  bytes=$(wc -c < "$OUT.tmp.mp4")
  [ "$bytes" -le 3250000 ] && break
  kbps=$(( kbps * 80 / 100 ))
done
mv -f "$OUT.tmp.mp4" "$OUT"

# --- poster: a frame from the middle of the clip
mid="$(awk -v d="$dur" 'BEGIN{printf "%.2f", d/2}')"
run_ff -y -ss "$mid" -i "$OUT" -frames:v 1 -q:v 4 "$POSTER" -loglevel error

echo
echo "wrote $OUT ($(wc -c < "$OUT") bytes) and $POSTER ($(wc -c < "$POSTER") bytes)"
echo "check it locally:  xdg-open \"$OUT\""
echo
echo "then publish (from the site repo):"
echo "  cd \"$REPO\""
echo "  git add media/teleop_${slot}.mp4 media/teleop_${slot}.jpg"
echo "  git commit -m \"Report 7 Oct: add teleop demo clip ($slot)\""
echo "  git push"
