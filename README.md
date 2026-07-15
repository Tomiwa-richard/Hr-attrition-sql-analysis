# HR Attrition SQL Analysis

A data-driven MySQL investigation into employee attrition patterns, built to support strategic retention decisions for an HR executive audience.

---

## Project Overview

The Chief Human Resources Officer (CHRO) of a mid-size organisation raised concerns about employee attrition heading into year-end. She needed to understand **who is leaving, from where, and why** — so that a limited retention budget could be directed at the right departments and root causes rather than applied uniformly.

This project works through **five targeted business questions** using MySQL, moving from broad department-level attrition rates down to salary comparisons between leavers and stayers at the job-role level. The dataset is a realistic simulated HR database (~750 employees, 8 departments) with intentional messiness built in to mirror real-world data quality challenges.

> **Note:** This is a practice project built to demonstrate the full SQL analytics workflow — data audit, cleaning, view creation, and business analysis. The dataset is synthetic; findings are illustrative of real analytical patterns.

---

## Repository Structure

```
Hr-attrition-sql-analysis/
│
├── sql/
│   ├── hr_attrition_project_schema.sql   # Database schema + raw data (CREATE + INSERT)
│   ├── data_cleaning_views.sql           # Data quality audit + clean views
│   ├── analysis_queries.sql              # All 5 business question queries + findings
│   └── full_project_setup.sql            # Full end-to-end file (schema + cleaning + analysis)
│
├── output/
│   └── HR_Attrition_Case_Study.pdf       # Stakeholder-facing case study report
│
└── README.md
```

---

## Dataset

| Table | Rows | Description |
|---|---|---|
| `employees` | 761 (raw) | Employee records — name, department, role, hire date, performance rating, status |
| `departments` | 8 | Department reference table |
| `salary_history` | 3,049 | Historical salary entries per employee (multiple raises over time) |
| `attrition` | 115 | Exit records for terminated employees — exit type, date, and reason |

**Departments:** Sales, Engineering, Marketing, Human Resources, Finance, Customer Support, Operations, Legal

---

## Data Quality Issues Found & Resolved

The raw dataset contained the following intentional quality issues, identified during the audit phase before any analysis:

| Issue | Detail | Resolution |
|---|---|---|
| Inconsistent `job_role` casing | Same roles stored as `'HR Manager'`, `'HR MANAGER'`, `'hr manager '` | `LOWER(TRIM())` applied in clean view |
| Orphaned `department_id` | ~2% of rows pointed to `dept_id = 99` (non-existent in departments table) | Inferred correct dept from proven 1-to-1 job_role mapping |
| NULL `department_id` | ~3% of employees had no department recorded | Same inference approach as orphaned FK rows |
| Duplicate employee rows | Same person entered twice with different `employee_id` | `ROW_NUMBER()` deduplication — kept earliest ID |
| NULL `performance_rating` | ~4% of employees unrated | Kept in view; excluded only from Q3 (performance analysis) |
| Bad salary values | 60 rows with negative, zero, or NULL `salary_amount` | Excluded from `salary_clean` view |
| Fully NULL garbage row | One row with every column NULL including `employee_id` | Excluded via `WHERE employee_id IS NOT NULL` |
| Missing attrition records | 3 terminated employees had no row in attrition table | Accepted as irrecoverable data gap; noted in analysis |

### Cleaning Approach

Two SQL views were created rather than modifying the source tables:

- **`employees_clean`** — handles deduplication, department recovery, and job_role standardization
- **`salary_clean`** — excludes invalid salary entries

All subsequent business queries run on these views. The raw tables remain intact.

---

## Business Questions & Key Findings

### Q1 — Which departments have the highest attrition rate?

| Department | Employees | Leavers | Attrition Rate |
|---|---|---|---|
| Sales | 85 | 18 | **21.18%** |
| Human Resources | 98 | 17 | 17.35% |
| Operations | 86 | 14 | 16.28% |
| Engineering | 88 | 14 | 15.91% |
| Legal | 101 | 16 | 15.84% |
| Finance | 97 | 13 | 13.40% |
| Customer Support | 98 | 13 | 13.27% |
| Marketing | 97 | 9 | **9.28%** |

**Finding:** Sales has the highest attrition at 21.2% — approximately 1 in 5 employees left. Marketing has the lowest at 9.3%. Department-level rates vary significantly, confirming that company-wide averages mask very different retention realities across teams.

---

### Q2 — Is attrition voluntary or involuntary, and does the split vary by department?

*Voluntary = employee chose to leave. Involuntary = company decision (fired, restructured).*

**Key finding:** Human Resources has the highest voluntary attrition (14.3%) — employees are actively choosing to leave, pointing to internal dissatisfaction. Sales is uniquely problematic: high rates on both sides simultaneously (12.9% voluntary + 8.2% involuntary), suggesting a department under stress from multiple directions at once.

> **Analytical note:** A CTE was required to fix the department headcount denominator before splitting by `exit_type`. Without this, `GROUP BY exit_type` scopes `COUNT(e.employee_id)` to each exit group and produces 100% attrition rates — a silent error that runs without warning.

---

### Q3 — Are high performers leaving at a higher rate than low performers?

| Performance Rating | Employees | Leavers | Attrition Rate |
|---|---|---|---|
| 5 — Exceptional | 97 | 19 | **19.59%** |
| 4 — Strong | 215 | 33 | 15.35% |
| 3 — Average | 297 | 43 | 14.48% |
| 2 — Below Average | 74 | 11 | 14.86% |
| 1 — Poor | 37 | 5 | **13.51%** |

**Critical finding:** Top performers (rating 5) have the **highest** attrition rate at 19.6%, while the lowest performers are the most stable at 13.5%. The organisation is retaining its weakest employees while losing its best — a pattern that degrades the talent base over time and requires immediate investigation.

---

### Q4 — What is the salary gap between leavers and stayers within the same job role?

Uses the most recent salary per employee (via `ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY effective_date DESC)`). `CASE WHEN` inside `AVG()` pivots leavers and stayers into separate columns on the same row.

*Positive gap = stayers earn more than leavers did. Negative gap = leavers were earning more than current stayers.*

**Finding:** Most roles show a **negative salary gap** — leavers were earning more than the stayers who remained in the same role. This rules out pay as the primary attrition driver for high-exit roles like Sales and Operations. Root causes are likely non-monetary: management quality, career growth ceiling, or burnout. Roles with a positive gap (Account Manager, Marketing Manager) suggest those leavers may have felt underpaid relative to peers.

---

### Q5 — Which departments have the longest average tenure before employees leave?

| Department | Avg Tenure Before Leaving |
|---|---|
| Finance | 2.37 years |
| Legal | 2.66 years |
| Sales | 2.80 years |
| Customer Support | 3.13 years |
| Marketing | 3.32 years |
| Human Resources | 3.42 years |
| Operations | 3.44 years |
| Engineering | **3.91 years** |

**Finding:** Finance and Legal employees leave after only 2.4–2.7 years — the shortest tenure in the organisation. The company is losing people before they reach full productivity. Engineering retains leavers the longest (3.9 years), suggesting stronger engagement or more complex career decisions in technical roles.

---

## Recommendations

| Priority | Department / Area | Recommendation |
|---|---|---|
| 🔴 Urgent | Sales | Investigate management structure and target-setting. High voluntary + involuntary attrition with leavers earning more than stayers rules out pay as the fix — this is a leadership and culture problem. |
| 🔴 Urgent | All departments | Address top-performer flight risk. Rating-5 employees are leaving at 19.6% — the highest of any group. Audit promotion pathways and recognition programmes immediately. |
| 🟡 Important | Human Resources | HR has the highest voluntary attrition (14.3%) — a department that exists to retain others is struggling to retain its own people. Conduct anonymous pulse surveys and review team management. |
| 🟡 Important | Finance & Legal | Short average tenure (2.4–2.7 years) suggests early disillusionment. Introduce structured 18-month check-ins and clearer career progression frameworks. |
| 🟢 Monitor | Marketing | Lowest attrition rate (9.3%). Document what Marketing is doing differently and use it as a benchmark for struggling departments. |

---

## Tools Used

- **MySQL / MySQL Workbench** — data cleaning, view creation, and all analysis queries
- **Python (ReportLab)** — stakeholder-facing PDF case study generation

---

## Skills Demonstrated

- Relational database design and schema understanding (primary keys, foreign keys, normalisation)
- Data quality auditing — identifying NULLs, orphaned foreign keys, duplicates, inconsistent text, and bad numeric values
- SQL view creation for non-destructive data cleaning
- Window functions: `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)`
- CTEs for fixing denominator scoping in grouped calculations
- Conditional aggregation: `CASE WHEN` inside `AVG()` to pivot groups into columns
- `DATEDIFF()` for tenure calculations
- Business framing — translating raw query output into stakeholder-facing findings and recommendations

---

*Author: Tomiwa Richard | MySQL Portfolio Project | 2025*
