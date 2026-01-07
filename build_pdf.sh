#!/usr/bin/env bash
set -euo pipefail

# Build a single "book-like" PDF from law??.md files using pandoc.
# It generates `__book__.md` (one chapter per input file) and inserts `\newpage`
# between chapters so each chapter starts on a new page in the PDF.
# Usage:
#   bash build_pdf.sh                 # uses law??.md in order
#   bash build_pdf.sh law31.md law32.md
#
# Default ordering:
# - If README.md contains `- [lawXX.md](lawXX.md)` links, it follows that order.
# - Otherwise it falls back to lexicographic `law??.md` order (law01..law48).
#
# Optional README category headings:
# - If `BOOK_INCLUDE_CATEGORIES=1`, it also inserts README `### ...` headings
#   (as top-level sections) and demotes each law's first `#` heading to `##`
#   when stitching the book, so the PDF structure becomes:
#     Category (H1) → Law (H2)
#
# Optional env vars (Windows defaults):
#   OUT="权力48法则.pdf"
#   CJK_MAINFONT="SimSun"
#   CJK_SANSFONT="Microsoft YaHei"
#   CJK_MONOFONT="Consolas"
#   FONTSIZE="12pt"                  # e.g. 11pt/12pt
#   MD_HARD_LINE_BREAKS=1            # treat single newlines as hard breaks
#   BOOK_INCLUDE_CATEGORIES=1        # include README category headings

OUT="${OUT:-权力48法则byGPT5.pdf}"
CJK_MAINFONT="${CJK_MAINFONT:-SimSun}"
CJK_SANSFONT="${CJK_SANSFONT:-Microsoft YaHei}"
CJK_MONOFONT="${CJK_MONOFONT:-Consolas}"
FONTSIZE="${FONTSIZE:-12pt}"
HEADER_TEX="${HEADER_TEX:-pandoc_header.tex}"

if ! command -v pandoc >/dev/null 2>&1; then
  echo "Error: pandoc not found in PATH." >&2
  exit 1
fi

if ! command -v xelatex >/dev/null 2>&1; then
  echo "Error: xelatex not found in PATH (install TeX Live/MiKTeX with XeLaTeX)." >&2
  exit 1
fi

inputs=("$@")
include_categories="${BOOK_INCLUDE_CATEGORIES:-0}"

if [ "${#inputs[@]}" -eq 0 ]; then
  if [ -f README.md ]; then
    if [ "$include_categories" = "1" ]; then
      mapfile -t inputs < <(
        awk '
          /^## 索引/ {in_index=1; next}
          in_index && /^## / {exit}
          in_index && /^### / {print "CAT|" substr($0, 5); next}
          in_index && /^- \[law[0-9][0-9]\.md\]/ {
            if (match($0, /^- \[(law[0-9][0-9]\.md)\]/, m)) print "FILE|" m[1]
          }
        ' README.md \
          | awk '!seen[$0]++'
      )
    else
      mapfile -t inputs < <(
        sed -n 's/^- \[\(law[0-9][0-9]\.md\)\].*/\1/p' README.md \
          | awk '!seen[$0]++'
      )
    fi
  fi
  if [ "${#inputs[@]}" -eq 0 ]; then
    mapfile -t inputs < <(ls -1 law??.md 2>/dev/null | LC_ALL=C sort)
  fi
fi

if [ "${#inputs[@]}" -eq 0 ]; then
  echo "Error: no input files found (expected law??.md)." >&2
  exit 1
fi

tmp_md="__book__.md"

: >"$tmp_md"
for item in "${inputs[@]}"; do
  if [ "$include_categories" = "1" ] && [[ "$item" == CAT\|* ]]; then
    printf '# %s\n\n' "${item#CAT|}" >>"$tmp_md"
    continue
  fi

  f="$item"
  if [ "$include_categories" = "1" ] && [[ "$item" == FILE\|* ]]; then
    f="${item#FILE|}"
  fi

  if [ ! -f "$f" ]; then
    echo "Error: missing file: $f" >&2
    exit 1
  fi

  if [ "$include_categories" = "1" ]; then
    # Demote all headings by 1 level so the structure becomes:
    #   Category (H1) → Law (H2) → Sections (H3)
    # Also avoid touching headings inside fenced code blocks.
    awk '
      BEGIN { in_code = 0 }
      /^```/ { in_code = !in_code; print; next }
      !in_code && /^#+[[:space:]]/ { sub(/^#/, "##"); print; next }
      { print }
    ' "$f" >>"$tmp_md"
  else
    cat "$f" >>"$tmp_md"
  fi

  # NOTE: bash printf treats "\n" as newline escape, so "\newpage" would become "ewpage".
  # We must escape the backslash so the output is literally "\newpage".
  printf '\n\n\\newpage\n\n' >>"$tmp_md"
done

md_format="markdown+raw_tex"
if [ "${MD_HARD_LINE_BREAKS:-0}" = "1" ]; then
  md_format="markdown+raw_tex+hard_line_breaks"
fi

pandoc "$tmp_md" \
  -f "$md_format" \
  -o "$OUT" \
	--toc --toc-depth=$([ "$include_categories" = "1" ] && echo 2 || echo 1) \
	--include-in-header="$HEADER_TEX" \
	--pdf-engine=xelatex \
	-V fontsize="$FONTSIZE" \
	-V geometry:margin=2.2cm \
	-V papersize=a4 \
	-V linestretch=1.25 \
	-V CJKmainfont="$CJK_MAINFONT" \
  -V CJKsansfont="$CJK_SANSFONT" \
  -V CJKmonofont="$CJK_MONOFONT"

echo "OK: wrote $OUT"
