/* =====================================================================================
   HOTEL BOOKING CANCELLATIONS: DRIVERS, REVENUE AT RISK & PREVENTION
   SQL analysis code

   Dataset : Hotel Booking Demand (Antonio, Almeida & Nunes, 2019), 119,390 bookings
   Table   : hotel_bookings  (the raw CSV imported as-is, one row per booking)
   Dialect : written and tested in SQLite; uses standard SQL (CTEs, CASE, window
             functions) and runs in PostgreSQL / MySQL 8 with minimal changes.

   How to load the data:
     1. Run the CREATE TABLE statement below (PART 0)
     2. Import data/hotels.csv into hotel_bookings
          - sqlite3 command line:  .import --csv --skip 1 data/hotels.csv hotel_bookings
          - DB Browser for SQLite: File > Import > Table from CSV file (header row on)
     3. Run the queries part by part
   ===================================================================================== */


/* -------------------------------------------------------------------------------------
   PART 0 - TABLE DEFINITION
   Columns are typed so that numbers are compared as numbers, not as text.
   children contains the text 'NA' and country / agent / company the text 'NULL' for missing values,
   which is handled in the cleaning step (PART 2).
   ------------------------------------------------------------------------------------- */
DROP TABLE IF EXISTS hotel_bookings;
CREATE TABLE hotel_bookings (
    hotel                           TEXT,     -- 'City Hotel' (Lisbon) or 'Resort Hotel' (Algarve)
    is_canceled                     INTEGER,  -- 1 = booking was cancelled, 0 = not cancelled
    lead_time                       INTEGER,  -- days between booking date and arrival date
    arrival_date_year               INTEGER,
    arrival_date_month              TEXT,     -- 'January' ... 'December'
    arrival_date_week_number        INTEGER,
    arrival_date_day_of_month       INTEGER,
    stays_in_weekend_nights         INTEGER,
    stays_in_week_nights            INTEGER,
    adults                          INTEGER,
    children                        INTEGER,
    babies                          INTEGER,
    meal                            TEXT,     -- BB = bed & breakfast, HB = half board, FB = full board, SC = no meal
    country                         TEXT,     -- ISO 3-letter country code of the guest
    market_segment                  TEXT,     -- e.g. Online TA (online travel agent), Groups, Direct, Corporate
    distribution_channel            TEXT,
    is_repeated_guest               INTEGER,  -- 1 = guest has stayed before
    previous_cancellations          INTEGER,  -- number of earlier bookings this guest cancelled
    previous_bookings_not_canceled  INTEGER,
    reserved_room_type              TEXT,
    assigned_room_type              TEXT,
    booking_changes                 INTEGER,
    deposit_type                    TEXT,     -- No Deposit / Non Refund / Refundable
    agent                           TEXT,     -- ID of the travel agent (anonymised)
    company                         TEXT,     -- ID of the company (anonymised)
    days_in_waiting_list            INTEGER,
    customer_type                   TEXT,     -- Transient, Transient-Party, Contract, Group
    adr                             REAL,     -- Average Daily Rate: price per night in EUR
    required_car_parking_spaces     INTEGER,
    total_of_special_requests       INTEGER,  -- e.g. twin beds, high floor
    reservation_status              TEXT,     -- Check-Out / Canceled / No-Show
    reservation_status_date         TEXT
);


/* -------------------------------------------------------------------------------------
   PART 1 - EXPLORING THE DATA
   ------------------------------------------------------------------------------------- */

-- 1.1 Preview the data
-- Retrieves the first rows to understand the structure and content of each column
SELECT *
FROM hotel_bookings
LIMIT 10;


-- 1.2 Size and scope of the dataset
-- Counts total bookings, the hotels covered and the arrival period
-- MIN / MAX on the year columns show that the data starts in 2015 and ends in 2017
SELECT
    COUNT(*)                      AS Total_Bookings,      -- number of rows (one row = one booking)
    COUNT(DISTINCT hotel)         AS Hotels,              -- City Hotel and Resort Hotel
    COUNT(DISTINCT CASE WHEN country <> 'NULL' THEN country END) AS Countries,  -- 'NULL' (missing) is not a country
    MIN(arrival_date_year)        AS First_Year,
    MAX(arrival_date_year)        AS Last_Year
FROM hotel_bookings;


-- 1.3 Check which months each year covers
-- Important because 2015 and 2017 are partial years, so yearly totals cannot be compared directly
SELECT
    arrival_date_year             AS Arrival_Year,
    COUNT(DISTINCT arrival_date_month) AS Months_Covered,  -- 12 = full year
    COUNT(*)                      AS Bookings
FROM hotel_bookings
GROUP BY arrival_date_year
ORDER BY arrival_date_year;


-- 1.4 Fair comparison between years: same months only (January - August)
-- 2017 has 28% fewer bookings than 2016 in total, but only because it ends in August
SELECT
    arrival_date_year             AS Arrival_Year,
    COUNT(*)                      AS Bookings_Jan_Aug
FROM hotel_bookings
WHERE arrival_date_year BETWEEN 2016 AND 2017
  AND arrival_date_month IN ('January', 'February', 'March', 'April',
                             'May', 'June', 'July', 'August')
GROUP BY arrival_date_year;
-- Result: 36,796 (2016) vs 40,687 (2017) = +10.6%


/* -------------------------------------------------------------------------------------
   PART 2 - DATA QUALITY CHECKS & CLEANING
   ------------------------------------------------------------------------------------- */

-- 2.1 Missing values in the columns that can be empty
-- In the CSV, missing values are written as the text 'NA' (children) or 'NULL' (country, agent, company)
SELECT
    SUM(CASE WHEN children IS NULL OR children = 'NA'   THEN 1 ELSE 0 END) AS Missing_Children,
    SUM(CASE WHEN country  IS NULL OR country  = 'NULL' THEN 1 ELSE 0 END) AS Missing_Country,
    SUM(CASE WHEN agent    IS NULL OR agent    = 'NULL' THEN 1 ELSE 0 END) AS Missing_Agent,   -- booked without a travel agent
    SUM(CASE WHEN company  IS NULL OR company  = 'NULL' THEN 1 ELSE 0 END) AS Missing_Company  -- not a company booking
FROM hotel_bookings;


-- 2.2 Logically invalid records
-- A booking with zero guests, a negative price or a price above 1,000 EUR per night is a data-entry error
SELECT
    SUM(CASE WHEN adults + COALESCE(CAST(NULLIF(children, 'NA') AS INTEGER), 0) + babies = 0
             THEN 1 ELSE 0 END)                                   AS Zero_Guest_Bookings,
    SUM(CASE WHEN adr < 0    THEN 1 ELSE 0 END)                   AS Negative_Price,
    SUM(CASE WHEN adr > 1000 THEN 1 ELSE 0 END)                   AS Price_Above_1000,
    SUM(CASE WHEN adr = 0    THEN 1 ELSE 0 END)                   AS Zero_Price,
    SUM(CASE WHEN stays_in_weekend_nights + stays_in_week_nights = 0
             THEN 1 ELSE 0 END)                                   AS Zero_Night_Stays
FROM hotel_bookings;


-- 2.3 Highest prices
-- Checks whether the maximum price is a real (expensive) booking or an error:
-- the top value is 5,400 EUR and the next one is 510 EUR, so 5,400 is treated as an error
SELECT hotel, adr, adults, stays_in_week_nights, is_canceled
FROM hotel_bookings
ORDER BY adr DESC
LIMIT 5;


-- 2.4 Who are the bookings with a price of 0?
-- A price of 0 can be real (free / complimentary stays), so these rows are checked before deciding
SELECT
    market_segment,
    COUNT(*)                                                             AS Bookings,
    SUM(CASE WHEN stays_in_weekend_nights + stays_in_week_nights = 0
             THEN 1 ELSE 0 END)                                          AS Zero_Night_Bookings
FROM hotel_bookings
WHERE adr = 0
GROUP BY market_segment
ORDER BY Bookings DESC;
-- About a third are 'Complementary' (free stays) and many have 0 nights: these rows are kept


-- 2.5 Create a clean view used by every query that follows
-- * removes the 182 invalid rows found above (0.15% of the data)
-- * fills missing children with 0 and missing country with 'Unknown'
-- * adds calculated columns: total nights, total guests, month number and booking value
-- Booking value = average daily rate (ADR) x number of nights = room revenue of the booking
-- Note: duplicate rows are intentionally kept. The dataset has no booking ID, so identical
-- rows are expected for group bookings made on the same day at the same price.
DROP VIEW IF EXISTS bookings_clean;
CREATE VIEW bookings_clean AS
SELECT
    hotel,
    is_canceled,
    lead_time,
    arrival_date_year,
    arrival_date_month,
    CASE arrival_date_month
        WHEN 'January'   THEN 1  WHEN 'February' THEN 2  WHEN 'March'    THEN 3
        WHEN 'April'     THEN 4  WHEN 'May'      THEN 5  WHEN 'June'     THEN 6
        WHEN 'July'      THEN 7  WHEN 'August'   THEN 8  WHEN 'September' THEN 9
        WHEN 'October'   THEN 10 WHEN 'November' THEN 11 WHEN 'December' THEN 12
    END                                                            AS arrival_month_num,
    stays_in_weekend_nights + stays_in_week_nights                 AS nights,
    adults + COALESCE(CAST(NULLIF(children, 'NA') AS INTEGER), 0) + babies AS guests,
    meal,
    CASE WHEN country IS NULL OR country = 'NULL' THEN 'Unknown' ELSE country END AS country,
    market_segment,
    distribution_channel,
    is_repeated_guest,
    previous_cancellations,
    deposit_type,
    customer_type,
    adr,
    adr * (stays_in_weekend_nights + stays_in_week_nights)         AS booking_value,
    total_of_special_requests,
    required_car_parking_spaces,
    reservation_status
FROM hotel_bookings
WHERE adults + COALESCE(CAST(NULLIF(children, 'NA') AS INTEGER), 0) + babies > 0
  AND adr BETWEEN 0 AND 1000;


/* -------------------------------------------------------------------------------------
   PART 3 - HOW BIG IS THE PROBLEM?
   ------------------------------------------------------------------------------------- */

-- 3.1 Headline KPIs for each hotel and in total
-- Cancellation rate = cancelled bookings / all bookings. AVG of a 0/1 column gives that share directly.
-- Average ADR and lead time are calculated on all bookings to describe the typical reservation
SELECT
    COALESCE(hotel, 'Total')                        AS Hotel,
    COUNT(*)                                        AS Bookings,
    SUM(is_canceled)                                AS Cancelled,
    ROUND(100.0 * AVG(is_canceled), 1)              AS Cancel_Rate_Pct,
    ROUND(AVG(adr), 2)                              AS Avg_Price_Per_Night,
    ROUND(AVG(lead_time), 1)                        AS Avg_Lead_Time_Days,
    ROUND(AVG(nights), 2)                           AS Avg_Nights
FROM bookings_clean
GROUP BY hotel
UNION ALL
SELECT 'Total', COUNT(*), SUM(is_canceled), ROUND(100.0 * AVG(is_canceled), 1),
       ROUND(AVG(adr), 2), ROUND(AVG(lead_time), 1), ROUND(AVG(nights), 2)
FROM bookings_clean;


-- 3.2 Final status of every booking
-- Separates true cancellations from no-shows (guests who neither cancelled nor arrived)
SELECT
    reservation_status                               AS Status,
    COUNT(*)                                         AS Bookings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS Pct_Of_All   -- window function: share of the grand total
FROM bookings_clean
GROUP BY reservation_status
ORDER BY Bookings DESC;


-- 3.3 Room revenue booked vs revenue lost to cancellations
-- Lost value is an upper bound: the data does not show whether a cancelled room was re-sold
-- Lost per year = lost value / 26 months of data x 12
SELECT
    hotel                                                                     AS Hotel,
    ROUND(SUM(booking_value), 0)                                              AS Booked_Value_EUR,
    ROUND(SUM(CASE WHEN is_canceled = 1 THEN booking_value ELSE 0 END), 0)    AS Cancelled_Value_EUR,
    ROUND(100.0 * SUM(CASE WHEN is_canceled = 1 THEN booking_value ELSE 0 END)
                / SUM(booking_value), 1)                                      AS Pct_Value_Lost,
    ROUND(SUM(CASE WHEN is_canceled = 1 THEN booking_value ELSE 0 END) / 26.0 * 12, 0) AS Lost_Per_Year_EUR
FROM bookings_clean
GROUP BY hotel
ORDER BY Cancelled_Value_EUR DESC;


-- 3.4 Cancellation rate over time (by arrival month)
-- Tracks whether the problem is getting better or worse across the 26 months of data
SELECT
    arrival_date_year                               AS Year,
    arrival_month_num                               AS Month,
    hotel                                           AS Hotel,
    COUNT(*)                                        AS Bookings,
    ROUND(100.0 * AVG(is_canceled), 1)              AS Cancel_Rate_Pct
FROM bookings_clean
GROUP BY arrival_date_year, arrival_month_num, hotel
ORDER BY arrival_date_year, arrival_month_num, hotel;


/* -------------------------------------------------------------------------------------
   PART 4 - WHICH BOOKINGS CANCEL?
   ------------------------------------------------------------------------------------- */

-- 4.1 Lead time (days between booking and arrival) grouped into buckets
-- The bucket label is prefixed with a number so that ORDER BY keeps the logical order
SELECT
    CASE
        WHEN lead_time <= 7   THEN '1) 0-7 days'
        WHEN lead_time <= 30  THEN '2) 8-30 days'
        WHEN lead_time <= 90  THEN '3) 31-90 days'
        WHEN lead_time <= 180 THEN '4) 91-180 days'
        WHEN lead_time <= 365 THEN '5) 181-365 days'
        ELSE                       '6) 365+ days'
    END                                                                        AS Lead_Time_Bucket,
    COUNT(*)                                                                   AS Bookings,
    ROUND(100.0 * AVG(is_canceled), 1)                                         AS Cancel_Rate_Pct,
    ROUND(100.0 * AVG(CASE WHEN hotel = 'City Hotel'   THEN is_canceled END), 1) AS City_Cancel_Rate_Pct,
    ROUND(100.0 * AVG(CASE WHEN hotel = 'Resort Hotel' THEN is_canceled END), 1) AS Resort_Cancel_Rate_Pct
FROM bookings_clean
GROUP BY Lead_Time_Bucket
ORDER BY Lead_Time_Bucket;


-- 4.2 Market segment: cancellation rate AND share of the lost revenue
-- A segment can have an average cancellation rate but still cause most of the losses because of its size
-- The CTE aggregates per segment; the window function SUM() OVER () computes the grand total for the share
WITH segment_stats AS (
    SELECT
        market_segment,
        COUNT(*)                                                       AS Bookings,
        AVG(is_canceled)                                               AS Cancel_Rate,
        SUM(CASE WHEN is_canceled = 1 THEN booking_value ELSE 0 END)   AS Lost_Value
    FROM bookings_clean
    WHERE market_segment <> 'Undefined'                                -- 2 rows only
    GROUP BY market_segment
)
SELECT
    market_segment                                                     AS Market_Segment,
    Bookings,
    ROUND(100.0 * Cancel_Rate, 1)                                      AS Cancel_Rate_Pct,
    ROUND(Lost_Value, 0)                                               AS Lost_Value_EUR,
    ROUND(100.0 * Lost_Value / SUM(Lost_Value) OVER (), 1)             AS Pct_Of_Lost_Value
FROM segment_stats
ORDER BY Lost_Value DESC;


-- 4.3 Deposit type
-- Expectation: bookings with a non-refundable deposit should cancel the LEAST
SELECT
    deposit_type                                    AS Deposit_Type,
    COUNT(*)                                        AS Bookings,
    ROUND(100.0 * AVG(is_canceled), 1)              AS Cancel_Rate_Pct
FROM bookings_clean
GROUP BY deposit_type
ORDER BY Cancel_Rate_Pct DESC;


-- 4.4 Who are the "Non Refund" bookings? (investigating the result of 4.3)
-- Compares the profile of non-refundable bookings with all other bookings
SELECT
    CASE WHEN deposit_type = 'Non Refund' THEN 'Non Refund' ELSE 'All other bookings' END AS Booking_Group,
    COUNT(*)                                                                         AS Bookings,
    ROUND(100.0 * AVG(CASE WHEN country = 'PRT' THEN 1.0 ELSE 0 END), 1)            AS Pct_From_Portugal,
    ROUND(100.0 * AVG(CASE WHEN market_segment IN ('Groups', 'Offline TA/TO')
                           THEN 1.0 ELSE 0 END), 1)                                  AS Pct_Groups_Or_Tour_Operators,
    ROUND(AVG(lead_time), 0)                                                         AS Avg_Lead_Time_Days,
    ROUND(AVG(total_of_special_requests), 2)                                         AS Avg_Special_Requests,
    ROUND(100.0 * AVG(CASE WHEN hotel = 'City Hotel' THEN 1.0 ELSE 0 END), 1)       AS Pct_City_Hotel
FROM bookings_clean
GROUP BY Booking_Group;


-- 4.5 Guest behaviour and history signals
-- Each block turns one attribute into Yes/No and returns its cancellation rate; UNION ALL stacks them in one table
SELECT 'Made a special request' AS Signal,
       CASE WHEN total_of_special_requests > 0 THEN 'Yes' ELSE 'No' END AS Value,
       COUNT(*) AS Bookings, ROUND(100.0 * AVG(is_canceled), 1) AS Cancel_Rate_Pct
FROM bookings_clean GROUP BY Value
UNION ALL
SELECT 'Repeat guest',
       CASE WHEN is_repeated_guest = 1 THEN 'Yes' ELSE 'No' END,
       COUNT(*), ROUND(100.0 * AVG(is_canceled), 1)
FROM bookings_clean GROUP BY 2
UNION ALL
SELECT 'Has cancelled before',
       CASE WHEN previous_cancellations > 0 THEN 'Yes' ELSE 'No' END,
       COUNT(*), ROUND(100.0 * AVG(is_canceled), 1)
FROM bookings_clean GROUP BY 2
UNION ALL
SELECT 'Requested parking',
       CASE WHEN required_car_parking_spaces > 0 THEN 'Yes' ELSE 'No' END,
       COUNT(*), ROUND(100.0 * AVG(is_canceled), 1)
FROM bookings_clean GROUP BY 2;
-- Note: 'Requested parking = Yes' shows 0% cancellations. Parking is recorded at check-in,
-- so only guests who actually arrived can have it. This is a recording artefact, not an insight.


-- 4.6 Cancellation rate by number of special requests
SELECT
    CASE WHEN total_of_special_requests >= 3 THEN '3+'
         ELSE CAST(total_of_special_requests AS TEXT) END   AS Special_Requests,
    COUNT(*)                                                AS Bookings,
    ROUND(100.0 * AVG(is_canceled), 1)                      AS Cancel_Rate_Pct
FROM bookings_clean
GROUP BY Special_Requests
ORDER BY Special_Requests;


-- 4.7 Top 10 countries by bookings, with and without the non-refundable blocks
-- Shows how much of each country's cancellation rate comes from the blocks found in 4.4
SELECT
    country                                                                    AS Country,
    COUNT(*)                                                                   AS Bookings,
    ROUND(100.0 * AVG(is_canceled), 1)                                         AS Cancel_Rate_Pct,
    ROUND(100.0 * AVG(CASE WHEN deposit_type <> 'Non Refund' THEN is_canceled END), 1)
                                                                               AS Cancel_Rate_Excl_Non_Refund_Pct
FROM bookings_clean
GROUP BY country
ORDER BY Bookings DESC
LIMIT 10;


-- 4.8 Combined view: market segment x lead time (cancellation rate matrix)
-- Used for the conditional-formatting heat map; shows where the two risk factors overlap
SELECT
    market_segment                                                                           AS Market_Segment,
    ROUND(100.0 * AVG(CASE WHEN lead_time <= 30                 THEN is_canceled END), 1)   AS Lead_0_30_Pct,
    ROUND(100.0 * AVG(CASE WHEN lead_time BETWEEN 31 AND 90     THEN is_canceled END), 1)   AS Lead_31_90_Pct,
    ROUND(100.0 * AVG(CASE WHEN lead_time BETWEEN 91 AND 180    THEN is_canceled END), 1)   AS Lead_91_180_Pct,
    ROUND(100.0 * AVG(CASE WHEN lead_time > 180                 THEN is_canceled END), 1)   AS Lead_180_Plus_Pct
FROM bookings_clean
WHERE market_segment IN ('Online TA', 'Offline TA/TO', 'Groups', 'Direct', 'Corporate')
GROUP BY market_segment
ORDER BY Lead_180_Plus_Pct DESC;


/* -------------------------------------------------------------------------------------
   PART 5 - SEASONALITY & PRICING
   ------------------------------------------------------------------------------------- */

-- 5.1 Monthly demand and price per hotel
-- Bookings are divided by the number of years each month appears in the data (2 or 3) to get a fair average
-- Average price is calculated on stays that actually happened (not cancelled, at least one night)
WITH monthly AS (
    SELECT
        hotel,
        arrival_month_num,
        COUNT(*)                                                         AS Bookings,
        COUNT(DISTINCT arrival_date_year)                                AS Years_In_Data,
        AVG(CASE WHEN is_canceled = 0 AND nights > 0 THEN adr END)       AS Avg_Price_Kept
    FROM bookings_clean
    GROUP BY hotel, arrival_month_num
)
SELECT
    hotel                                            AS Hotel,
    arrival_month_num                                AS Month,
    ROUND(1.0 * Bookings / Years_In_Data, 0)         AS Avg_Bookings_Per_Year,
    ROUND(Avg_Price_Kept, 2)                         AS Avg_Price_Per_Night
FROM monthly
ORDER BY hotel, arrival_month_num;


-- 5.2 Top 3 months by lost revenue in each hotel
-- ROW_NUMBER() ranks the months inside each hotel (PARTITION BY hotel) by the value of cancelled bookings
WITH monthly_loss AS (
    SELECT
        hotel,
        arrival_date_month,
        SUM(CASE WHEN is_canceled = 1 THEN booking_value ELSE 0 END)   AS Lost_Value,
        ROW_NUMBER() OVER (PARTITION BY hotel
                           ORDER BY SUM(CASE WHEN is_canceled = 1 THEN booking_value ELSE 0 END) DESC) AS Loss_Rank
    FROM bookings_clean
    GROUP BY hotel, arrival_date_month
)
SELECT
    hotel                       AS Hotel,
    Loss_Rank                   AS Rank,
    arrival_date_month          AS Month,
    ROUND(Lost_Value, 0)        AS Lost_Value_EUR
FROM monthly_loss
WHERE Loss_Rank <= 3
ORDER BY hotel, Loss_Rank;


-- 5.3 Value of an average cancelled booking by season
-- Summer (Jun-Aug) vs the rest of the year: how much does one cancellation cost?
SELECT
    hotel                                                               AS Hotel,
    CASE WHEN arrival_month_num IN (6, 7, 8) THEN 'Summer (Jun-Aug)'
         ELSE 'Rest of year' END                                        AS Season,
    COUNT(*)                                                            AS Cancelled_Bookings,
    ROUND(AVG(booking_value), 0)                                        AS Avg_Value_Per_Cancellation_EUR
FROM bookings_clean
WHERE is_canceled = 1
GROUP BY hotel, Season
ORDER BY hotel, Season DESC;
