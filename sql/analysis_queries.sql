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