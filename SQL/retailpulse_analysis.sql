CREATE DATABASE retailpulse;
USE retailpulse;
SELECT COUNT(*) FROM retailpulse_mysql;
SELECT * FROM retailpulse_mysql
LIMIT 10;

-- Check imported column names and data types
DESCRIBE retailpulse_mysql;

-- =====================================================
-- 1. DATASET VALIDATION
-- =====================================================

-- Confirm the number of imported records
SELECT COUNT(*) AS total_rows
FROM retailpulse_mysql;

-- Check the number of unique products
SELECT COUNT(DISTINCT product_id) AS unique_products
FROM retailpulse_mysql;

-- Check the date range covered by the dataset
SELECT 
    MIN(STR_TO_DATE(month_year, '%Y-%m-%d')) AS start_date,
    MAX(STR_TO_DATE(month_year, '%Y-%m-%d')) AS end_date
FROM retailpulse_mysql;

-- =====================================================
-- 2. CATEGORY REVENUE & SALES PERFORMANCE
-- =====================================================

SELECT
    product_category_name,
    ROUND(SUM(total_price), 2) AS total_revenue,
    SUM(qty) AS total_quantity,
    ROUND(AVG(unit_price), 2) AS avg_unit_price
FROM retailpulse_mysql
GROUP BY product_category_name
ORDER BY total_revenue DESC;

-- =====================================================
-- 3. CATEGORY REVENUE SHARE & RANKING
-- =====================================================

WITH category_sales AS (
    SELECT
        product_category_name,
        SUM(total_price) AS total_revenue,
        SUM(qty) AS total_quantity
    FROM retailpulse_mysql
    GROUP BY product_category_name
)
SELECT
    product_category_name,
    ROUND(total_revenue, 2) AS total_revenue,
    total_quantity,ROUND(total_revenue / SUM(total_revenue) OVER () * 100,2) AS revenue_share_pct,
-- Rank categories from highest to lowest revenue
    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS revenue_rank
FROM category_sales
ORDER BY revenue_rank;

-- =====================================================
-- 4. TOP PRODUCT PERFORMANCE
-- =====================================================

-- =====================================================
-- 4. TOP PRODUCT PERFORMANCE
-- =====================================================

WITH product_sales AS (
    SELECT
        product_id,
        product_category_name,
        ROUND(SUM(total_price), 2) AS total_revenue,
        SUM(qty) AS total_quantity,
        ROUND(AVG(unit_price), 2) AS avg_unit_price
    FROM retailpulse_mysql
    GROUP BY product_id, product_category_name
)

SELECT
    product_id,
    product_category_name,
    total_revenue,
    total_quantity,
    avg_unit_price,
    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS revenue_rank,
    DENSE_RANK() OVER (
        ORDER BY total_quantity DESC
    ) AS quantity_rank
FROM product_sales
ORDER BY revenue_rank
LIMIT 15;

-- =====================================================
-- 5. MONTHLY REVENUE & SALES TREND
-- =====================================================

SELECT
    STR_TO_DATE(month_year, '%Y-%m-%d') AS month_date,
    ROUND(SUM(total_price), 2) AS monthly_revenue,
    SUM(qty) AS monthly_quantity
FROM retailpulse_mysql
GROUP BY STR_TO_DATE(month_year, '%Y-%m-%d')
ORDER BY month_date;

-- =====================================================
-- 6. MONTH-OVER-MONTH REVENUE CHANGE
-- =====================================================

-- Month-over-month revenue change
WITH monthly_sales AS (
    SELECT STR_TO_DATE(month_year, '%Y-%m-%d') AS month_date,
           SUM(total_price) AS revenue,
           SUM(qty) AS quantity
    FROM retailpulse_mysql
    GROUP BY month_date
)
SELECT month_date,
       ROUND(revenue, 2) AS revenue,
       quantity,
       ROUND(LAG(revenue) OVER(ORDER BY month_date), 2) AS previous_revenue,
       ROUND(revenue - LAG(revenue) OVER(ORDER BY month_date), 2) AS revenue_change,
       ROUND((revenue - LAG(revenue) OVER(ORDER BY month_date)) /
             LAG(revenue) OVER(ORDER BY month_date) * 100, 2) AS revenue_change_pct
FROM monthly_sales
ORDER BY month_date;

-- =====================================================
-- 7. DEMAND RESPONSE BY PRICE DIRECTION
-- =====================================================

SELECT price_direction,
       COUNT(*) AS observations,
       ROUND(AVG(CAST(qty_change AS DECIMAL(10,2))), 2) AS avg_qty_change
FROM retailpulse_mysql
WHERE price_direction IN ('Increase', 'Decrease')
  AND qty_change <> ''
GROUP BY price_direction;

-- =====================================================
-- 8. COMPETITOR PRICE POSITIONING
-- =====================================================

SELECT 
    comp_1_position,
    COUNT(*) AS observations,
    ROUND(AVG(qty), 2) AS avg_quantity,
    ROUND(AVG(total_price), 2) AS avg_revenue
FROM
    retailpulse_mysql
GROUP BY comp_1_position
ORDER BY observations DESC;

-- =====================================================
-- 9. CATEGORY-LEVEL COMPETITOR POSITIONING
-- =====================================================

SELECT product_category_name,
       ROUND(AVG(comp_1_gap), 2) AS avg_comp1_gap,
       ROUND(AVG(comp_2_gap), 2) AS avg_comp2_gap,
       ROUND(AVG(comp_3_gap), 2) AS avg_comp3_gap,
       ROUND(AVG(qty), 2) AS avg_quantity
FROM retailpulse_mysql
GROUP BY product_category_name
ORDER BY avg_comp1_gap DESC;

-- =====================================================
-- BUSINESS QUESTION 1: COMPETITIVE PRICING RISK
-- =====================================================

-- Which high-revenue products are consistently priced above competitors?

WITH product_pricing AS (
    SELECT product_id, product_category_name,
           SUM(total_price) AS revenue,
           SUM(qty) AS units_sold,
           AVG(comp_1_gap) AS gap1,
           AVG(comp_2_gap) AS gap2,
           AVG(comp_3_gap) AS gap3
    FROM retailpulse_mysql
    GROUP BY product_id, product_category_name
)
SELECT product_id, product_category_name,
       ROUND(revenue, 2) AS revenue,
       units_sold,
       ROUND((gap1 + gap2 + gap3) / 3, 2) AS avg_comp_gap
FROM product_pricing
WHERE gap1 > 0 AND gap2 > 0 AND gap3 > 0
ORDER BY revenue DESC
LIMIT 10;

-- =====================================================
-- BUSINESS QUESTION 2: POTENTIAL PRICING HEADROOM
-- =====================================================

-- Which strong-selling products are priced below the average competitor level?

WITH product_pricing AS (
    SELECT product_id, product_category_name,
           SUM(total_price) AS revenue,
           SUM(qty) AS units_sold,
           AVG((comp_1_gap + comp_2_gap + comp_3_gap) / 3) AS avg_comp_gap
    FROM retailpulse_mysql
    GROUP BY product_id, product_category_name
),
avg_sales AS (
    SELECT AVG(units_sold) AS avg_units
    FROM product_pricing
)
SELECT product_id, product_category_name,
       ROUND(revenue, 2) AS revenue,
       units_sold,
       ROUND(avg_comp_gap, 2) AS avg_comp_gap
FROM product_pricing, avg_sales
WHERE units_sold > avg_units
  AND avg_comp_gap < 0
ORDER BY units_sold DESC;

-- =====================================================
-- BUSINESS QUESTION 3: REVENUE EXPOSURE
-- =====================================================

-- How much revenue comes from products priced above the average competitor level?

WITH product_pricing AS (
    SELECT product_id, product_category_name,
           SUM(total_price) AS revenue,
           AVG((comp_1_gap + comp_2_gap + comp_3_gap) / 3) AS avg_comp_gap
    FROM retailpulse_mysql
    GROUP BY product_id, product_category_name
)
SELECT product_category_name,
       ROUND(SUM(revenue), 2) AS exposed_revenue,
       COUNT(*) AS products,
       ROUND(AVG(avg_comp_gap), 2) AS avg_comp_gap
FROM product_pricing
WHERE avg_comp_gap > 0
GROUP BY product_category_name
ORDER BY exposed_revenue DESC;

-- =====================================================
-- BUSINESS QUESTION 4: PRICE SENSITIVITY RISK
-- =====================================================

-- Which products lost the most demand when their prices increased?

SELECT product_id, product_category_name,
       COUNT(*) AS price_increases,
       ROUND(AVG(CAST(price_change_pct AS DECIMAL(10,2))), 2) AS avg_price_increase_pct,
       ROUND(AVG(CAST(qty_change AS DECIMAL(10,2))), 2) AS avg_qty_change,
       ROUND(SUM(total_price), 2) AS revenue
FROM retailpulse_mysql
WHERE price_direction = 'Increase'
  AND qty_change <> ''
GROUP BY product_id, product_category_name
HAVING COUNT(*) >= 2
ORDER BY avg_qty_change
LIMIT 10;

-- =====================================================
-- BUSINESS QUESTION 5: PRICING STABILITY
-- =====================================================

-- Which high-revenue products experience the most frequent price changes?

SELECT product_id, product_category_name,
       COUNT(*) AS comparable_months,
       SUM(CASE WHEN price_direction IN ('Increase', 'Decrease') THEN 1 ELSE 0 END) AS price_changes,
       ROUND(SUM(CASE WHEN price_direction IN ('Increase', 'Decrease') THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 2) AS change_frequency_pct,
       ROUND(SUM(total_price), 2) AS revenue
FROM retailpulse_mysql
WHERE price_direction <> 'First Observation'
GROUP BY product_id, product_category_name
HAVING COUNT(*) >= 5
ORDER BY change_frequency_pct DESC, revenue DESC
LIMIT 10;

-- =====================================================
-- BUSINESS QUESTION 6: PRICING PRIORITY SHORTLIST
-- =====================================================

-- Which products should be prioritized for pricing review?

WITH product_summary AS (
    SELECT product_id, product_category_name,
           SUM(total_price) AS revenue,
           SUM(qty) AS units_sold,
           AVG((comp_1_gap + comp_2_gap + comp_3_gap) / 3) AS avg_comp_gap,
           AVG(CASE WHEN price_direction = 'Increase'
                    THEN CAST(qty_change AS DECIMAL(10,2)) END) AS demand_after_increase
    FROM retailpulse_mysql
    GROUP BY product_id, product_category_name
)
SELECT product_id, product_category_name,
       ROUND(revenue, 2) AS revenue,
       units_sold,
       ROUND(avg_comp_gap, 2) AS avg_comp_gap,
       ROUND(demand_after_increase, 2) AS demand_after_increase
FROM product_summary
WHERE revenue > (SELECT AVG(revenue) FROM product_summary)
ORDER BY revenue DESC, avg_comp_gap DESC
LIMIT 10;