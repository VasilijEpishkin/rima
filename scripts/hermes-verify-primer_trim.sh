#!/usr/bin/env bash
# hermes-verify-primer_trim.sh — AD-HOC verification of OPTIMIZED parallel primer_trim.sh
# (NOT a green suite). Runs the REAL script on a 50k-read subset of one horse pair,
# in an isolated temp tree. Confirms: MaskPrimers align + cutadapt + fastp + fastqc
# all produce real outputs under the new parallel (xargs -P) structure.
set -e
export PATH=~/.local/bin:$PATH

DS=PRJNA848968
BASE=SRR19646177
WORK=/tmp/verify_primer6
rm -rf "$WORK"
mkdir -p "$WORK/trim" "$WORK/out/fastq" "$WORK/out/fastp_reports" "$WORK/out/fastqc"

# подвыборка с ТЕМ ЖЕ расширением, что в проде (*.trim.fastq.gz)
zcat /tmp/sub_1.fastq.gz 2>/dev/null | gzip > "$WORK/trim/${BASE}_1.trim.fastq.gz"
zcat /tmp/sub_1.fastq.gz 2>/dev/null | gzip > "$WORK/trim/${BASE}_2.trim.fastq.gz"

# copy real script, repoint TRIM_SRC + OUT to temp
cp ~/primer_trim.sh "$WORK/pt_test.sh"
sed -i "s|TRIM_SRC=~/results/qc_trim_pipeline/\${DS}/trim|TRIM_SRC=$WORK/trim|" "$WORK/pt_test.sh"
sed -i "s|OUT=\${REPO}/pr_trimmed|OUT=$WORK/out|" "$WORK/pt_test.sh"

bash "$WORK/pt_test.sh" "$DS"

echo "=== VERIFY ==="
RC=0
for d in fastq fastp_reports fastqc; do
  n=$(ls "$WORK/out/$d" 2>/dev/null | wc -l); echo "$d: $n files"; [ "$n" -gt 0 ] || RC=1
done
M1=$WORK/out/fastq/${BASE}_1.pr.fastq.gz
if [ -s "$M1" ] && zcat "$M1" 2>/dev/null | head -1 | grep -q "@"; then echo "final pr read: OK"; else echo "final pr read: EMPTY"; RC=1; fi
if ls "$WORK/out/fastqc"/*.html >/dev/null 2>&1; then echo "FastQC html: OK"; else echo "FastQC html: MISSING"; RC=1; fi
if [ -s "$WORK/out/fastp_reports/${BASE}.json" ]; then echo "fastp json: OK"; else echo "fastp json: MISSING"; RC=1; fi
if [ -s "$WORK/out/fastp_reports/${BASE}.cutadapt.log" ]; then echo "cutadapt log: OK"; else echo "cutadapt log: MISSING"; RC=1; fi
echo "VERIFY_RC=$RC"
exit $RC
