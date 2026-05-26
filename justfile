set dotenv-load

default:
	@just --list

docker-up:
	docker compose -f docker/docker-compose.yml up --build

docker-down:
	docker compose -f docker/docker-compose.yml down

docker-down-volumes:
	docker compose -f docker/docker-compose.yml down --volumes
