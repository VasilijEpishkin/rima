# VM — команды проверки и копирования отчётов (OneQ Jupyter)

Хост Jupyter (внутренний, проксируется OneQ):
`http://task-41999da8-68f2-476f-8063-73694c2e04f3-zswtx:8888/?token=41999da8-68f2-476f-8063-73694c2e04f3`

Root Jupyter (куда копируем отчёты, чтобы открыть по URL):
`/data/user/epishkin/one-q/41999da8-68f2-476f-8063-73694c2e04f3/`

Фронт OneQ (открывать отчёты через него):
`https://one-q.biocad.ru/task/41999da8-68f2-476f-8063-73694c2e04f3/jupyter/files/<имя>.html`

Датасеты: PRJEB40348 (human), PRJNA848968 (horse), PRJNA1247978 (macaque), PRJNA900592 (sheep).

Меняй `DS` на нужный датасет в командах ниже.

---

## 1. Проверка: есть ли QC до и после тримминга

Проверяет наличие multiqc-отчёта для raw и для trimmed:

```
echo "=== QC raw ==="; ls /data/user/epishkin/results/DS/qc_raw/multiqc/*.html 2>&1; echo "=== QC trimmed ==="; ls /data/user/epishkin/results/DS/qc_trimmed/multiqc/*.html 2>&1
```

Замени `DS` на датасет, например `PRJEB40348`. Если папки/файла нет — 404 / "No such file".

---

## 2. Проверка: сколько trim-файлов реально сделано

```
echo "trim-файлов:"; ls /data/user/epishkin/results/DS/trimmed/fastq/*.trim.fastq.gz 2>/dev/null | wc -l; echo "raw пар:"; ls /data/user/epishkin/raw/DS/*_1.fastq.gz 2>/dev/null | wc -l
```

Сырьё лежит в `/data/user/epishkin/raw/DS/` (НЕ в results/.../raw/).
trim-файлы в `/data/user/epishkin/results/DS/trimmed/fastq/`.
Если trim-файлов меньше, чем raw-пар ×2 — тримминг недопрогнался, перезапусти ячейку adapter_trim (skip-логика докинет остальное).

---

## 3. Проверка: сколько ридов выкинул fastp (фильтрация сработала?)

```
python3 -c "import json,glob; f=sorted(glob.glob('/data/user/epishkin/results/DS/trimmed/fastp_reports/*.json')); d=json.load(open(f[0])); print('before',d['summary']['before_filtering']['total_reads']); print('after',d['summary']['after_filtering']['total_reads']); print('too_short',d['filtering_result']['too_short_readq']); print('low_qual',d['filtering_result']['low_quality_reads'])"
```

Покажет before/after и сколько выкинуто too_short (<250) и low_qual (Q<30).

---

## 4. Копирование multiqc-отчётов в root Jupyter (чтобы открыть по URL)

Копируй ТОЛЬКО те отчёты, что реально существуют (см. пункт 1).
Одна строка на датасет, через `;` (если файла нет — пропустит с ошибкой, остальные скопируются):

human (PRJEB40348) — raw + trimmed:
```
cp /data/user/epishkin/results/PRJEB40348/qc_raw/multiqc/PRJEB40348_raw_multiqc.html /data/user/epishkin/one-q/41999da8-68f2-476f-8063-73694c2e04f3/ ; cp /data/user/epishkin/results/PRJEB40348/qc_trimmed/multiqc/PRJEB40348_trimmed_multiqc.html /data/user/epishkin/one-q/41999da8-68f2-476f-8063-73694c2e04f3/
```

horse (PRJNA848968) — raw + trimmed:
```
cp /data/user/epishkin/results/PRJNA848968/qc_raw/multiqc/PRJNA848968_raw_multiqc.html /data/user/epishkin/one-q/41999da8-68f2-476f-8063-73694c2e04f3/ ; cp /data/user/epishkin/results/PRJNA848968/qc_trimmed/multiqc/PRJNA848968_trimmed_multiqc.html /data/user/epishkin/one-q/41999da8-68f2-476f-8063-73694c2e04f3/
```

После копирования проверь, что легли:
```
ls /data/user/epishkin/one-q/41999da8-68f2-476f-8063-73694c2e04f3/*.html
```

---

## 5. Ссылки на отчёты (открывать в браузере через OneQ)

Шаблон: `https://one-q.biocad.ru/task/41999da8-68f2-476f-8063-73694c2e04f3/jupyter/files/<имя>.html`

Готовые (для тех, что уже готовы и скопированы):
- human до:     `.../jupyter/files/PRJEB40348_raw_multiqc.html`
- human после:  `.../jupyter/files/PRJEB40348_trimmed_multiqc.html`
- horse до:     `.../jupyter/files/PRJNA848968_raw_multiqc.html`
- horse после:  `.../jupyter/files/PRJNA848968_trimmed_multiqc.html`

(вместо `...` подставь `https://one-q.biocad.ru/task/41999da8-68f2-476f-8063-73694c2e04f3`)

---

## Примечания
- Jupyter видит ТОЛЬКО папку `one-q/41999da8.../`. Файлы в `results/` для него — за пределами root → 404. Поэтому копируем html туда.
- Имя html точное: `<DS>_raw_multiqc.html` и `<DS>_trimmed_multiqc.html` (из qc.ipynb, флаг `-n`).
- Копия, не перемещение: оригиналы в `results/.../multiqc/` остаются.
- Команды без pipe, однострочные (через `;` или `&&`), чтобы bash не рвал при вставке.
- macaque (PRJNA1247978) и sheep (PRJNA900592): trimmed ещё не готов → отчётов qc_trimmed нет, копировать нечего пока.
