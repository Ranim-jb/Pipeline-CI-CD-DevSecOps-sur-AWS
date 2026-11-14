.PHONY: test security run

test:
	. .venv/bin/activate && pytest -q

security:
	. .venv/bin/activate && semgrep --config .semgrep/rules.yml --error app tests
	. .venv/bin/activate && checkov -d terraform --quiet --compact

run:
	. .venv/bin/activate && python -m app.app
