-- =============================================================================
-- GROCERY E-COMMERCE SQL ANALYTICS
-- Dataset: "FreshCart Australia" (synthetic, 24K+ orders across 2022-2024)
-- Author: Ryan Do
-- Tools: DuckDB
-- =============================================================================
-- This project demonstrates advanced SQL for commercial analytics:
--   CTEs, window functions, cohort analysis, RFM segmentation,
--   YoY comparisons, promotional ROI, and market basket analysis.
-- =============================================================================


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  1. EXECUTIVE SUMMARY: Key Business Metrics                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- A single query that produces a high-level dashboard snapshot.

WITH revenue AS (
    SELECT
        oi.order_id,
        o.order_date,
        o.status,
        SUM(oi.quantity * oi.final_unit_price)  AS order_revenue,
        SUM(oi.quantity * p.unit_cost)           AS order_cogs,
        SUM(oi.quantity)                         AS total_units
    FROM order_items oi
    JOIN orders o    ON oi.order_id = o.order_id
    JOIN products p  ON oi.product_id = p.product_id
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY oi.order_id, o.order_date, o.status
)
SELECT
    COUNT(DISTINCT order_id)                              AS total_orders,
    ROUND(SUM(order_revenue), 2)                          AS total_revenue,
    ROUND(SUM(order_revenue - order_cogs), 2)             AS gross_profit,
    ROUND(SUM(order_revenue - order_cogs)
          / NULLIF(SUM(order_revenue), 0) * 100, 1)       AS gross_margin_pct,
    ROUND(SUM(order_revenue) / COUNT(DISTINCT order_id), 2) AS avg_order_value,
    ROUND(SUM(total_units)::FLOAT
          / COUNT(DISTINCT order_id), 1)                  AS avg_units_per_order,
    COUNT(DISTINCT CASE WHEN status = 'Returned'
                        THEN order_id END)                AS returned_orders,
    ROUND(COUNT(DISTINCT CASE WHEN status = 'Returned'
                              THEN order_id END)::FLOAT
          / COUNT(DISTINCT order_id) * 100, 1)            AS return_rate_pct
FROM revenue;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  2. MONTHLY REVENUE TREND WITH YEAR-OVER-YEAR GROWTH                      ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Uses LAG() to compare each month against the same month in the prior year.

WITH monthly AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::DATE AS month,
        EXTRACT(YEAR FROM o.order_date)          AS yr,
        EXTRACT(MONTH FROM o.order_date)         AS mth,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status != 'Cancelled'
    GROUP BY 1, 2, 3
)
SELECT
    month,
    revenue,
    LAG(revenue) OVER (PARTITION BY mth ORDER BY yr)     AS same_month_prev_year,
    CASE
        WHEN LAG(revenue) OVER (PARTITION BY mth ORDER BY yr) IS NOT NULL
        THEN ROUND(
            (revenue - LAG(revenue) OVER (PARTITION BY mth ORDER BY yr))
            / LAG(revenue) OVER (PARTITION BY mth ORDER BY yr) * 100, 1
        )
    END AS yoy_growth_pct
FROM monthly
ORDER BY month;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  3. CUSTOMER COHORT RETENTION ANALYSIS                                    ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Groups customers by the quarter of their first purchase, then tracks what
-- percentage return in subsequent quarters.

WITH first_purchase AS (
    SELECT
        customer_id,
        DATE_TRUNC('quarter', MIN(order_date))::DATE AS cohort_quarter
    FROM orders
    WHERE status != 'Cancelled'
    GROUP BY customer_id
),
customer_activity AS (
    SELECT DISTINCT
        o.customer_id,
        fp.cohort_quarter,
        DATE_TRUNC('quarter', o.order_date)::DATE AS activity_quarter
    FROM orders o
    JOIN first_purchase fp ON o.customer_id = fp.customer_id
    WHERE o.status != 'Cancelled'
),
cohort_sizes AS (
    SELECT cohort_quarter, COUNT(DISTINCT customer_id) AS cohort_size
    FROM first_purchase
    GROUP BY cohort_quarter
)
SELECT
    ca.cohort_quarter,
    cs.cohort_size,
    -- Number of quarters since first purchase (0 = first quarter)
    (EXTRACT(YEAR FROM ca.activity_quarter) - EXTRACT(YEAR FROM ca.cohort_quarter)) * 4
    + (EXTRACT(QUARTER FROM ca.activity_quarter) - EXTRACT(QUARTER FROM ca.cohort_quarter))
        AS quarters_since_first,
    COUNT(DISTINCT ca.customer_id) AS active_customers,
    ROUND(
        COUNT(DISTINCT ca.customer_id)::FLOAT / cs.cohort_size * 100, 1
    ) AS retention_pct
FROM customer_activity ca
JOIN cohort_sizes cs ON ca.cohort_quarter = cs.cohort_quarter
GROUP BY ca.cohort_quarter, cs.cohort_size,
         quarters_since_first
HAVING quarters_since_first <= 8
ORDER BY ca.cohort_quarter, quarters_since_first;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  4. RFM SEGMENTATION                                                      ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Segments customers using Recency, Frequency, and Monetary scores (1-5).
-- Assigns human-readable labels based on the combined RFM profile.

WITH rfm_base AS (
    SELECT
        o.customer_id,
        DATEDIFF('day', MAX(o.order_date), DATE '2024-12-31') AS recency_days,
        COUNT(DISTINCT o.order_id)                             AS frequency,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2)       AS monetary
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY o.customer_id
),
rfm_scores AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC)  AS r_score,  -- lower recency = higher score
        NTILE(5) OVER (ORDER BY frequency ASC)       AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)        AS m_score
    FROM rfm_base
),
rfm_labelled AS (
    SELECT
        *,
        r_score * 100 + f_score * 10 + m_score AS rfm_combined,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 4 AND f_score >= 3                  THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2                  THEN 'New Customers'
            WHEN r_score = 3  AND f_score >= 3                  THEN 'Potential Loyalists'
            WHEN r_score <= 2 AND f_score >= 4                  THEN 'At Risk'
            WHEN r_score <= 2 AND f_score >= 2 AND m_score >= 3 THEN 'Need Attention'
            WHEN r_score = 1  AND f_score = 1                   THEN 'Lost'
            ELSE 'Others'
        END AS rfm_segment
    FROM rfm_scores
)
SELECT
    rfm_segment,
    COUNT(*)                                     AS customer_count,
    ROUND(AVG(recency_days), 0)                  AS avg_recency_days,
    ROUND(AVG(frequency), 1)                     AS avg_frequency,
    ROUND(AVG(monetary), 2)                      AS avg_monetary,
    ROUND(SUM(monetary), 2)                      AS total_revenue,
    ROUND(SUM(monetary) / SUM(SUM(monetary)) OVER () * 100, 1)
                                                 AS revenue_share_pct
FROM rfm_labelled
GROUP BY rfm_segment
ORDER BY total_revenue DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  5. PRODUCT CATEGORY PERFORMANCE WITH RANKING                             ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Ranks categories by revenue, profit, and volume, with cumulative revenue share.

WITH category_stats AS (
    SELECT
        p.category,
        COUNT(DISTINCT o.order_id)                             AS orders,
        SUM(oi.quantity)                                       AS units_sold,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2)       AS revenue,
        ROUND(SUM(oi.quantity * (oi.final_unit_price - p.unit_cost)), 2)
                                                               AS gross_profit,
        ROUND(SUM(oi.quantity * (oi.final_unit_price - p.unit_cost))
              / NULLIF(SUM(oi.quantity * oi.final_unit_price), 0) * 100, 1)
                                                               AS margin_pct,
        COUNT(DISTINCT o.customer_id)                          AS unique_buyers
    FROM order_items oi
    JOIN orders o   ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.status != 'Cancelled'
    GROUP BY p.category
)
SELECT
    category,
    orders,
    units_sold,
    revenue,
    gross_profit,
    margin_pct,
    unique_buyers,
    RANK() OVER (ORDER BY revenue DESC)       AS revenue_rank,
    RANK() OVER (ORDER BY gross_profit DESC)  AS profit_rank,
    ROUND(
        SUM(revenue) OVER (ORDER BY revenue DESC
                           ROWS UNBOUNDED PRECEDING)
        / SUM(revenue) OVER () * 100, 1
    )                                         AS cumulative_revenue_pct
FROM category_stats
ORDER BY revenue DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  6. TOP 10 PRODUCTS BY REVENUE (PER CATEGORY)                             ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Uses ROW_NUMBER to get the top 10 products within each category.

WITH product_revenue AS (
    SELECT
        p.category,
        p.product_name,
        p.brand,
        SUM(oi.quantity)                                   AS units_sold,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2)   AS revenue,
        ROW_NUMBER() OVER (
            PARTITION BY p.category ORDER BY SUM(oi.quantity * oi.final_unit_price) DESC
        ) AS rank_in_category
    FROM order_items oi
    JOIN orders o   ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.status != 'Cancelled'
    GROUP BY p.category, p.product_name, p.brand
)
SELECT *
FROM product_revenue
WHERE rank_in_category <= 10
ORDER BY category, rank_in_category;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  7. PROMOTIONAL EFFECTIVENESS ANALYSIS                                    ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Compares promo vs non-promo orders on AOV, basket size, and volume.

WITH promo_flag AS (
    SELECT
        o.order_id,
        o.promo_id IS NOT NULL AS is_promo_order,
        pr.promo_name,
        pr.discount_pct AS promo_discount,
        SUM(oi.quantity * oi.final_unit_price) AS order_revenue,
        SUM(oi.quantity * oi.unit_price)       AS order_revenue_before_discount,
        SUM(oi.quantity)                       AS items
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    LEFT JOIN promotions pr ON o.promo_id = pr.promo_id
    WHERE o.status != 'Cancelled'
    GROUP BY o.order_id, o.promo_id, pr.promo_name, pr.discount_pct
)
SELECT
    COALESCE(promo_name, 'No Promotion') AS promo_name,
    COUNT(*)                             AS order_count,
    ROUND(AVG(order_revenue), 2)         AS avg_order_value,
    ROUND(AVG(items), 1)                 AS avg_basket_size,
    ROUND(SUM(order_revenue), 2)         AS total_revenue,
    ROUND(SUM(order_revenue_before_discount - order_revenue), 2)
                                         AS total_discount_given,
    ROUND(
        SUM(order_revenue_before_discount - order_revenue)
        / NULLIF(SUM(order_revenue_before_discount), 0) * 100, 1
    )                                    AS effective_discount_pct
FROM promo_flag
GROUP BY ROLLUP(promo_name)
ORDER BY total_revenue DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  8. CHANNEL MIX ANALYSIS WITH QUARTERLY TREND                             ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Tracks how each sales channel's revenue share evolves over time.

WITH quarterly_channel AS (
    SELECT
        DATE_TRUNC('quarter', o.order_date)::DATE            AS quarter,
        o.channel,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2)     AS revenue,
        COUNT(DISTINCT o.order_id)                           AS orders,
        COUNT(DISTINCT o.customer_id)                        AS customers
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status != 'Cancelled'
    GROUP BY 1, 2
)
SELECT
    quarter,
    channel,
    revenue,
    orders,
    customers,
    ROUND(
        revenue / SUM(revenue) OVER (PARTITION BY quarter) * 100, 1
    ) AS revenue_share_pct,
    -- QoQ growth within each channel
    ROUND(
        (revenue - LAG(revenue) OVER (PARTITION BY channel ORDER BY quarter))
        / NULLIF(LAG(revenue) OVER (PARTITION BY channel ORDER BY quarter), 0) * 100, 1
    ) AS qoq_growth_pct
FROM quarterly_channel
ORDER BY quarter, channel;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  9. CUSTOMER LIFETIME VALUE (CLV) DISTRIBUTION                            ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Calculates each customer's lifetime value and tenure, then buckets them.

WITH clv AS (
    SELECT
        o.customer_id,
        c.customer_segment,
        c.state,
        MIN(o.order_date) AS first_order,
        MAX(o.order_date) AS last_order,
        DATEDIFF('day', MIN(o.order_date), MAX(o.order_date)) AS tenure_days,
        COUNT(DISTINCT o.order_id)                             AS lifetime_orders,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2)       AS lifetime_revenue,
        ROUND(AVG(oi.quantity * oi.final_unit_price), 2)       AS avg_item_spend
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN customers c    ON o.customer_id = c.customer_id
    WHERE o.status NOT IN ('Cancelled')
    GROUP BY o.customer_id, c.customer_segment, c.state
)
SELECT
    customer_segment,
    COUNT(*)                             AS customers,
    ROUND(AVG(lifetime_revenue), 2)      AS avg_clv,
    ROUND(MEDIAN(lifetime_revenue), 2)   AS median_clv,
    ROUND(AVG(lifetime_orders), 1)       AS avg_orders,
    ROUND(AVG(tenure_days), 0)           AS avg_tenure_days,
    -- Distribution: how many are in each CLV tier
    COUNT(CASE WHEN lifetime_revenue < 50  THEN 1 END) AS clv_under_50,
    COUNT(CASE WHEN lifetime_revenue BETWEEN 50 AND 200 THEN 1 END) AS clv_50_200,
    COUNT(CASE WHEN lifetime_revenue BETWEEN 200 AND 500 THEN 1 END) AS clv_200_500,
    COUNT(CASE WHEN lifetime_revenue > 500 THEN 1 END) AS clv_over_500
FROM clv
GROUP BY customer_segment
ORDER BY avg_clv DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  10. STATE-LEVEL PERFORMANCE WITH BENCHMARKING                            ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Compares each state against the national average using a cross join.

WITH state_metrics AS (
    SELECT
        c.state,
        COUNT(DISTINCT o.order_id)                                AS orders,
        COUNT(DISTINCT o.customer_id)                             AS active_customers,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2)          AS revenue,
        ROUND(SUM(oi.quantity * oi.final_unit_price)
              / COUNT(DISTINCT o.order_id), 2)                    AS aov
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN customers c    ON o.customer_id = c.customer_id
    WHERE o.status != 'Cancelled'
    GROUP BY c.state
),
national_avg AS (
    SELECT
        ROUND(SUM(revenue) / SUM(orders), 2)            AS nat_aov,
        ROUND(SUM(revenue) / SUM(active_customers), 2)  AS nat_rev_per_cust
    FROM state_metrics
)
SELECT
    sm.state,
    sm.orders,
    sm.active_customers,
    sm.revenue,
    sm.aov,
    ROUND(sm.revenue / sm.active_customers, 2)  AS rev_per_customer,
    na.nat_aov,
    ROUND((sm.aov - na.nat_aov) / na.nat_aov * 100, 1) AS aov_vs_national_pct,
    ROUND(
        sm.revenue / SUM(sm.revenue) OVER () * 100, 1
    ) AS revenue_share_pct
FROM state_metrics sm
CROSS JOIN national_avg na
ORDER BY sm.revenue DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  11. ROLLING 3-MONTH REVENUE WITH TREND DETECTION                         ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Smooths revenue volatility using a 3-month rolling average, then flags
-- months where revenue dropped below the rolling average.

WITH monthly_rev AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::DATE AS month,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.status != 'Cancelled'
    GROUP BY 1
)
SELECT
    month,
    revenue,
    ROUND(
        AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2
    ) AS rolling_3m_avg,
    ROUND(
        revenue - AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2
    ) AS deviation_from_rolling,
    CASE
        WHEN revenue < AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
        THEN 'Below Trend'
        ELSE 'On/Above Trend'
    END AS trend_flag
FROM monthly_rev
ORDER BY month;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  12. MARKET BASKET ANALYSIS: FREQUENTLY CO-PURCHASED CATEGORIES           ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Self-join on order_items to find which category pairs appear together most.

WITH order_categories AS (
    SELECT DISTINCT
        oi.order_id,
        p.category
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    JOIN orders o   ON oi.order_id = o.order_id
    WHERE o.status != 'Cancelled'
),
category_pairs AS (
    SELECT
        a.category AS category_a,
        b.category AS category_b,
        COUNT(DISTINCT a.order_id) AS co_occurrence
    FROM order_categories a
    JOIN order_categories b
        ON a.order_id = b.order_id
        AND a.category < b.category   -- avoid duplicates and self-pairs
    GROUP BY a.category, b.category
),
category_totals AS (
    SELECT category, COUNT(DISTINCT order_id) AS solo_orders
    FROM order_categories
    GROUP BY category
)
SELECT
    cp.category_a,
    cp.category_b,
    cp.co_occurrence,
    ct_a.solo_orders AS orders_with_a,
    ct_b.solo_orders AS orders_with_b,
    -- Lift: how much more likely are they bought together vs. independently?
    ROUND(
        cp.co_occurrence::FLOAT
        / (ct_a.solo_orders::FLOAT * ct_b.solo_orders / (SELECT COUNT(DISTINCT order_id) FROM orders WHERE status != 'Cancelled'))
    , 3) AS lift
FROM category_pairs cp
JOIN category_totals ct_a ON cp.category_a = ct_a.category
JOIN category_totals ct_b ON cp.category_b = ct_b.category
ORDER BY lift DESC, co_occurrence DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  13. NEW vs RETURNING CUSTOMER REVENUE SPLIT                              ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- For each month, calculates how much revenue came from first-time buyers
-- vs. repeat purchasers.

WITH first_order AS (
    SELECT customer_id, MIN(order_date) AS first_order_date
    FROM orders
    WHERE status != 'Cancelled'
    GROUP BY customer_id
),
order_type AS (
    SELECT
        o.order_id,
        o.order_date,
        CASE
            WHEN o.order_date = fo.first_order_date THEN 'New'
            ELSE 'Returning'
        END AS customer_type
    FROM orders o
    JOIN first_order fo ON o.customer_id = fo.customer_id
    WHERE o.status != 'Cancelled'
)
SELECT
    month,
    customer_type,
    orders,
    revenue,
    ROUND(revenue / SUM(revenue) OVER (PARTITION BY month) * 100, 1)
        AS revenue_share_pct
FROM (
    SELECT
        DATE_TRUNC('month', ot.order_date)::DATE AS month,
        ot.customer_type,
        COUNT(DISTINCT ot.order_id)                              AS orders,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2)         AS revenue
    FROM order_type ot
    JOIN order_items oi ON ot.order_id = oi.order_id
    GROUP BY 1, 2
) sub
ORDER BY month, customer_type;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  14. STORE PERFORMANCE SCORECARD                                          ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Evaluates each physical store by revenue, orders, basket size,
-- and revenue per square metre.

SELECT
    s.store_name,
    s.state,
    s.city,
    s.store_size_sqm,
    COUNT(DISTINCT o.order_id)                                AS orders,
    ROUND(SUM(oi.quantity * oi.final_unit_price), 2)          AS revenue,
    ROUND(SUM(oi.quantity * oi.final_unit_price)
          / s.store_size_sqm, 2)                              AS revenue_per_sqm,
    ROUND(SUM(oi.quantity * oi.final_unit_price)
          / COUNT(DISTINCT o.order_id), 2)                    AS aov,
    ROUND(AVG(oi.quantity), 1)                                AS avg_qty_per_line,
    DENSE_RANK() OVER (
        ORDER BY SUM(oi.quantity * oi.final_unit_price) DESC
    )                                                         AS revenue_rank
FROM stores s
JOIN orders o       ON s.store_id = o.store_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status != 'Cancelled'
  AND o.channel != 'Online'
GROUP BY s.store_id, s.store_name, s.state, s.city, s.store_size_sqm
ORDER BY revenue DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  15. DAYS BETWEEN REPEAT PURCHASES (PURCHASE GAP ANALYSIS)                ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Uses LEAD() to calculate the gap between consecutive orders per customer.

WITH ordered_purchases AS (
    SELECT
        customer_id,
        order_date,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date)  AS purchase_seq,
        LEAD(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS next_order_date
    FROM orders
    WHERE status NOT IN ('Cancelled')
),
gaps AS (
    SELECT
        customer_id,
        purchase_seq,
        DATEDIFF('day', order_date, next_order_date) AS days_to_next_order
    FROM ordered_purchases
    WHERE next_order_date IS NOT NULL
)
SELECT
    CASE
        WHEN days_to_next_order <= 7   THEN '0-7 days'
        WHEN days_to_next_order <= 14  THEN '8-14 days'
        WHEN days_to_next_order <= 30  THEN '15-30 days'
        WHEN days_to_next_order <= 60  THEN '31-60 days'
        WHEN days_to_next_order <= 90  THEN '61-90 days'
        ELSE '90+ days'
    END AS gap_bucket,
    COUNT(*)                               AS occurrences,
    ROUND(AVG(days_to_next_order), 1)      AS avg_gap_days,
    ROUND(MEDIAN(days_to_next_order), 1)   AS median_gap_days
FROM gaps
GROUP BY 1
ORDER BY MIN(days_to_next_order);


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  16. BRAND SHARE WITHIN EACH CATEGORY                                     ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝
-- Shows each brand's market share within its category and overall rank.

WITH brand_stats AS (
    SELECT
        p.category,
        p.brand,
        SUM(oi.quantity)                                   AS units_sold,
        ROUND(SUM(oi.quantity * oi.final_unit_price), 2)   AS revenue
    FROM order_items oi
    JOIN orders o   ON oi.order_id = o.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.status != 'Cancelled'
    GROUP BY p.category, p.brand
)
SELECT
    category,
    brand,
    units_sold,
    revenue,
    ROUND(
        revenue / SUM(revenue) OVER (PARTITION BY category) * 100, 1
    ) AS category_share_pct,
    RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_category
FROM brand_stats
ORDER BY category, rank_in_category;

-- End of SQL analytics code for FreshCart Australia dataset.
-- All these queries can be run in the included interactive Python Notebook
