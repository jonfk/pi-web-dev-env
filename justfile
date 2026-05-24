set dotenv-load

default:
	@just --list

docker-up:
	docker compose -f docker/docker-compose.yml up --build

docker-down:
	docker compose -f docker/docker-compose.yml down

docker-production-up:
	docker compose -f prod-deployment/compose.yml up --build -d

docker-production-down:
	docker compose -f prod-deployment/compose.yml down
