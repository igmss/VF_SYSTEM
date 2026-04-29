# Supabase Migration - Phase 1: Infrastructure Setup

This directory contains the SQL scripts and instructions for Phase 1 of the Firebase to Supabase migration.

## Steps

### 1. Create Supabase Project
- Go to [supabase.com](https://supabase.com) and create a new project.
- Select a region close to your users (e.g., `eu-central-1` for Egypt).
- Set a strong database password and save it securely.
- Record the following from **Project Settings → API**:
  - **Project URL**
  - **anon/public key**
  - **service_role key**

### 2. Enable Extensions
In the Supabase SQL Editor, run:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";
```
*Note: `pg_cron` may require enabling via the Dashboard UI (Database → Extensions) first.*

### 3. Apply Schema
Open the Supabase **SQL Editor** and copy-paste the contents of `supabase/schema.sql`. Run the script to:
- Create all 15 tables.
- Create necessary indexes.
- Enable Row Level Security (RLS) and define policies.

### 4. Verify Implementation
Run the queries in `supabase/verify.sql` to ensure everything is correctly set up.
- You should see 15 tables in the `public` schema.
- All tables should have `rowsecurity = true`.

## Next Phase
Once this schema is applied and verified, proceed to **Phase 2: Data Migration Script**.
