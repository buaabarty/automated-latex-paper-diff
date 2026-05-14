IMAGE ?= automated-latex-paper-diff:latest

.PHONY: smoke test docker-build

smoke:
	bash -n scripts/generate_marked_diff.sh
	python3 -m py_compile scripts/postprocess_marked_diff.py scripts/normalize_bibitems.py tests/test_postprocess_marked_diff.py tests/test_normalize_bibitems.py

test:
	python3 -m unittest discover -s tests

docker-build:
	docker build -t $(IMAGE) .
