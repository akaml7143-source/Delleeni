#!/usr/bin/env python3
"""Static validation for Delleeni's Supabase SQL schema.

This parses SQL before Flutter builds. It does not replace running the schema
against a real Supabase project or testing its RLS policies with pgTAP.
"""
from pathlib import Path
import re
import sys

try:
    from pglast import parse_sql
except ImportError as exc:
    raise SystemExit("Install pglast first: python -m pip install pglast") from exc

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "backend" / "supabase" / "schema.sql"
sql = SCHEMA.read_text(encoding="utf-8")

sql_files = [SCHEMA, *sorted((ROOT / "backend" / "supabase" / "migrations").glob("*.sql"))]
statement_count = 0
for sql_file in sql_files:
    source = sql_file.read_text(encoding="utf-8")
    try:
        statement_count += len(parse_sql(source))
    except Exception as exc:
        print(f"SQL syntax validation failed in {sql_file.relative_to(ROOT)}: {exc}", file=sys.stderr)
        raise SystemExit(1)

tables = set(re.findall(
    r"create\s+table\s+if\s+not\s+exists\s+public\.([a-z_][a-z0-9_]*)",
    sql, flags=re.IGNORECASE
))
rls_tables = set(re.findall(
    r"alter\s+table\s+public\.([a-z_][a-z0-9_]*)\s+enable\s+row\s+level\s+security",
    sql, flags=re.IGNORECASE
))
missing_rls = sorted(tables - rls_tables)
if missing_rls:
    raise SystemExit("Tables missing RLS: " + ", ".join(missing_rls))

# Security-definer functions must pin search_path to avoid object-shadowing.
for match in re.finditer(
    r"create\s+or\s+replace\s+function\s+public\.([a-z_][a-z0-9_]*).*?as\s+\$\$.*?\$\$\s*;",
    sql, flags=re.IGNORECASE | re.DOTALL
):
    body = match.group(0)
    if re.search(r"security\s+definer", body, flags=re.IGNORECASE):
        if not re.search(r"set\s+search_path\s*=\s*''", body, flags=re.IGNORECASE):
            raise SystemExit(f"SECURITY DEFINER function must use an empty search_path: {match.group(1)}")

required_functions = {
    "nearby_places",
    "nearby_road_reports",
    "nearby_accessibility_features",
    "guard_delleeni_road_report",
    "is_delleeni_moderator",
    "prevent_profile_role_escalation",
    "review_delleeni_place",
    "review_delleeni_road_report",
    "review_delleeni_contribution",
}
found_functions = set(re.findall(
    r"create\s+or\s+replace\s+function\s+public\.([a-z_][a-z0-9_]*)",
    sql, flags=re.IGNORECASE
))
missing_functions = sorted(required_functions - found_functions)
if missing_functions:
    raise SystemExit("Required functions missing: " + ", ".join(missing_functions))



if 'new.role is distinct from old.role' not in sql.lower():
    raise SystemExit('Profile role-escalation trigger guard is missing')
if not re.search(r'revoke\s+update\s+on\s+public\.user_profiles\s+from\s+authenticated', sql, flags=re.IGNORECASE):
    raise SystemExit('Authenticated users must not have table-wide profile update rights')
if not re.search(r'grant\s+update\s*\\(\s*display_name\s*\\)\s+on\s+public\.user_profiles\s+to\s+authenticated', sql, flags=re.IGNORECASE):
    raise SystemExit('Authenticated users should only update their display name')

for privileged_name in ('review_delleeni_place', 'review_delleeni_road_report', 'review_delleeni_contribution'):
    pattern = rf'revoke\s+all\s+on\s+function\s+public\.{privileged_name}\b[^;]*from\s+public\s*,\s*anon'
    if not re.search(pattern, sql, flags=re.IGNORECASE):
        raise SystemExit(f'Privileged function is not revoked from PUBLIC and anon: {privileged_name}')

print(
    f"Supabase SQL parsed successfully: {statement_count} statements, "
    f"{len(tables)} tables, RLS enabled on all tables."
)
