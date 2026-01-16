import psycopg2
import os

# Database connection using the copilot_edit credentials
conn_string = "postgresql://copilot_edit:R8q!v9Kz#xT2sP4uF1a@L0y@pxpjxyfcydiasrycpbfp:5432/postgres"

try:
    conn = psycopg2.connect(conn_string)
    cursor = conn.cursor()
    
    print("Connected to database successfully")
    
    # Create login_audit table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS public.login_audit (
      id bigserial PRIMARY KEY,
      user_id uuid,
      username text NOT NULL,
      ip_hash text NOT NULL,
      user_agent_hash text NOT NULL,
      login_at timestamp with time zone NOT NULL DEFAULT NOW(),
      success boolean NOT NULL,
      failure_reason text,
      created_at timestamp with time zone NOT NULL DEFAULT NOW()
    );
    """)
    print("✓ Created login_audit table")
    
    # Create login_rate_limiting table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS public.login_rate_limiting (
      id bigserial PRIMARY KEY,
      username text NOT NULL,
      ip_hash text NOT NULL,
      attempt_count integer NOT NULL DEFAULT 1,
      first_attempt_at timestamp with time zone NOT NULL DEFAULT NOW(),
      last_attempt_at timestamp with time zone NOT NULL DEFAULT NOW(),
      locked_until timestamp with time zone,
      created_at timestamp with time zone NOT NULL DEFAULT NOW(),
      updated_at timestamp with time zone NOT NULL DEFAULT NOW(),
      UNIQUE(username, ip_hash)
    );
    """)
    print("✓ Created login_rate_limiting table")
    
    # Add username column to users table
    cursor.execute("""
    ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text UNIQUE;
    """)
    print("✓ Added username column to users table")
    
    # Backfill usernames
    cursor.execute("""
    UPDATE public.users 
    SET username = LOWER('user_' || SUBSTRING(id::text, 1, 8)) 
    WHERE username IS NULL;
    """)
    print("✓ Backfilled usernames")
    
    # Create indexes
    cursor.execute("""
    CREATE INDEX IF NOT EXISTS idx_login_audit_user_id_login_at 
      ON public.login_audit(user_id, login_at DESC);
    """)
    print("✓ Created index on login_audit")
    
    cursor.execute("""
    CREATE INDEX IF NOT EXISTS idx_login_rate_limiting_locked_until 
      ON public.login_rate_limiting(locked_until);
    """)
    print("✓ Created index on login_rate_limiting")
    
    conn.commit()
    print("\n✅ All deployments completed successfully!")
    
    # Verify
    cursor.execute("""
    SELECT 
      EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='login_audit' AND table_schema='public') as login_audit_exists,
      EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='login_rate_limiting' AND table_schema='public') as rate_limiting_exists,
      EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='username') as username_exists;
    """)
    result = cursor.fetchone()
    print(f"\nVerification: {result}")
    
    cursor.close()
    conn.close()
    
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
