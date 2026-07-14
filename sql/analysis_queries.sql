-- =========================================================================
-- FILE: 03_analysis_queries.sql
-- PURPOSE: Solves the 5 core HR business questions using clean views.
--          Techniques: CTEs, Window Functions, and Conditional Aggregations.
-- =========================================================================

USE hr_attrition_db; -- Match your local database name

-- -------------------------------------------------------------------------
-- Q1: Which departments have the highest attrition rate?
-- -------------------------------------------------------------------------
-- Business Takeaway: Identifies localized attrition hotspots rather than 
-- relying on deceptive company-wide averages.
-- -------------------------------------------------------------------------
SELECT 
    d.dept_name AS department,
    COUNT(e.employee_id) AS total_employees,
    COUNT(a.employee_id) AS leavers,
    ROUND((COUNT(a.employee_id) / COUNT(e.employee_id)) * 100, 2) AS attrition_rate
FROM employees_clean e
LEFT JOIN departments d ON e.department_id = d.department_id
LEFT JOIN attrition a ON e.employee_id = a.employee_id
GROUP BY d.dept_name
ORDER BY attrition_rate DESC;


-- -------------------------------------------------------------------------
-- Q2: Is the attrition voluntary or involuntary across departments?
-- -------------------------------------------------------------------------
-- Business Takeaway: Separates forced terminations (performance/layoffs) 
-- from voluntary resignations (culture/morale issues).
-- -------------------------------------------------------------------------
WITH department_baselines AS (
    -- Pre-calculate absolute headcount to maintain an accurate denominator
    SELECT 
        department_id,
        COUNT(*) AS total_dept_headcount
    FROM employees_clean
    GROUP BY department_id
)
SELECT 
    d.dept_name AS department,
    a.exit_type,
    COUNT(a.employee_id) AS leavers,
    ROUND((COUNT(a.employee_id) / b.total_dept_headcount) * 100, 2) AS rate_vs_total_headcount
FROM attrition a
JOIN employees_clean e ON a.employee_id = e.employee_id
JOIN departments d ON e.department_id = d.department_id
JOIN department_baselines b ON e.department_id = b.department_id
WHERE a.exit_type IS NOT NULL
GROUP BY d.dept_name, a.exit_type, b.total_dept_headcount
ORDER BY d.dept_name, rate_vs_total_headcount DESC;


-- -------------------------------------------------------------------------
-- Q3: Are high performers leaving at a higher rate than low performers?
-- -------------------------------------------------------------------------
-- Business Takeaway: Exposes if the organization is suffering a "brain drain" 
-- by losing top-tier talent (Rating 5) while retaining weak performers.
-- -------------------------------------------------------------------------
SELECT 
    e.performance_rating,
    COUNT(e.employee_id) AS total_employees,
    COUNT(a.employee_id) AS leavers,
    ROUND((COUNT(a.employee_id) / COUNT(e.employee_id)) * 100, 2) AS attrition_rate
FROM employees_clean e
LEFT JOIN attrition a ON e.employee_id = a.employee_id
WHERE e.performance_rating IS NOT NULL
GROUP BY e.performance_rating
ORDER BY e.performance_rating DESC;


-- -------------------------------------------------------------------------
-- Q4: What is the salary gap between leavers and stayers per job role?
-- -------------------------------------------------------------------------
-- Business Takeaway: Determines whether individuals are leaving for money 
-- (positive gap) or if compensation is unrelated to turnover (negative gap).
-- -------------------------------------------------------------------------
WITH current_salaries AS (
    -- Extract only the most recent salary to prevent historical skew
    SELECT 
        employee_id,
        salary
    FROM salary_clean
    WHERE current_salary_rank = 1
)
SELECT 
    e.job_role,
    -- Average salary of active employees
    ROUND(AVG(CASE WHEN a.employee_id IS NULL THEN s.salary END), 2) AS avg_salary_stayers,
    -- Average salary of terminated employees
    ROUND(AVG(CASE WHEN a.employee_id IS NOT NULL THEN s.salary END), 2) AS avg_salary_leavers,
    -- Calculated variance (stayers - leavers)
    ROUND(
        AVG(CASE WHEN a.employee_id IS NULL THEN s.salary END) - 
        AVG(CASE WHEN a.employee_id IS NOT NULL THEN s.salary END), 
        2
    ) AS salary_variance
FROM employees_clean e
JOIN current_salaries s ON e.employee_id = s.employee_id
LEFT JOIN attrition a ON e.employee_id = a.employee_id
GROUP BY e.job_role
HAVING avg_salary_leavers IS NOT NULL
ORDER BY salary_variance ASC;


-- -------------------------------------------------------------------------
-- Q5: Which departments have the longest average tenure before employees leave?
-- -------------------------------------------------------------------------
-- Business Takeaway: Benchmarks how long departments retain talent before 
-- fatigue or growth boundaries trigger an exit.
-- -------------------------------------------------------------------------
SELECT 
    d.dept_name AS department,
    ROUND(AVG(DATEDIFF(a.exit_date, e.hire_date) / 365.25), 2) AS avg_tenure_years
FROM attrition a
JOIN employees_clean e ON a.employee_id = e.employee_id
JOIN departments d ON e.department_id = d.department_id
WHERE a.exit_date IS NOT NULL
GROUP BY d.dept_name
ORDER BY avg_tenure_years ASC;