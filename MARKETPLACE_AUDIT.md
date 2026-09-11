# Marketplace gap audit

Audit of the Railway Marketplace for an existing SplitPro (or equivalent shared-expense) template.
Rerun immediately before publication; results are recorded in the "Re-audit" section.

- **Audit timestamp (UTC):** 2026-09-11T14:44:00Z (initial), see below for the pre-publication rerun
- **Tool:** `npx -y @railway/cli@latest templates search "<query>" --json --limit 50` (Railway CLI 5.52.1)
- **Secondary:** web search for `site:railway.com/deploy` plus product name and aliases

## Queries and results

| # | Query | Class | Result |
|---|---|---|---|
| 1 | `splitpro` | exact product name | 0 results |
| 2 | `split-pro` | repository name | 2 unrelated results (Plane, Stirling-PDF, matched on the word "split") |
| 3 | `splitwise` | commercial product replaced | 0 results |
| 4 | `shared expenses` | generic need | 0 results |
| 5 | `expense sharing` | generic need | 0 results |
| 6 | `split expenses` | generic need | 0 results |
| 7 | `bill splitting` | generic need | 0 results |
| 8 | `group expenses` | generic need | 0 results |
| 9 | `expense` | broad category | 6 results, none are shared-expense apps (see below) |
| 10 | `spliit` | adjacent OSS project | 0 results |
| 11 | `cospend` | adjacent OSS project | 0 results |
| 12 | `tricount` | commercial alias | 0 results |
| 13 | `settle up` | commercial alias / generic | 0 results |
| 14 | `roommate` | generic need | 0 results |
| 15 | `split bills` | generic need | 0 results |

### Adjacent matches inspected (query 9, `expense`)

| Template | Code | Deploys | What it is | Overlap |
|---|---|---|---|---|
| Hammond | `hammond` | 0 | vehicle expense tracking | none (single-user vehicle costs) |
| Paisa | `paisa` | 0 | personal finance / ledger | none (personal budgeting) |
| Akaunting | `akaunting-railway` | 0 | accounting software | none (business accounting) |
| ideal-vision | `NEJ3se` | 1 | income/expense balance manager | none (personal budgeting) |
| money-matter | `money-matter` | 1 | balances and transactions tracker | none (personal budgeting) |
| Invoice Ninja | `invoice-ninja` | 9 | invoicing | none |

None of these lets a group of people record who paid what and settle debts between members, which
is SplitPro's purpose.

### Web search

`site:railway.com/deploy splitpro OR splitwise OR "split expenses"` returned no railway.com/deploy
pages. Results were SplitPro's own site, GitHub, Docker Hub, TrueNAS catalog, and comparison sites.

## Conclusion (initial audit)

**Clean gap.** No exact, alias, or generic-need match exists for a self-hosted shared-expense /
Splitwise-alternative template. Proceeding with SplitPro.

## Re-audit before publication

_To be filled in immediately before `railway templates publish`._
