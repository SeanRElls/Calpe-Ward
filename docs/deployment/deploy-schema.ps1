Add-Type -AssemblyName System.Data.SqlClient

# Connection string
$connString = "Server=pxpjxyfcydiasrycpbfp,5432;Username=copilot_edit;Password=R8q!v9Kz#xT2sP4uF1a@L0y;Database=postgres;SSL Mode=Require;"

try {
    $conn = New-Object Npgsql.NpgsqlConnection($connString)
    $conn.Open()
    Write-Host "✓ Connected to database"
    
    $cmd = $conn.CreateCommand()
    
    # Create login_audit table
    $cmd.CommandText = @"
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
"@
    $cmd.ExecuteNonQuery()
    Write-Host "✓ Created login_audit table"
    
    # Create login_rate_limiting table
    $cmd.CommandText = @"
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
"@
    $cmd.ExecuteNonQuery()
    Write-Host "✓ Created login_rate_limiting table"
    
    # Add username column
    $cmd.CommandText = "ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text UNIQUE;"
    $cmd.ExecuteNonQuery()
    Write-Host "✓ Added username column to users"
    
    # Backfill usernames
    $cmd.CommandText = "UPDATE public.users SET username = LOWER('user_' || SUBSTRING(id::text, 1, 8)) WHERE username IS NULL;"
    $cmd.ExecuteNonQuery()
    Write-Host "✓ Backfilled usernames"
    
    $conn.Close()
    Write-Host "`n✅ All deployments completed!"
    
} catch {
    Write-Host "❌ Error: $_"
}
