IMAGE ?= automated-latex-paper-diff:latest

.PHONY: smoke docker-build

smoke:
	bash -n scripts/generate_marked_diff.sh

docker-build:
	docker build -t $(IMAGE) .
