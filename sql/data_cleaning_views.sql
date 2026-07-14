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