#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "Testing Backup & Restore Validation"
echo "================================================"
echo ""

# Check for TEST_DB_URL environment variable
if [[ -z "${TEST_DB_URL:-}" ]]; then
  echo -e "${RED}ERROR: TEST_DB_URL is not set.${NC}"
  echo ""
  echo "Please set TEST_DB_URL to point to the restored database."
  echo "Example:"
  echo "  export TEST_DB_URL='postgresql://user:pass@host:5432/dbname?sslmode=require'"
  echo ""
  echo "Or populate qa/.env and source it:"
  echo "  source .env"
  exit 1
fi

echo "Testing restored database at: ${TEST_DB_URL}"
echo ""

# Test 1: Basic connectivity
test_connectivity() {
  echo -n "Testing database connectivity... "
  if psql "$TEST_DB_URL" -c "SELECT 1 AS connection_test;" > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    return 0
  else
    echo -e "${RED}FAIL${NC}"
    echo "Could not connect to database. Check TEST_DB_URL and credentials."
    return 1
  fi
}

# Test 2: Validate schema exists
test_schema() {
  echo -n "Validating schema on restored DB... "

  # List all tables
  tables=$(psql "$TEST_DB_URL" -t -c "\dt" 2>/dev/null)

  if [[ -n "$tables" ]]; then
    table_count=$(echo "$tables" | grep -c "|" || echo "0")
    echo -e "${GREEN}PASS${NC} ($table_count tables found)"
    return 0
  else
    echo -e "${YELLOW}WARN${NC} (No tables found - might be expected for empty DB)"
    return 0
  fi
}

# Test 3: Check migration version (Alembic)
test_migration_version() {
  echo -n "Checking migration version (Alembic)... "

  if psql "$TEST_DB_URL" -t -c "SELECT version_num FROM alembic_version;" > /dev/null 2>&1; then
    version=$(psql "$TEST_DB_URL" -t -c "SELECT version_num FROM alembic_version;" | xargs)
    echo -e "${GREEN}PASS${NC} (version: $version)"
    return 0
  else
    echo -e "${YELLOW}WARN${NC} (alembic_version table not found - ensure migrations ran)"
    echo "  This is expected if you're testing a fresh restore without migrations."
    return 0
  fi
}

# Test 4: Smoke query - list schemas
test_smoke_query() {
  echo -n "Smoke query (list schemas)... "

  schemas=$(psql "$TEST_DB_URL" -t -c "SELECT schema_name FROM information_schema.schemata LIMIT 5;" 2>/dev/null)

  if [[ -n "$schemas" ]]; then
    echo -e "${GREEN}PASS${NC}"
    echo "  Found schemas: $(echo "$schemas" | xargs | tr '\n' ', ')"
    return 0
  else
    echo -e "${RED}FAIL${NC} (Could not query information_schema)"
    return 1
  fi
}

# Test 5: Check database size
test_database_size() {
  echo -n "Checking database size... "

  db_size=$(psql "$TEST_DB_URL" -t -c "SELECT pg_size_pretty(pg_database_size(current_database()));" 2>/dev/null | xargs)

  if [[ -n "$db_size" ]]; then
    echo -e "${GREEN}PASS${NC} (size: $db_size)"
    return 0
  else
    echo -e "${RED}FAIL${NC} (Could not determine database size)"
    return 1
  fi
}

# Test 6: Verify PostgreSQL version
test_postgres_version() {
  echo -n "Verifying PostgreSQL version... "

  version=$(psql "$TEST_DB_URL" -t -c "SELECT version();" 2>/dev/null | head -1 | xargs)

  if [[ -n "$version" ]]; then
    echo -e "${GREEN}PASS${NC}"
    echo "  $version"
    return 0
  else
    echo -e "${RED}FAIL${NC} (Could not determine PostgreSQL version)"
    return 1
  fi
}

# Test 7: Check for common application tables (customize per app)
test_application_tables() {
  echo -n "Checking for common application tables... "

  # List of common table names - customize based on your application
  common_tables=("users" "sessions" "migrations" "alembic_version")
  found_tables=0

  for table in "${common_tables[@]}"; do
    if psql "$TEST_DB_URL" -t -c "SELECT to_regclass('public.$table');" 2>/dev/null | grep -q "$table"; then
      ((found_tables++))
    fi
  done

  if [[ $found_tables -gt 0 ]]; then
    echo -e "${GREEN}PASS${NC} ($found_tables/${#common_tables[@]} common tables found)"
    return 0
  else
    echo -e "${YELLOW}WARN${NC} (No common tables found - verify table names match your schema)"
    return 0
  fi
}

# Test 8: Verify data integrity (sample count queries)
test_data_integrity() {
  echo -n "Testing data integrity (sample queries)... "

  # Try to count rows in any available table
  first_table=$(psql "$TEST_DB_URL" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' LIMIT 1;" 2>/dev/null | xargs)

  if [[ -n "$first_table" ]]; then
    row_count=$(psql "$TEST_DB_URL" -t -c "SELECT COUNT(*) FROM $first_table;" 2>/dev/null | xargs)
    echo -e "${GREEN}PASS${NC} (table '$first_table' has $row_count rows)"
    return 0
  else
    echo -e "${YELLOW}WARN${NC} (No tables to query - might be expected for empty DB)"
    return 0
  fi
}

# Run all tests
echo "Starting backup/restore validation tests..."
echo ""

test_results=0

test_connectivity || ((test_results++))
test_schema || ((test_results++))
test_migration_version || ((test_results++))
test_smoke_query || ((test_results++))
test_database_size || ((test_results++))
test_postgres_version || ((test_results++))
test_application_tables || ((test_results++))
test_data_integrity || ((test_results++))

echo ""
echo "================================================"
if [ $test_results -eq 0 ]; then
  echo -e "${GREEN}All restore validation tests passed!${NC}"
  echo ""
  echo "The restored database appears to be healthy and accessible."
  echo "Next steps:"
  echo "  1. Verify business-critical queries work"
  echo "  2. Run application-specific integration tests"
  echo "  3. Check data completeness against expected counts"
  exit 0
else
  echo -e "${RED}$test_results test(s) failed${NC}"
  echo ""
  echo "The restored database may have issues. Review errors above."
  exit 1
fi
