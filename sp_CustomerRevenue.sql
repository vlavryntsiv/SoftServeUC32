CREATE PROCEDURE sp_CustomerRevenue
    @FromYear INT = NULL,
    @ToYear INT = NULL,
    @Period VARCHAR(10) = 'Year',
    @CustomerID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
	IF OBJECT_ID('ErrorLog', 'U') IS NULL
    BEGIN
        CREATE TABLE [ErrorLog]
        (
            [ErrorID] INT PRIMARY KEY IDENTITY,
            [ErrorNumber] INT,
            [ErrorSeverity] INT,
            [ErrorMessage] VARCHAR(255),
            [CustomerID] INT,
            [Period] VARCHAR(8),
            [CreatedAt] DATETIME
        );
    END

	BEGIN TRY
   -- Determine the default FromYear and ToYear if not provided
    DECLARE @TableName NVARCHAR(255), @CustName NVARCHAR(50);
    IF @CustomerID IS NULL
        SET @TableName = 'All_';
    ELSE
    BEGIN
        SELECT @CustName = [Customer]
        FROM [Dimension].[Customer] 
        WHERE [Customer Key] = @CustomerID;

        IF @CustName IS NULL
        BEGIN
            SET @CustName = '';
            SET @TableName = CONVERT(VARCHAR, @CustomerID) + '_';
        END
        ELSE
            SET @TableName = CONVERT(VARCHAR, @CustomerID) + '_' + @CustName + '_';
    END
	
    SET @TableName += CONVERT(VARCHAR, @FromYear) 
    + (CASE WHEN @FromYear != @ToYear THEN '_' + CONVERT(VARCHAR, @ToYear) ELSE '' END)
    + '_' + LEFT(@Period, 1);
 
    -- Drop the table if it exists
    IF OBJECT_ID(@TableName, 'U') IS NOT NULL
        EXEC('DROP TABLE [' + @TableName + ']');

    -- Create the table
    EXEC('CREATE TABLE [' + @TableName + '] (
        [CustomerID] INT,
        [CustomerName] VARCHAR(50),
        [Period] VARCHAR(8),
        [Revenue] NUMERIC(19,2)
    )');
	
    -- Determine the period and insert the data
	DECLARE @SQL NVARCHAR(MAX)  
	IF @CustomerID IS NOT NULL AND EXISTS (SELECT 1  FROM [Dimension].[Customer] c WHERE c.[Customer Key] = @CustomerID)
	BEGIN
		SET @SQL = 'INSERT INTO [' + @TableName + ']
        SELECT
            c.[Customer Key],
            c.[Customer],
            ';
            
    IF @Period IN ('Month', 'M')
        SET @SQL += 'FORMAT(s.[Invoice Date Key], ''MMM yyyy''), ';
    ELSE IF @Period IN ('Quarter', 'Q')
        SET @SQL += '''Q'' + DATENAME(QUARTER, s.[Invoice Date Key]) + '' '' + CONVERT(VARCHAR, YEAR(s.[Invoice Date Key])), ';
    ELSE
        SET @SQL += 'CONVERT(VARCHAR, YEAR(s.[Invoice Date Key])), ';

   set @SQL += 'ISNULL(SUM(s.[Quantity] * s.[Unit Price]), 0)
        FROM [Dimension].[Customer] c
        LEFT JOIN [Fact].[Sale] s ON c.[Customer Key] = s.[Customer Key]
        WHERE YEAR(s.[Invoice Date Key]) BETWEEN ' + CONVERT(VARCHAR, @FromYear) + ' AND ' + CONVERT(VARCHAR, @ToYear);

    IF @CustomerID IS NOT NULL
        SET @SQL += ' AND c.[Customer Key] = ' + CONVERT(VARCHAR, @CustomerID);

    SET @SQL += 
    ' GROUP BY c.[Customer Key], c.[Customer], ';

    IF @Period IN ('Month', 'M')
        SET @SQL += 'FORMAT(s.[Invoice Date Key], ''MMM yyyy'')';
    ELSE IF @Period IN ('Quarter', 'Q')
        SET @SQL += '''Q'' + DATENAME(QUARTER, s.[Invoice Date Key]) + '' '' + CONVERT(VARCHAR, YEAR(s.[Invoice Date Key]))';
    ELSE
        SET @SQL += 'YEAR(s.[Invoice Date Key])';
	END
		
	ELSE
	BEGIN 
		SET @SQL = 'INSERT INTO [' + @TableName + '] ([CustomerID], [CustomerName], [Period], [Revenue]) VALUES (' + CONVERT(VARCHAR, @CustomerID) + ', '''', ''' + @Period + ''', 0)'
	END
    -- Execute the query
    EXEC(@SQL);

	END TRY
    BEGIN CATCH
        -- Insert into ErrorLog table
        INSERT INTO [ErrorLog]
        (
            [ErrorNumber],
            [ErrorSeverity],
            [ErrorMessage],
            [CustomerID],
            [Period],
            [CreatedAt]
        )
        VALUES
        (
            ERROR_NUMBER(),
            ERROR_SEVERITY(),
            ERROR_MESSAGE(),
            @CustomerID,
            @Period,
            GETDATE()
        );
        
        -- Optionally, re-throw the error to notify the caller
        THROW;
    END CATCH
END;