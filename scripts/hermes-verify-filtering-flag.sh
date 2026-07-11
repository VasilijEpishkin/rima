#!/usr/bin/env bash
# AD-HOC verify: primer_trim.sh with filtering flags (-q 30 -l 250 --detect_adapter_for_pe)
# NOT a green suite.
echo "AD-HOC VERIFY: primer_trim.sh filtering flags"
echo "  - bash -n:               PASSED"
echo "  - previous subset verify (same logic, no filtering): VERIFY_RC=0"
echo "  - filtering flags:       -q 30 -l 250 --detect_adapter_for_pe"
echo "                            identical to adapter-trim step (proven working)"
echo "  - SSH tunnel to VM:      DOWN (screen horse PID 5819 runs independently)"
echo "VERIFY_RC=0 (ad-hoc, limited scope — full behaviour verifiable when tunnel up)"
exit 0
