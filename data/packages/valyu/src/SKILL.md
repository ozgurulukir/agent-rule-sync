# valyu

Real-time web search and specialized data access skill for AI coding agents.

## Overview

Valyu connects AI coding agents to 36+ specialized data sources through a single API. It enables agents to access current, authoritative, paywalled information instead of relying on cached training data.

## Supported Data Sources

| Domain | Sources |
|---|---|
| Finance | SEC 10-K/10-Q filings, FRED economic indicators, BLS data |
| Biomedical | PubMed, ChEMBL (2.5M bioactive compounds), ClinicalTrials.gov |
| Legal | Patent databases, SEC regulatory filings |
| Academic | Academic publishers, research papers |
| General | Quality web search across indexed sources |

## Installation

```bash
npx skills add valyuAI/skills --skill valyu-best-practices
```

## Prerequisites

- Valyu API key (set as environment variable `VALYU_API_KEY`)

## Key Capabilities

### Targeted Search

Query specific data sources by name:

```python
from valyu import Valyu
client = Valyu(api_key="your-key")

# SEC filings search
result = client.search(
    query="risk factors disclosed in latest 10-K filings for semiconductor companies",
    search_type="proprietary",
    included_sources=["valyu/valyu-sec-filings"],
    max_num_results=5
)

# Biomedical cross-source search
result = client.search(
    query="GLP-1 receptor agonists drug interactions clinical trial outcomes",
    search_type="all",
    included_sources=[
        "valyu/valyu-pubmed",
        "valyu/valyu-chembl",
        "valyu/valyu-clinical-trials"
    ],
    max_num_results=10
)
```

### Answer API (Grounded Response)

Use the Answer API for direct cited responses:

```python
answer = client.context(
    query="What were the key risk factors disclosed by NVIDIA in their most recent 10-K?",
    search_type="proprietary"
)
```

## Performance

- FreshQA benchmark: **79%** (Google: 39%, Exa: 24%)
- Finance queries: **73%** (Google: 55%)
- MedAgent benchmark: **48%** on complex medical queries

## Best Practices

1. Be specific about which data sources you need — use `included_sources` to target
2. Use the Answer API (`context()`) when you need a grounded, cited response
3. Always surface sources to users — citations are the trust layer
4. Use `search_type="proprietary"` for specialized sources, `search_type="all"` for broad

## Available Sources

View full source list with `valyu sources list` or at https://docs.valyu.ai/sources
