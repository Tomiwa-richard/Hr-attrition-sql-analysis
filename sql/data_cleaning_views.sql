-- =========================================================================
-- FILE: 02_data_cleaning_views.sql
-- PURPOSE: Establishes clean, standardized views over simulated raw tables.
--          Addresses: Inconsistent casing, orphaned keys, and duplicates.
-- =========================================================================

USE hr_attrition_db; -- Change this to match your local database name

-- -------------------------------------------------------------------------
-- VIEW 1: employees_clean
-- Handles: Casing inconsistencies, trailing spaces, and orphaned dept IDs.
-- -------------------------------------------------------------------------
CREATE OR REPLACE VIEW employees_clean AS
WITH deduplicated_employees AS (
    SELECT 
        employee_id,
        -- Fix casing and remove trailing spaces from job roles
        LOWER(TRIM(job_role)) AS job_role,
        performance_rating,
        hire_date,
        -- Fallback logic for orphaned or NULL department IDs based on job role
        CASE 
            WHEN department_id IS NULL AND LOWER(TRIM(job_role)) LIKE '%sales%' THEN 101 -- Sales Dept ID
            WHEN department_id IS NULL AND LOWER(TRIM(job_role)) LIKE '%marketing%' THEN 102 -- Marketing Dept ID
            WHEN department_id IS NULL AND LOWER(TRIM(job_role)) LIKE '%developer%' THEN 103 -- Engineering Dept ID
            ELSE department_id 
        END AS department_id,
        -- Identify duplicates by partitioning unique fields (keeping the earliest record)
        ROW_NUMBER() OVER (
            PARTITION BY first_name, last_name, hire_date 
            ORDER BY employee_id ASC
        ) AS row_num
    FROM employees
)
SELECT 
    employee_id,
    job_role,
    performance_rating,
    hire_date,
    department_id
FROM deduplicated_employees
WHERE row_num = 1; -- Filter out duplicate entries


-- -------------------------------------------------------------------------
-- VIEW 2: salary_clean
-- Handles: Excluding anomalous, negative, or NULL salaries at query runtime.
-- -------------------------------------------------------------------------
CREATE OR REPLACE VIEW salary_clean AS
SELECT 
    employee_id,
    salary,
    effective_date,
    -- Get the absolute current salary ranking for each employee
    ROW_NUMBER() OVER (
        PARTITION BY employee_id 
        ORDER BY effective_date DESC
    ) AS current_salary_rank
FROM salary_history
WHERE salary IS NOT NULL 
  AND salary > 0; -- Filters out negative or null salary anomalies