"""Demonstrate how Row Level Security limits the Supabase anon role."""

import json
from pathlib import Path

from supabase import create_client


PROJECT_ROOT = Path(__file__).resolve().parent.parent


with (PROJECT_ROOT / "config.public.json").open(encoding="utf-8") as config_file:
    public = json.load(config_file)

# This client has only the public anon key and no authenticated user session.
client = create_client(public["SUPABASE_URL"], public["SUPABASE_ANON_KEY"])

# page_views has a public SELECT policy, so this query is allowed.
page_views = client.table("page_views").select("*").limit(5).execute()
print(f"page_views: {len(page_views.data)} rows ✅")

# sentence_embeddings has a SELECT policy only for authenticated users.
# PostgreSQL RLS therefore filters every row from this anonymous query.
embeddings = client.table("sentence_embeddings").select("*").limit(5).execute()
print(
    f"sentence_embeddings: {len(embeddings.data)} rows "
    "(expected: 0) 🔒"
)
