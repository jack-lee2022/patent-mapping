# Patent Mapping Skill

A Claude Code skill that transforms a patent CSV into actionable strategy charts — assignee landscape, filing trends, country distribution, tech-effect matrix, evolution timeline, competitor radar, and more (9 charts total).

## Features

- **IPC-first classification** — tech/effect dimensions derived from IPC/CPC codes before falling back to keywords
- **Abstract enrichment** — batch-fetches full abstracts and detailed IPC codes from Google Patents detail pages (no count limit)
- **langdetect** — non-English abstracts (JP/KR/CN/RU) are detected and excluded from keyword matching to avoid garbled-text misclassification
- **Tor auto-rotation** — requests a new exit node via NEWNYM after 2 consecutive 503 responses; no manual intervention needed
- **Blue Ocean detection** — zero-count cells in the tech-effect matrix are highlighted as technology white spaces

## Installation

```powershell
# Windows (PowerShell) — run once
.\install.ps1
```

The script installs all Python dependencies, sets up Playwright Chromium (browser fallback), and configures Tor with `CookieAuthentication 1`.

**Manual dependency install:**
```bash
pip install -r requirements.txt
playwright install chromium
```

## Quick Start

```python
from scripts.google_patents_collector import GooglePatentsCollector
from scripts.advanced.abstract_enricher import enrich_csv
from scripts.advanced.visualizer import build_all_charts

# 1. Collect
col = GooglePatentsCollector(tor_enabled=True)
items = col.fetch_by_ipc("A61M11/00", max_results=200)

# 2. Enrich abstracts + IPC codes (enrich all, no cap)
enrich_csv("patents_raw.csv", "patents_enriched.csv", max_enrich=0)

# 3. Classify + generate charts
results = build_all_charts("patents_enriched.csv", "./output")
print(f"Classification rate: {results['classify_rate']}")
print(f"Blue Ocean cells: {len(results['blue_ocean'])}")
```

**CLI usage:**
```bash
# Collect by IPC
python scripts/google_patents_collector.py --ipc A61M11/00 --max 200

# Enrich abstracts
python scripts/advanced/abstract_enricher.py --csv raw.csv --out enriched.csv

# Generate all charts
python scripts/advanced/visualizer.py --csv enriched.csv --outdir ./output --enrich
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/google_patents_collector.py` | Google Patents XHR API search (keyword / IPC / assignee) + Tor auto-rotation |
| `scripts/advanced/abstract_enricher.py` | Batch-enrich patents with abstracts and IPC codes |
| `scripts/advanced/ipc_classifier.py` | IPC-prefix-first tech/effect classifier with langdetect |
| `scripts/advanced/lang_utils.py` | Language detection utility (`is_english`, `build_classification_text`) |
| `scripts/advanced/visualizer.py` | Generate 9 strategy charts (`build_all_charts()`); see `SKILL.md` for full chart reference |
| `scripts/advanced/citation_crawler.py` | Citation snowball crawling |
| `scripts/advanced/browser_renderer.py` | Playwright fallback renderer (when API is blocked) |

## Tor Setup

Add to your `torrc`:
```
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
```

`install.ps1` writes this automatically.

## Works With: Pro Patent Search

This skill accepts any CSV that contains at minimum: `publication_number`, `title`, `assignee`, `year`, `country`, `ipc`. The most common upstream source is the [pro-patent-search](https://github.com/jack-lee2022/pro-patent-search) skill.

| Scenario | Upstream source | Use this skill for |
|----------|-----------------|--------------------|
| Full pipeline | pro-patent-search (`patent_search_runner.py`) | Enrich → classify → all 9 charts |
| Existing list | Any CSV export (Espacenet, PatSnap, Derwent…) | Classify → charts directly |
| Quick map | Manual CSV | Skip enrichment, run `build_all_charts()` as-is |

**Typical end-to-end pipeline:**
```powershell
# 1. Search (pro-patent-search skill)
python patent_search_runner.py --topic "nebulizer" --outdir "D:\patent\run1"

# 2. Enrich + map (this skill) — --enrich fetches missing abstracts automatically
python scripts/advanced/visualizer.py `
    --csv "D:\patent\run1\nebulizer_Patent_List.csv" `
    --outdir "D:\patent\run1\charts" `
    --enrich
```

The `--enrich` flag triggers `abstract_enricher.py` to fill missing abstracts and IPC codes before classification. Omit it if the CSV is already fully enriched.

## Skill SOP

See `SKILL.md` for the full four-phase analysis SOP (data cleaning → macro trends → tech-effect matrix → citation network).
