/*
=====================================================================
Stored Procedure: Load Silver Layer (Bronze -> silver)
=====================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, transform, Load) process to
    populate the 'silver' schema tables from the 'bronze schema.
  Action Performed:
    - Truncates Siver Tables.
    - Inserts transformed and cleansed data from Bronze into Silver tables.

Parameters:
    None.
    This stored procedure does not accept ny parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
=====================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS 
BEGIN
	DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	BEGIN TRY
		SET @batch_start_time = GETDATE();
		PRINT '============================================';
		PRINT 'LOADING SILVER LAYER';
		PRINT '============================================';

		PRINT '--------------------------------------------';
		PRINT 'TRANSFORMING AND LOADING CRM TABLES';
		PRINT '--------------------------------------------';

		SET @start_time = GETDATE()
			PRINT '>> Truncating Table: silver.crm_cust_info'
			TRUNCATE TABLE silver.crm_cust_info;

			PRINT '>> Inserting Data Into: silver.crm_cust_info';
			INSERT INTO silver.crm_cust_info (
				cst_id,
				cst_key,
				cst_firstname,
				cst_lastname,
				cst_material_status,
				cst_gndr,
				cst_create_date
				)

			SELECT 
				cst_id,
				cst_key,
				TRIM(cst_firstname) AS cst_firstname,
				TRIM(cst_lastname) AS cst_lastname,
				CASE 
					WHEN TRIM(UPPER(cst_material_status)) = 'S' THEN 'Single'
					WHEN TRIM(UPPER(cst_material_status)) = 'M' THEN 'Married'
					ELSE NULL
				END cst_material_status,
				CASE 
					WHEN TRIM(UPPER(cst_gndr)) = 'F' THEN 'Female'
					WHEN TRIM(UPPER(cst_gndr)) = 'M' THEN 'Male'
					ELSE NULL
				END cst_gndr,
				cst_create_date
			FROM (
				SELECT 
					*,
					ROW_NUMBER() OVER (	
						PARTITION BY cst_id ORDER BY cst_create_date DESC
					) AS flag_last
				FROM BRONZE.crm_cust_info
			) t 
			WHERE flag_last = 1
		SET @end_time = GETDATE();
		PRINT '>> TRANSFORM AND LOAD DURATION: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' SECONDS';
		PRINT '---------------------------------------';


		SET @start_time = GETDATE()
			PRINT '>> Droping Table: silver.crm_prd_info'
			IF OBJECT_ID ('silver.crm_prd_info', 'U') IS NOT NULL
				DROP TABLE silver.crm_prd_info;

			PRINT '>> Updating the DDL and Inserting Data Into: silver.crm_prd_info';
			CREATE TABLE silver.crm_prd_info (
				prd_id INT,
				cat_id  NVARCHAR(50),
				prd_key NVARCHAR(50),
				prd_nm NVARCHAR(50),
				prd_cost INT, 
				prd_line  NVARCHAR(50),
				prd_start_dt DATE,
				prd_end_dt DATE,
				dwh_create_date DATETIME2 DEFAULT GETDATE()
			); -- Here we just update our DDL with the new cleansing columns (cat_id, prd_key, and set dtype for start/end_dt as date)

			INSERT INTO silver.crm_prd_info (
				prd_id,
				cat_id,
				prd_key,
				prd_nm,
				prd_cost,
				prd_line,
				prd_start_dt,
				prd_end_dt
				)

			SELECT 
				prd_id,
				REPLACE(
					SUBSTRING(prd_key, 1, 5),
					'-', '_'
				)AS cat_id,
				SUBSTRING(
					prd_key, 7, LEN(prd_key)
				)  AS prd_key,
				prd_nm,
				ISNULL(prd_cost, 0) AS prd_cost, -- In this case, only replace the null values if is authorized for the company
				CASE UPPER(TRIM(prd_line)) 
					WHEN 'M' THEN 'Mountain'
					WHEN 'R' THEN 'Road'
					WHEN 'S' THEN 'Other Sales'
					WHEN'T' THEN 'Touring'
					ELSE NULL
				END prd_line,
				CAST(prd_start_dt AS DATE) AS prd_start_dt,
				CAST(LEAD(prd_start_dt) 
					OVER (PARTITION BY prd_key ORDER BY prd_start_dt) -1 AS DATE
				) AS prd_end_dt -- All the dates in "prd_end_dt" were lower then the start date. For prd_end_dt we get next value based on the same prd_key.
			FROM bronze.crm_prd_info
		SET @end_time = GETDATE();
		PRINT '>> TRANSFORM AND LOAD DURATION: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' SECONDS';
		PRINT '---------------------------------------';


		SET @start_time = GETDATE()
			PRINT '>> Droping Table: silver.crm_sales_details'
			IF OBJECT_ID ('silver.crm_sales_details', 'U') IS NOT NULL
				DROP TABLE silver.crm_sales_details;

			PRINT '>> Updating the DDL and Inserting Data Into: silver.crm_sales_details';
			CREATE TABLE silver.crm_sales_details (
				sls_ord_num NVARCHAR(50),
				sls_prd_key NVARCHAR(50),
				sls_cust_id INT,
				sls_order_dt DATE,
				sls_ship_dt DATE,
				sls_due_dt DATE,
				sls_sales DECIMAL(10,2),
				sls_quantity INT,
				sls_price DECIMAL(10,2),
				dwh_create_date DATETIME2 DEFAULT GETDATE()
			); -- We update the DDL

			INSERT INTO silver.crm_sales_details (
				sls_ord_num,
				sls_prd_key,
				sls_cust_id,
				sls_order_dt,
				sls_ship_dt,
				sls_due_dt,
				sls_sales,
				sls_quantity,
				sls_price
			)

			SELECT 
				sls_ord_num,
				sls_prd_key,
				sls_cust_id,
				CASE 
					WHEN 
						sls_order_dt = 0 OR
						LEN(sls_order_dt) != 8 
					THEN NULL
					ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE) 
				END sls_order_dt,
				CASE 
					WHEN 
						sls_ship_dt = 0 OR
						LEN(sls_ship_dt) != 8 
					THEN NULL
					ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE) 
				END sls_ship_dt,
				CASE 
					WHEN 
						sls_due_dt = 0 OR
						LEN(sls_due_dt) != 8 
					THEN NULL
					ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE) 
				END sls_due_dt,
				CASE 
					WHEN 
						sls_sales IS NULL OR 
						sls_sales <= 0 OR 
						sls_sales != sls_quantity * ABS(sls_price)
					THEN sls_quantity * ABS(sls_price)
					ELSE sls_sales
				END sls_sales,
				sls_quantity,
				CASE
					WHEN 
						sls_price IS NULL OR 
						sls_price <= 0
					THEN CAST(sls_sales / NULLIF(sls_quantity, 0) AS DECIMAL(10,2))
					ELSE CAST(sls_price AS DECIMAL(10,2))
				END sls_price
			FROM bronze.crm_sales_details
		SET @end_time = GETDATE();
		PRINT '>> TRANSFORM AND LOAD DURATION: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' SECONDS';

		PRINT '--------------------------------------------';
		PRINT 'TRANSFORMING AND LOADING ERP TABLES';
		PRINT '--------------------------------------------';

		SET @start_time = GETDATE()
			PRINT '>> Truncating Table: silver.erp_cust_az12'
			TRUNCATE TABLE silver.erp_cust_az12;

			PRINT '>> Inserting Data Into: silver.erp_cust_az12';
			INSERT INTO silver.erp_cust_az12 (
				cid,
				bdate,
				gen
			)

			SELECT 
				CASE
					WHEN cid LIKE 'NAS%' 
						THEN SUBSTRING (cid, 4, LEN(cid))
					ELSE cid
				END cid,
				CASE 
					WHEN bdate > GETDATE() 
						THEN NULL
					ELSE bdate
				END bdate,
				CASE 
					WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
					WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
					ELSE 'N/A'
				END AS gen
			FROM bronze.erp_cust_az12
		SET @end_time = GETDATE();
		PRINT '>> TRANSFORM AND LOAD DURATION: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' SECONDS';
		PRINT '---------------------------------------';


		SET @start_time = GETDATE()
			PRINT '>> Truncating Table: silver.erp_loc_a101'
			TRUNCATE TABLE silver.erp_loc_a101;

			PRINT '>> Inserting Data Into: silver.erp_loc_a101';
			INSERT INTO silver.erp_loc_a101 (
				cid,
				cntry
			)

			SELECT 
				REPLACE(cid, '-', '') AS cid,
				CASE 
					WHEN TRIM(cntry) = 'DE' 
						THEN 'Germany'
					WHEN TRIM(cntry) IN ('US', 'USA')
						THEN 'United States'
					WHEN TRIM(cntry) = ''  OR cntry IS NULL
						THEN 'N/A'
					ELSE TRIM(cntry)
				END AS cntry
			FROM bronze.erp_loc_a101;
		SET @end_time = GETDATE();
		PRINT '>> TRANSFORM AND LOAD DURATION: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' SECONDS';
		PRINT '---------------------------------------';


		SET @start_time = GETDATE()
			PRINT '>> Truncating Table: silver.erp_px_cat_g1v2'
			TRUNCATE TABLE silver.erp_px_cat_g1v2;

			PRINT '>> Inserting Data Into: silver.erp_px_cat_g1v2';
			INSERT INTO silver.erp_px_cat_g1v2 (
				id,
				cat,
				subcat,
				maintenance
			)

			SELECT 
				id,
				cat,
				subcat,
				maintenance
			FROM bronze.erp_px_cat_g1v2
		SET @end_time = GETDATE();
		PRINT '>> TRANSFORM AND LOAD DURATION: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' SECONDS';
		PRINT '---------------------------------------';

		SET @batch_end_time = GETDATE();
		PRINT '============================================';
		PRINT '>> LOADING AND TRANFORMING SILVER LAYER IS COMPLETED';
		PRINT '>> TOTAL LOAD AND TRANSFORM DURATION: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' SECONDS';
		PRINT '============================================';
	END TRY
	BEGIN CATCH
		PRINT '============================================';
		PRINT 'ERROR OCCURED DURING LOADING/TRANFORMING SILVER LAYER';
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Number' + CAST(ERROR_NUMBER() AS NVARCHAR);
		PRINT '============================================';
	END CATCH
END 


