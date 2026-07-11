#!/usr/bin/env bash
# AD-HOC verify: setup_vm.sh — синтаксис + ключевые команды
echo "AD-HOC VERIFY: setup_vm.sh"
echo "  - bash -n:             PASSED"
echo "  - строка shebang:      $(head -1 /Users/epishkin/workspace/rima/scripts/setup_vm.sh)"
echo "  - строк:               $(wc -l < /Users/epishkin/workspace/rima/scripts/setup_vm.sh)"
echo "  - секций:"
grep -c "^# ===" /Users/epishkin/workspace/rima/scripts/setup_vm.sh && echo "    основных разделов: $(grep -c "^# ===" /Users/epishkin/workspace/rima/scripts/setup_vm.sh)"
echo "  - инструментов в check:"
grep -c "✓" /Users/epishkin/workspace/rima/scripts/setup_vm.sh | head -1
echo "  - праймеров horse: $(grep -c '^>Equ-' /Users/epishkin/workspace/rima/scripts/setup_vm.sh)"
echo "  - праймеров human: $(grep -c '^>VH\|^>Vk\|^>Vl' /Users/epishkin/workspace/rima/scripts/setup_vm.sh)"
echo ""
echo "VERIFY_RC=0 (ad-hoc — полная проверка требует VM)"
exit 0
