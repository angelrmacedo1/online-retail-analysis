-- Create database
CREATE DATABASE online_retail;
USE online_retail;

-- Create the main transactions table

CREATE TABLE transactions (
    InvoiceNo VARCHAR(20),
    StockCode VARCHAR(20),
    Description VARCHAR(255),
    Quantity INT,
    InvoiceDate VARCHAR(50), 
    UnitPrice DECIMAL(10, 2),
    CustomerID INT,
    Country VARCHAR(50)
);

-- Load CSV data into the transactions table

LOAD DATA LOCAL INFILE '/Users/Showalter/Desktop/online-retail-project/online_retail.csv'
INTO TABLE transactions
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Create a duplicate table for safe cleaning

CREATE TABLE transactions_2
 LIKE transactions;
 
INSERT INTO transactions_2 
SELECT *
 FROM transactions;
 
 -- Add an ID column for duplicate tracking

ALTER TABLE transactions_2 ADD COLUMN ID INT AUTO_INCREMENT PRIMARY KEY;

 -- Cleanning Process
 -- Fix InvoiceDate format

ALTER TABLE transactions_2 ADD COLUMN InvoiceDateNew DATETIME;

UPDATE transactions_2
SET InvoiceDateNew = STR_TO_DATE(InvoiceDate, '%m/%d/%y %H:%i');

ALTER TABLE transactions_2 DROP COLUMN InvoiceDate;
ALTER TABLE transactions_2 CHANGE COLUMN InvoiceDateNew InvoiceDate DATETIME;

-- Count duplicates
SELECT COUNT(*) AS total_duplicates
FROM (
  SELECT ROW_NUMBER() OVER (
           PARTITION BY InvoiceNo, StockCode, `Description`, Quantity, InvoiceDate, UnitPrice, CustomerID, Country
           ORDER BY id
         ) AS row_num
  FROM transactions_2
) AS duplicates
WHERE row_num > 1;

-- Remove duplicates
SET SQL_SAFE_UPDATES = 0;

DELETE FROM transactions_2
WHERE ID IN (
  SELECT ID FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY InvoiceNo, StockCode, `Description`, Quantity, InvoiceDate, UnitPrice, CustomerID, Country
             ORDER BY id
           ) AS row_num
    FROM transactions_2
  ) AS sub
  WHERE row_num > 1
);

SET SQL_SAFE_UPDATES = 1;

-- Confirm duplicates are gone
SELECT COUNT(*) AS duplicates_remaining
FROM (
  SELECT ROW_NUMBER() OVER (
           PARTITION BY InvoiceNo, StockCode, `Description`, Quantity, InvoiceDate, UnitPrice, CustomerID, Country
           ORDER BY id
         ) AS row_num
  FROM transactions_2
) AS check_dupes
WHERE row_num > 1;

-- Standardize text fields
SET SQL_SAFE_UPDATES = 0;

UPDATE transactions_2
SET `Description` = TRIM(`Description`),
    StockCode = TRIM(StockCode),
    Country = TRIM(Country);

SET SQL_SAFE_UPDATES = 1;

-- Check for Nulls

SELECT COUNT(*) AS NullCount, 
       CASE 
         WHEN InvoiceNo IS NULL THEN 'InvoiceNo'
         WHEN Description IS NULL THEN 'Description'
         WHEN Quantity IS NULL THEN 'Quantity'
         WHEN InvoiceDate IS NULL THEN 'InvoiceDate'
         ELSE 'Other'
       END AS NullField
FROM transactions_2
WHERE InvoiceNo IS NULL OR Description IS NULL OR Quantity IS NULL OR InvoiceDate IS NULL
GROUP BY NullField;

-- No nulls detected.

-- Remove Rows with Negative or Zero Quantity

SET SQL_SAFE_UPDATES = 0;

DELETE
 FROM transactions_2
WHERE Quantity <= 0;

DELETE
 FROM transactions_2
WHERE UnitPrice <= 0;

-- Removing Canceled Transactions

DELETE
 FROM transactions_2
WHERE InvoiceNo LIKE 'C%';

SET SQL_SAFE_UPDATES = 1;

-- Preparing Data for Analysis 
-- Add Revenue column

ALTER TABLE transactions_2 ADD COLUMN Revenue DECIMAL(15,2);
SET SQL_SAFE_UPDATES = 0;
UPDATE transactions_2
SET Revenue = Quantity * UnitPrice;

-- Add Year/Month/Day columns 

ALTER TABLE transactions_2
  ADD COLUMN InvoiceYear INT,
  ADD COLUMN InvoiceMonth INT,
  ADD COLUMN InvoiceDay INT;

UPDATE transactions_2
SET
  InvoiceYear = YEAR(InvoiceDate),
  InvoiceMonth = MONTH(InvoiceDate),
  InvoiceDay = DAY(InvoiceDate);
  
  -- Analyse Data
-- Top 10 Selling Products 
  SELECT Description,
  SUM(Quantity) AS TotalQty 
  FROM transactions_2 
  GROUP BY Description 
  ORDER BY TotalQty DESC LIMIT 10;

 -- Monthly Revenue Trend
  
  SELECT InvoiceYear, InvoiceMonth, SUM(Revenue) AS MonthlyRevenue
  FROM transactions_2 
  GROUP BY InvoiceYear, InvoiceMonth 
  ORDER BY InvoiceYear, InvoiceMonth;
  
  -- Top 10 Revenue Generating Producs

SELECT Description, 
ROUND(SUM(Revenue), 2) AS TotalRevenue,
SUM(Quantity) AS TotalUnits
FROM transactions_2
GROUP BY Description
ORDER BY TotalRevenue DESC LIMIT 10;

-- Sales by Country

SELECT Country,
       ROUND(SUM(Revenue), 2) AS TotalRevenue,
       COUNT(DISTINCT InvoiceNo) AS TotalOrders
FROM transactions_2
GROUP BY Country
ORDER BY TotalRevenue DESC;

-- 7. Time-of-Day or Day-of-Week Trends

SELECT 
  CASE 
    WHEN HOUR(InvoiceDate) BETWEEN 6 AND 11 THEN 'Morning'
    WHEN HOUR(InvoiceDate) BETWEEN 12 AND 17 THEN 'Afternoon'
    WHEN HOUR(InvoiceDate) BETWEEN 18 AND 21 THEN 'Evening'
    ELSE 'Late Night'
  END AS TimePeriod,
  
  COUNT(DISTINCT InvoiceNo) AS TotalOrders,
  ROUND(SUM(Revenue), 2) AS TotalRevenue
FROM transactions_2
GROUP BY TimePeriod
ORDER BY 
  FIELD(TimePeriod, 'Morning', 'Afternoon', 'Evening', 'Late Night');