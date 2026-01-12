.PHONY: help test test-metrics test-alerts test-backup-restore test-service-health test-all clean setup

# Default target
help:
	@echo "Observability Stack QA Test Suite"
	@echo "=================================="
	@echo ""
	@echo "Available targets:"
	@echo "  make setup                - Set up environment and dependencies"
	@echo "  make test-metrics         - Test metrics collection"
	@echo "  make test-alerts          - Test alert configuration"
	@echo "  make test-service-health  - Test service health checks and SLA tracking"
	@echo "  make test-backup-restore  - Test backup/restore validation"
	@echo "  make test-all             - Run all tests"
	@echo "  make test                 - Alias for test-all"
	@echo "  make clean                - Clean up test artifacts"
	@echo ""

# Set up environment
setup:
	@echo "Setting up QA environment..."
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env file from .env.example"; \
		echo "Please update .env with your configuration"; \
	else \
		echo ".env file already exists"; \
	fi
	@chmod +x test_metrics.sh test_alerts.sh test_backup_restore.sh test_service_health.sh
	@echo "Setup complete!"

# Test metrics collection
test-metrics:
	@echo "Running metrics tests..."
	@./test_metrics.sh

# Test alert configuration
test-alerts:
	@echo "Running alert tests..."
	@./test_alerts.sh

# Test service health checks
test-service-health:
	@echo "Running service health tests..."
	@./test_service_health.sh

# Test backup/restore validation
test-backup-restore:
	@echo "Running backup/restore validation tests..."
	@if [ -f .env ]; then \
		source .env && ./test_backup_restore.sh; \
	else \
		echo "WARNING: .env file not found. Using environment variables."; \
		./test_backup_restore.sh; \
	fi

# Run all tests
test-all: test-metrics test-alerts test-service-health
	@echo ""
	@echo "All tests completed!"

# Alias for test-all
test: test-all

# Clean up test artifacts
clean:
	@echo "Cleaning up test artifacts..."
	@rm -f test-results.log
	@echo "Clean complete!"

# Validate YAML files
validate:
	@echo "Validating YAML configuration files..."
	@if command -v yamllint &> /dev/null; then \
		yamllint ../prometheus/prom.yml; \
		yamllint ../prometheus/rules/alerts.yml; \
		yamllint ../prometheus/rules/recording.yml; \
		yamllint ../alertmanager/alertmanager.yml; \
		yamllint ../grafana/provisioning/alerting/rule_groups.yaml; \
		yamllint ../grafana/provisioning/dashboards/dashboards.yml; \
		echo "YAML validation complete!"; \
	else \
		echo "yamllint not found. Install it with: pip install yamllint"; \
		exit 1; \
	fi

# Validate Prometheus configuration
validate-prometheus:
	@echo "Validating Prometheus configuration..."
	@if command -v promtool &> /dev/null; then \
		promtool check config ../prometheus/prom.yml; \
		promtool check rules ../prometheus/rules/alerts.yml; \
		promtool check rules ../prometheus/rules/recording.yml; \
		echo "Prometheus validation complete!"; \
	else \
		echo "promtool not found. Install Prometheus to get promtool."; \
		exit 1; \
	fi

# Validate Alertmanager configuration
validate-alertmanager:
	@echo "Validating Alertmanager configuration..."
	@if command -v amtool &> /dev/null; then \
		amtool check-config ../alertmanager/alertmanager.yml; \
		echo "Alertmanager validation complete!"; \
	else \
		echo "amtool not found. Install Alertmanager to get amtool."; \
		exit 1; \
	fi

# Run all validations
validate-all: validate validate-prometheus validate-alertmanager
	@echo ""
	@echo "All validations complete!"
