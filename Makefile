TAG ?= latest
help:  ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[0-9A-Za-z_-]+:.*?##/ { printf "  \033[36m%-45s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
.PHONY: docker-build
docker-build: ## build docker image
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
docker-run: ## run latest docker image localy
	docker rm -f blog
	docker run -d -p 8088:80 --name blog yusank/hugo_blog:$(TAG)

.PHONY: docker-push
docker-push: docker-build ## bulid and push newest docker image
	docker push docker.io/yusank/hugo_blog:$(TAG)

.PHONY: release
release: docker-push ## relaese newest version of image to aliyun
	ssh aliyun_d1 "./restart.sh latest"