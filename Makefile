TAG=$(v)
TAG ?= latest
.PHONY: docker-build
docker-build:
	## change config
	cat config.toml > config.backup.toml
	rm -f config.toml
	mv config.docker.toml config.toml
	
	docker build -t yusank/hugo_blog:$(TAG) .
	# recover
	mv config.toml config.docker.toml
	cat config.backup.toml > config.toml
	rm -f config.backup.toml
.PHONY: docker-run
docker-run:
	docker rm -f blog
	docker run -d -p 8080:80 --name blog yusank/hugo_blog:$(TAG)

.PHONY: docker-push
docker-push:
	docker push docker.io/yusank/hugo_blog:$(TAG)
