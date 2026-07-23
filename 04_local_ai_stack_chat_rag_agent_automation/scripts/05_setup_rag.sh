#!/usr/bin/env bash
# RAG layer (video chapter 4:49): fetch the pinned sample document and print
# the exact AnythingLLM UI steps. The video used the author's own research
# papers and asked "What is a Swin Transformer?", so this package stages the
# Swin Transformer paper as a fixed, verifiable stand-in.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_command curl
require_command sha256sum
prepare_results

mkdir -p "$RAG_DOCS_DIR"
pdf_path="$RAG_DOCS_DIR/$SWIN_PDF_FILE"

if [[ ! -f "$pdf_path" ]]; then
  printf 'Downloading pinned sample document %s...\n' "$SWIN_PDF_FILE"
  curl --fail --location --max-time 120 -o "$pdf_path" "$SWIN_PDF_URL"
fi

actual_sha256="$(sha256sum "$pdf_path" | cut -d ' ' -f 1)"
if [[ "$actual_sha256" == "$SWIN_PDF_SHA256" ]]; then
  printf 'PASS: sample document SHA-256 matches (verified pin from 2026-07-22).\n'
else
  # arXiv can regenerate PDFs, which changes bytes without changing content.
  printf 'WARN: SHA-256 mismatch\nexpected: %s\nactual:   %s\n' "$SWIN_PDF_SHA256" "$actual_sha256" >&2
  printf 'WARN: arXiv sometimes regenerates PDFs; verify the document is the Swin Transformer paper.\n' >&2
fi
du -h "$pdf_path"

cat <<EOF

RAG document staged: $pdf_path

AnythingLLM UI steps (video chapter 4:49), validation checkpoints in GUIDE.md:
  1. Settings -> AI Providers -> Vector Database: keep the default LanceDB.
  2. Settings -> AI Providers -> Embedder: keep the default AnythingLLM embedder
     (first use downloads a small embedding model inside the container).
  3. In the workspace, click the upload button and upload:
     $pdf_path
  4. Wait until the document shows as embedded, then move it into the workspace.
  5. Workspace settings -> Chat Settings -> Chat mode: "chat" (the video
     switched modes so answers come from the documents; use "query" for
     stricter document-only answers).
  6. Ask: "What is a Swin Transformer?"
  7. Success: the answer describes a hierarchical vision Transformer with
     shifted windows AND cites $SWIN_PDF_FILE as the source document.
EOF
