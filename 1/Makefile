.PHONY: help test test-auto-destroy validate fmt up down clean purge

help:
	@echo "Certara VPC Terraform Module - Development & Test Commands"
	@echo "=========================================================="
	@echo "  make validate           Run fast static validation and formatting checks"
	@echo "  make fmt                Format all Terraform files"
	@echo "  make up                 Start LocalStack in the background"
	@echo "  make down               Stop LocalStack container"
	@echo "  make test               Run full automated end-to-end LocalStack tests"
	@echo "  make test-auto-destroy  Run tests and automatically destroy resources after"
	@echo "  make clean              Destroy Terraform resources and stop LocalStack"
	@echo "  make purge              Clean resources and purge temporary state/cache files"

validate:
	@chmod +x ./validate.sh 2>/dev/null || true
	./validate.sh

fmt:
	terraform fmt -recursive

up:
	docker compose up -d

down:
	docker compose down

test:
	@chmod +x ./test_localstack.sh 2>/dev/null || true
	./test_localstack.sh

test-auto-destroy:
	@chmod +x ./test_localstack.sh 2>/dev/null || true
	./test_localstack.sh --auto-destroy

clean:
	@chmod +x ./cleanup_localstack.sh 2>/dev/null || true
	./cleanup_localstack.sh

purge:
	@chmod +x ./cleanup_localstack.sh 2>/dev/null || true
	./cleanup_localstack.sh --purge
