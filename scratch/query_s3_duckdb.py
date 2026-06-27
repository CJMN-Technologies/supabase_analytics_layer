import os
import duckdb

# AWS Credentials for S3 Access
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID", "your-access-key")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY", "your-secret-key")
AWS_REGION = os.environ.get("AWS_REGION", "ap-southeast-1")
S3_BUCKET = os.environ.get("S3_BUCKET", "lrt2-analytics-lake")

def run_s3_duckdb_queries():
    print("Initialize DuckDB Connection...")
    # Initialize in-memory database
    con = duckdb.connect(database=":memory:")
    
    # 1. Install and load the httpfs extension for S3 support (100% Free Open Source)
    con.execute("INSTALL httpfs;")
    con.execute("LOAD httpfs;")
    
    # 2. Configure AWS credentials inside DuckDB session
    con.execute(f"SET s3_region='{AWS_REGION}';")
    con.execute(f"SET s3_access_key_id='{AWS_ACCESS_KEY_ID}';")
    con.execute(f"SET s3_secret_access_key='{AWS_SECRET_ACCESS_KEY}';")
    
    print("\nExecuting query directly on S3 Parquet Files...")
    
    # Define S3 URLs
    weather_s3_path = f"s3://{S3_BUCKET}/analytics/external/weather_consolidated/data.parquet"
    events_s3_path = f"s3://{S3_BUCKET}/analytics/external/events_consolidated/data.parquet"
    
    # 3. Perform serverless SQL join directly on S3 Parquet files
    cfi_query = f"""
        SELECT 
            e.event_date,
            e.station,
            e.event_name,
            e.normalized_score as A_sw,
            COALESCE(w.p_idx, 0.0) as P_idx,
            (0.4 * COALESCE(w.p_idx, 0.0) + 0.3 * e.normalized_score) as CFI
        FROM '{events_s3_path}' e
        LEFT JOIN '{weather_s3_path}' w
          ON e.event_date = w.weather_date 
         AND (e.station = w.station OR e.station = 'All Stations')
        WHERE e.event_category != 'unclassified'
        ORDER BY e.event_date DESC, CFI DESC
        LIMIT 10;
    """
    
    df = con.execute(cfi_query).df()
    
    print("\n====================================================================")
    print("🏆 TOP 10 COMMUTER FRICTION INDEX (CFI) RESULTS DIRECTLY FROM S3")
    print("====================================================================")
    print(df.to_string())
    print("====================================================================")

if __name__ == "__main__":
    if AWS_ACCESS_KEY_ID == "your-access-key":
        print("⚠️ Please configure AWS credentials inside the script or environment variables to execute query on S3.")
    else:
        run_s3_duckdb_queries()
