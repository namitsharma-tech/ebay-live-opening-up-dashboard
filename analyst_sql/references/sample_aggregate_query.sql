DROP TABLE IF EXISTS P_amer_verticals_T.ebay_Live_UserFunnel_Tableau; ---BACKEND FOR SUMMARY TAB BOTTOM TABLE
CREATE TABLE P_amer_verticals_T.ebay_Live_UserFunnel_Tableau AS
WITH WEEKLY AS (
	SELECT
		CAL.RETAIL_YEAR||'RW'||CASE WHEN LENGTH(CAL.RETAIL_WEEK) = 1 THEN '0' ELSE '' END||CAL.RETAIL_WEEK||CASE WHEN CAL.AGE_FOR_RTL_WEEK_ID = 0 THEN "TW" ELSE '' END AS Label,
		'Retail Week' AS TIME_FRAME,
		VERTICAL,
		Category,
		Viewer_Traffic_Source_Group,
		Viewer_Traffic_Source,
		Viewer_Type,
		Buyer_Type,
		Byr_Segment,
		CAL.AGE_FOR_RTL_YEAR_ID,
		EVENT_SITEID,
		--Discovery
		sum(Views_) as Views,

		--Engagement
		sum(Quality_Views_) as Quality_Views,

		--Bidding
		sum(Bidding_Views_) as Bidding_Views,

		--Transaction
		sum(Buying_Views_) as Buying_Views,

		--Purchase
		sum(SI_PRE_DURING_WEEK_) as BI,

		--Sales
		sum(GMV_PRE_DURING_WEEK_) as GMB,
		
		--Overall Bidding Views
		sum(Overall_Bidding_Views_) as Overall_Bidding_Views

	FROM p_ksarla_live_t.ebay_Live_Demand_Funnel_Grouping_Sets AS BASE 
		INNER JOIN 
			( 
				SELECT 
					DISTINCT 
						AGE_FOR_RTL_YEAR_ID, 
						RTL_QTR_OF_RTL_YEAR_ID, 
						AGE_FOR_RTL_QTR_ID, 
						RETAIL_WEEK, 
						AGE_FOR_RTL_WEEK_ID, 
						RETAIL_YEAR
				FROM ACCESS_VIEWS.DW_CAL_DT
				WHERE AGE_FOR_RTL_YEAR_ID IN (1, 0, -1, -2, -3)
			) AS CAL 
		ON BASE.RETAIL_YEAR = CAL.RETAIL_YEAR
		AND BASE.RETAIL_WEEK = CAL.RETAIL_WEEK
	WHERE CAL.AGE_FOR_RTL_YEAR_ID IN (0, -1)
	AND CAL.AGE_FOR_RTL_WEEK_ID <= -1
	Group by 1,2,3,4,5,6,7,8,9,10,11
),

Quarterly AS (
	SELECT
		CASE 
			WHEN CAL.AGE_FOR_RTL_QTR_ID = (SELECT MAX(AGE_FOR_RTL_QTR_ID) FROM ACCESS_VIEWS.DW_CAL_DT WHERE AGE_FOR_RTL_WEEK_ID = -1) THEN CAL.RETAIL_YEAR || "Q" ||CAL.RTL_QTR_OF_RTL_YEAR_ID||"TW" 
			ELSE CAL.RETAIL_YEAR || "Q" ||CAL.RTL_QTR_OF_RTL_YEAR_ID
		END AS Label,
		'Retail Quarter' AS TIME_FRAME,
		VERTICAL,
		Category,
		Viewer_Traffic_Source_Group,
		Viewer_Traffic_Source,
		Viewer_Type,
		Buyer_Type,
		Byr_Segment,
		CAL.AGE_FOR_RTL_YEAR_ID,
		EVENT_SITEID,
		--Discovery
		sum(Views_)/count(distinct BASE.RETAIL_WEEK) as Views,

		--Engagement
		sum(Quality_Views_)/count(distinct BASE.RETAIL_WEEK) as Quality_Views,

		--Bidding
		sum(Bidding_Views_)/count(distinct BASE.RETAIL_WEEK) as Bidding_Views,

		--Transaction
		sum(Buying_Views_)/count(distinct BASE.RETAIL_WEEK) as Buying_Views,

		--Purchase
		sum(SI_PRE_DURING_WEEK_)/count(distinct BASE.RETAIL_WEEK) as BI,

		--Sales
		sum(GMV_PRE_DURING_WEEK_)/count(distinct BASE.RETAIL_WEEK) as GMB,
		
		--Overall Bidding Views
		sum(Overall_Bidding_Views_) as Overall_Bidding_Views

	FROM p_ksarla_live_t.ebay_Live_Demand_Funnel_Grouping_Sets AS BASE
		INNER JOIN 
					( 
						SELECT 
							DISTINCT 
								AGE_FOR_RTL_YEAR_ID, 
								RTL_QTR_OF_RTL_YEAR_ID, 
								AGE_FOR_RTL_QTR_ID, 
								RETAIL_WEEK, 
								AGE_FOR_RTL_WEEK_ID, 
								RETAIL_YEAR
						FROM ACCESS_VIEWS.DW_CAL_DT
						WHERE AGE_FOR_RTL_YEAR_ID IN (1, 0, -1, -2, -3)
					) AS CAL 
				ON BASE.RETAIL_YEAR = CAL.RETAIL_YEAR
				AND BASE.RETAIL_WEEK = CAL.RETAIL_WEEK
		WHERE CAL.AGE_FOR_RTL_YEAR_ID IN (0, -1)
		AND CAL.AGE_FOR_RTL_WEEK_ID <= -1
	Group by 1,2,3,4,5,6,7,8,9,10,11
)
,

Yearly AS (
	SELECT
		CASE 
			WHEN CAL.AGE_FOR_RTL_YEAR_ID = (SELECT MAX(AGE_FOR_RTL_YEAR_ID) FROM ACCESS_VIEWS.DW_CAL_DT WHERE AGE_FOR_RTL_WEEK_ID = -1) THEN CAL.RETAIL_YEAR||"YTW" 
			ELSE CAL.RETAIL_YEAR
		END as Label,
		'Retail Year' AS TIME_FRAME,
		VERTICAL,
		Category,
		Viewer_Traffic_Source_Group,
		Viewer_Traffic_Source,
		Viewer_Type,
		Buyer_Type,
		Byr_Segment,
		CAL.AGE_FOR_RTL_YEAR_ID,
		EVENT_SITEID,

		--Discovery
		sum(Views_)/count(distinct BASE.RETAIL_WEEK) as Views,

		--Engagement
		sum(Quality_Views_)/count(distinct BASE.RETAIL_WEEK) as Quality_Views,

		--Bidding
		sum(Bidding_Views_)/count(distinct BASE.RETAIL_WEEK) as Bidding_Views,

		--Transaction
		sum(Buying_Views_)/count(distinct BASE.RETAIL_WEEK) as Buying_Views,

		--Purchase
		sum(SI_PRE_DURING_WEEK_)/count(distinct BASE.RETAIL_WEEK) as BI,

		--Sales
		sum(GMV_PRE_DURING_WEEK_)/count(distinct BASE.RETAIL_WEEK) as GMB,
		
		--Overall Bidding Views
		sum(Overall_Bidding_Views_) as Overall_Bidding_Views

	FROM p_ksarla_live_t.ebay_Live_Demand_Funnel_Grouping_Sets AS BASE 
		INNER JOIN 
				( 
					SELECT 
						DISTINCT 
							AGE_FOR_RTL_YEAR_ID, 
							RTL_QTR_OF_RTL_YEAR_ID, 
							AGE_FOR_RTL_QTR_ID, 
							RETAIL_WEEK, 
							AGE_FOR_RTL_WEEK_ID, 
							RETAIL_YEAR
					FROM ACCESS_VIEWS.DW_CAL_DT
					WHERE AGE_FOR_RTL_YEAR_ID IN (1, 0, -1, -2, -3)
				) AS CAL 
			ON BASE.RETAIL_YEAR = CAL.RETAIL_YEAR
			AND BASE.RETAIL_WEEK = CAL.RETAIL_WEEK
	WHERE CAL.AGE_FOR_RTL_YEAR_ID >= -1
	AND CAL.AGE_FOR_RTL_WEEK_ID <= -1
	Group by 1,2,3,4,5,6,7,8,9,10,11
),

T4W AS (
	SELECT
		"T4W" as Label,
		'Retail Week' AS TIME_FRAME,
		VERTICAL,
		Category,
		Viewer_Traffic_Source_Group,
		Viewer_Traffic_Source,
		Viewer_Type,
		Buyer_Type,
		Byr_Segment,
		CAL.AGE_FOR_RTL_YEAR_ID,
		EVENT_SITEID,

		--Discovery
		sum(Views_)/count(distinct BASE.RETAIL_WEEK) as Views,

		--Engagement
		sum(Quality_Views_)/count(distinct BASE.RETAIL_WEEK) as Quality_Views,

		--Bidding
		sum(Bidding_Views_)/count(distinct BASE.RETAIL_WEEK) as Bidding_Views,

		--Transaction
		sum(Buying_Views_)/count(distinct BASE.RETAIL_WEEK) as Buying_Views,

		--Purchase
		sum(SI_PRE_DURING_WEEK_)/count(distinct BASE.RETAIL_WEEK) as BI,

		--Sales
		sum(GMV_PRE_DURING_WEEK_)/count(distinct BASE.RETAIL_WEEK) as GMB,
		
		--Overall Bidding Views
		sum(Overall_Bidding_Views_) as Overall_Bidding_Views

	FROM p_ksarla_live_t.ebay_Live_Demand_Funnel_Grouping_Sets AS BASE
	INNER JOIN 
				( 
					SELECT 
						DISTINCT 
							AGE_FOR_RTL_YEAR_ID, 
							RTL_QTR_OF_RTL_YEAR_ID, 
							AGE_FOR_RTL_QTR_ID, 
							RETAIL_WEEK, 
							AGE_FOR_RTL_WEEK_ID, 
							RETAIL_YEAR
					FROM ACCESS_VIEWS.DW_CAL_DT
					WHERE AGE_FOR_RTL_YEAR_ID IN (1, 0, -1, -2, -3)
				) AS CAL 
			ON BASE.RETAIL_YEAR = CAL.RETAIL_YEAR
			AND BASE.RETAIL_WEEK = CAL.RETAIL_WEEK
	WHERE CAL.AGE_FOR_RTL_WEEK_ID between -5 and -2
	Group by 1,2,3,4,5,6,7,8,9,10,11
)

SELECT 
	a.*
FROM 
(
-- WEEKLY
	SELECT *
	FROM WEEKLY

-- Quarterly
	UNION ALL
	
	SELECT *
	FROM Quarterly
	
-- Yearly
	UNION ALL
	
	SELECT *
	FROM YEARLY
	
-- Last 4 week
	UNION ALL
	
	SELECT *
	FROM T4W

) a
;