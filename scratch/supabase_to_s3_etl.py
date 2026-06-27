import os
import pg8000
import pandas as pd
import boto3
from io import BytesIO

# Load configuration (in production, these are loaded from GitHub Actions Secrets)
DB_HOST = os.environ.get("DB_HOST", "aws-0-ap-southeast-1.pooler.supabase.com")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "postgres")
DB_USER = os.environ.get("DB_USER", "postgres.kthioobzfyepokrrykem")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
S3_BUCKET = os.environ.get("S3_BUCKET", "lrt2-analytics-lake")
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID", "")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY", "")

def get_db_connection():
    return pg8000.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )

def upload_df_to_s3_as_parquet(df, s3_client, bucket, s3_key):
    print(f"Converting DataFrame to Parquet for S3: s3://{bucket}/{s3_key}...")
    parquet_buffer = BytesIO()
    df.to_parquet(parquet_buffer, index=False, compression="snappy")
    parquet_buffer.seek(0)
    
    s3_client.put_object(
        Bucket=bucket,
        Key=s3_key,
        Body=parquet_buffer.getvalue()
    )
    print(f"✅ Successfully uploaded to s3://{bucket}/{s3_key}")

def etl_pipeline():
    # 1. Initialize AWS S3 Client
    s3_client = boto3.client(
        "s3",
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY
    )
    
    # 2. Connect to Supabase Postgres
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        # A. Get list of active (non-backup) transformed tables
        cursor.execute("""
            SELECT table_schema, table_name 
            FROM information_schema.tables 
            WHERE table_schema IN ('AFCS', 'external')
              AND table_name NOT LIKE '%_backup'
              AND table_type = 'BASE TABLE';
        """)
        tables = cursor.fetchall()
        
        for schema, table in tables:
            print(f"\nProcessing table {schema}.{table}...")
            
            # Query data from Supabase
            query = f'SELECT * FROM "{schema}"."{table}"'
            df = pd.read_sql(query, conn)
            
            if df.empty:
                print(f"Table {schema}.{table} is empty. Skipping.")
                continue
                
            # Define standard partition path
            s3_key = f"analytics/{schema}/{table}/data.parquet"
            
            # Upload to S3 (Free Tier eligible)
            upload_df_to_s3_as_parquet(df, s3_client, S3_BUCKET, s3_key)
            
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    if not AWS_ACCESS_KEY_ID or not DB_PASSWORD:
        print("⚠️ Environment variables missing. Run with credentials set to execute the ETL.")
    else:
        etl_pipeline()
