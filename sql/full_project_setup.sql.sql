-- =============================================================================
-- HR ATTRITION ANALYSIS
-- =============================================================================
-- Author   : Tomiwa Richard
-- Database : hr_attrition (MySQL)
-- Dataset  : Simulated HR dataset (~750 employees, 8 departments)
-- Purpose  : Analyse employee attrition patterns to support data-driven
--            retention decisions for the CHRO
-- Tables   : employees, departments, salary_history, attrition
-- Views    : employees_clean, salary_clean
-- Questions:
--   Q1. Which departments have the highest attrition rate?
--   Q2. Is attrition voluntary or involuntary, and does the split vary by dept?
--   Q3. Are high performers leaving at a higher rate than low performers?
--   Q4. What is the salary gap between leavers and stayers per job role?
--   Q5. Which departments have the longest average tenure before employees leave?
-- =============================================================================

USE hr_attrition;

-- =============================================================================
-- SECTION 1: DATA QUALITY AUDIT
-- =============================================================================
-- Before any cleaning or analysis, we inspect the raw tables to understand
-- the shape of the data and identify quality issues.
-- =============================================================================

-- 1.1 Row counts across all four tables
SELECT COUNT(*) AS total_employees   FROM employees;
SELECT COUNT(*) AS total_salary_rows FROM salary_history;
SELECT COUNT(*) AS total_attrition   FROM attrition;

-- 1.2 Preview raw employee records
SELECT * FROM employees LIMIT 10;

-- 1.3 Check for inconsistent job_role casing and spacing
-- Finding: many roles appear in multiple casing variants (e.g. 'HR MANAGER',
-- 'hr manager', 'Hr Manager') — these must be standardized before grouping.
SELECT DISTINCT job_role FROM employees ORDER BY job_role;

-- 1.4 Check department_id values — looking for NULLs and orphaned foreign keys
-- Finding: some rows have NULL department_id; others point to department_id = 99
-- which does not exist in the departments table (orphaned FK).
SELECT DISTINCT department_id FROM employees ORDER BY department_id;

-- 1.5 Confirm valid department IDs in the departments table
SELECT * FROM departments;

-- 1.6 Check for NULL performance ratings
-- Finding: ~4% of employees have no performance rating recorded.
SELECT DISTINCT performance_rating FROM employees ORDER BY performance_rating;

-- 1.7 Check for bad salary values (negative, zero, or NULL)
-- Finding: ~60 rows in salary_history have invalid amounts.
SELECT COUNT(*) AS bad_salary_rows
FROM salary_history
WHERE salary_amount <= 0 OR salary_amount IS NULL;

-- 1.8 Check for terminated employees missing from the attrition table
-- Finding: 3 terminated employees have no corresponding attrition record
-- (data entry gap — not recoverable, will be excluded from attrition analysis).
SELECT COUNT(*) AS terminated_missing_from_attrition
FROM employees e
LEFT JOIN attrition a ON e.employee_id = a.employee_id
WHERE e.employment_status = 'Terminated'
  AND a.employee_id IS NULL;

-- 1.9 Check for duplicate employee records
-- Grouping on name + hire_date (not employee_id, which is always unique by design).
-- Finding: a small number of employees were entered twice with different IDs.
SELECT first_name, last_name, hire_date, COUNT(*) AS occurrences
FROM employees
GROUP BY first_name, last_name, hire_date
HAVING COUNT(*) > 1;

-- 1.10 Check for a fully NULL garbage row (no employee_id, no data at all)
-- Finding: one row with every column NULL — not recoverable, must be excluded.
SELECT * FROM employees WHERE employee_id IS NULL;

-- 1.11 Verify job_role → department mapping is 1-to-1 (after standardization)
-- This confirms we can safely infer a correct department_id from job_role
-- for the orphaned (NULL / 99) rows.
SELECT
    LOWER(TRIM(job_role)) AS clean_role,
    COUNT(DISTINCT d.department_id) AS dept_count
FROM employees e
JOIN departments d ON d.department_id = e.department_id
GROUP BY clean_role
HAVING COUNT(DISTINCT d.department_id) > 1;
-- Result: 0 rows — every role maps to exactly one department. Inference is safe.


-- =============================================================================
-- SECTION 2: DATA CLEANING — VIEWS
-- =============================================================================
-- We never modify the raw tables. All fixes are applied inside views so the
-- source data remains intact and queries are always reproducible.
-- =============================================================================

-- 2.1 employees_clean
-- Fixes applied:
--   a) Exclude the fully NULL garbage row (WHERE employee_id IS NOT NULL)
--   b) Deduplicate rows using ROW_NUMBER() — keep earliest employee_id per person
--   c) Standardize job_role: LOWER(TRIM()) removes casing and spacing inconsistencies
--   d) Recover bad department_id values (NULL or 99) by inferring the correct
--      department from job_role using a correlated subquery
DROP VIEW IF EXISTS employees_clean;
CREATE VIEW employees_clean AS
SELECT
    employee_id,
    first_name,
    last_name,
    LOWER(TRIM(job_role)) AS clean_job_role,
    hire_date,
    gender,
    age,
    performance_rating,
    employment_status,
    -- Recover NULL / orphaned department_id using job_role → department mapping
    CASE
        WHEN e.department_id IN (99) OR e.department_id IS NULL
        THEN (
            SELECT d2.department_id
            FROM employees e2
            JOIN departments d2 USING (department_id)
            WHERE LOWER(TRIM(e2.job_role)) = LOWER(TRIM(e.job_role))
            LIMIT 1
        )
        ELSE e.department_id
    END AS clean_department_id
FROM (
    -- Deduplicate: assign row number per person, keep first occurrence
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY first_name, last_name, hire_date
            ORDER BY employee_id
        ) AS rn
    FROM employees
    WHERE employee_id IS NOT NULL  -- exclude garbage row
) AS e
WHERE rn = 1;  -- keep only the first (earliest) occurrence of each person

-- 2.2 salary_clean
-- Fixes applied:
--   Exclude rows where salary_amount is negative, zero, or NULL —
--   these are data entry errors and cannot be imputed meaningfully.
DROP VIEW IF EXISTS salary_clean;
CREATE VIEW salary_clean AS
SELECT
    salary_id,
    employee_id,
    salary_amount,
    effective_date
FROM salary_history
WHERE salary_amount > 0
  AND salary_amount IS NOT NULL;

-- 2.3 Verify cleaning results
SELECT COUNT(*) AS raw_employees   FROM employees;       -- expect 761
SELECT COUNT(*) AS clean_employees FROM employees_clean; -- expect ~750 (dupes + garbage removed)

SELECT COUNT(*) AS raw_salary_rows   FROM salary_history; -- expect 3049
SELECT COUNT(*) AS clean_salary_rows FROM salary_clean;   -- expect ~2989 (60 bad rows removed)

-- Confirm no remaining bad department_ids
SELECT COUNT(*) AS remaining_bad_depts
FROM employees_clean
WHERE clean_department_id IS NULL OR clean_department_id = 99; -- expect 0

-- Confirm job_role standardization
SELECT DISTINCT clean_job_role FROM employees_clean ORDER BY clean_job_role;


-- =============================================================================
-- SECTION 3: BUSINESS QUESTIONS
-- =============================================================================
-- All queries below run on the clean views, never on raw tables.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Q1. Which departments have the highest attrition rate?
-- ----------------------------------------------------------------------------
-- Attrition rate = (employees who left / total employees in dept) × 100
-- LEFT JOIN to attrition ensures active employees are included in the denominator.
-- COUNT(a.employee_id) only counts rows where a match exists (i.e. leavers).
-- ----------------------------------------------------------------------------
SELECT
    d.department_name,
    COUNT(e.employee_id)  AS total_employees,
    COUNT(a.employee_id)  AS total_leavers,
    ROUND(COUNT(a.employee_id) / COUNT(e.employee_id) * 100, 2) AS attrition_rate
FROM employees_clean e
JOIN departments d ON e.clean_department_id = d.department_id
LEFT JOIN attrition a ON e.employee_id = a.employee_id
GROUP BY d.department_id, d.department_name
ORDER BY attrition_rate DESC;

-- Finding: Sales has the highest attrition rate (~21%), Marketing the lowest (~9%).


-- ----------------------------------------------------------------------------
-- Q2. Is attrition voluntary or involuntary? Does the split vary by department?
-- ----------------------------------------------------------------------------
-- The denominator must be fixed BEFORE splitting by exit_type, otherwise
-- COUNT(e.employee_id) scopes to each exit_type group and produces 100% rates.
-- Solution: calculate total headcount per department in a CTE first,
-- then join it back as a fixed denominator.
-- ----------------------------------------------------------------------------
WITH department_headcount AS (
    SELECT
        clean_department_id,
        COUNT(employee_id) AS total_employees
    FROM employees_clean
    GROUP BY clean_department_id
)
SELECT
    d.department_name,
    te.total_employees,
    a.exit_type,
    COUNT(a.employee_id) AS total_leavers,
    ROUND(COUNT(a.employee_id) / te.total_employees * 100, 2) AS attrition_rate
FROM employees_clean e
JOIN departments d ON e.clean_department_id = d.department_id
LEFT JOIN attrition a ON e.employee_id = a.employee_id
JOIN department_headcount te ON d.department_id = te.clean_department_id
WHERE a.exit_type IS NOT NULL  -- exclude active employees (no exit_type)
GROUP BY d.department_id, d.department_name, a.exit_type
ORDER BY d.department_name, a.exit_type;

-- Finding: Human Resources has the highest voluntary attrition (14.3%) —
-- employees are actively choosing to leave. Sales shows high rates on BOTH
-- sides: 12.9% voluntary and 8.2% involuntary simultaneously, suggesting
-- a department under stress from multiple directions.


-- ----------------------------------------------------------------------------
-- Q3. Are high performers leaving at a higher rate than low performers?
-- ----------------------------------------------------------------------------
-- Groups employees by performance_rating (1=lowest, 5=highest).
-- NULL ratings excluded — we cannot meaningfully place unrated employees
-- in a performance-based analysis.
-- No CTE needed here: GROUP BY performance_rating does not split active vs
-- terminated, so COUNT(e.employee_id) correctly captures full headcount
-- per rating group.
-- ----------------------------------------------------------------------------
SELECT
    e.performance_rating,
    COUNT(e.employee_id)  AS total_employees,
    COUNT(a.employee_id)  AS total_leavers,
    ROUND(COUNT(a.employee_id) / COUNT(e.employee_id) * 100, 2) AS attrition_rate
FROM employees_clean e
JOIN departments d ON e.clean_department_id = d.department_id
LEFT JOIN attrition a ON e.employee_id = a.employee_id
WHERE e.performance_rating IS NOT NULL
GROUP BY e.performance_rating
ORDER BY attrition_rate DESC;

-- Finding: Rating 5 (top performers) has the HIGHEST attrition rate at 19.6%.
-- Rating 1 (lowest performers) has the lowest at 13.5%.
-- This is a crisis signal — the company is retaining its weakest employees
-- while losing its best. Immediate investigation required.


-- ----------------------------------------------------------------------------
-- Q4. What is the salary gap between leavers and stayers per job role?
-- ----------------------------------------------------------------------------
-- Uses only the most recent salary per employee (via ROW_NUMBER on effective_date)
-- to avoid distorting averages with historical raises.
-- CASE WHEN inside AVG() pivots two groups (Active/Terminated) into separate
-- columns on the same row — positive gap means stayers earn more than leavers did;
-- negative gap means leavers were earning MORE than stayers (pay is not the issue).
-- ----------------------------------------------------------------------------
WITH latest_salary AS (
    SELECT employee_id, salary_amount
    FROM (
        SELECT
            employee_id,
            salary_amount,
            ROW_NUMBER() OVER (
                PARTITION BY employee_id
                ORDER BY effective_date DESC
            ) AS rn
        FROM salary_clean
    ) ranked
    WHERE rn = 1
)
SELECT
    e.clean_job_role,
    ROUND(AVG(CASE WHEN e.employment_status = 'Active'
                   THEN ls.salary_amount END), 2) AS avg_salary_stayers,
    ROUND(AVG(CASE WHEN e.employment_status = 'Terminated'
                   THEN ls.salary_amount END), 2) AS avg_salary_leavers,
    ROUND(
        AVG(CASE WHEN e.employment_status = 'Active'     THEN ls.salary_amount END) -
        AVG(CASE WHEN e.employment_status = 'Terminated' THEN ls.salary_amount END)
    , 2) AS salary_gap
FROM employees_clean e
JOIN latest_salary ls ON e.employee_id = ls.employee_id
GROUP BY e.clean_job_role
ORDER BY salary_gap ASC;

-- Finding: Most roles show a NEGATIVE salary gap — leavers were earning more
-- than the stayers in the same role. This rules out pay as the primary driver
-- of attrition. Root causes are likely non-monetary: management quality,
-- career growth, culture, or unrealistic targets.
-- Roles with a positive gap (e.g. account manager, marketing manager) suggest
-- those leavers may have left due to feeling underpaid relative to peers.


-- ----------------------------------------------------------------------------
-- Q5. Which departments have the longest average tenure before employees leave?
-- ----------------------------------------------------------------------------
-- Tenure = days between hire_date and exit_date, converted to years.
-- Only includes employees who actually left (INNER JOIN to attrition).
-- Shorter average tenure = employees deciding to leave earlier,
-- suggesting the department fails to engage or retain people long-term.
-- ----------------------------------------------------------------------------
SELECT
    d.department_name,
    ROUND(AVG(DATEDIFF(a.exit_date, e.hire_date) / 365), 2) AS avg_tenure_years
FROM employees_clean e
JOIN attrition a ON e.employee_id = a.employee_id
JOIN departments d ON e.clean_department_id = d.department_id
GROUP BY d.department_id, d.department_name
ORDER BY avg_tenure_years ASC;

-- Finding: Finance (2.37 yrs) and Legal (2.66 yrs) have the shortest tenure
-- before employees leave — people are making their exit decision very early.
-- Engineering (3.91 yrs) retains leavers the longest before they walk out,
-- suggesting stronger engagement or more complex exit decisions in technical roles.