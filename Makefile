SHELL := env PATH=$(PATH) /bin/bash
PIP := pip3
PYTHON := python3

# Run all unit test cases
test:
	source .venv/bin/activate && nox

# Check the format
lint:
	source .venv/bin/activate && nox -e lint

# Enter a virtual env
venv:
	rm -rf .venv
	$(PYTHON) -m venv .venv
	source .venv/bin/activate;\
		$(PIP) install nox;\
		$(PYTHON) --version;\
		$(PIP) --version;\
		tox --version;\
		$(PIP) install -r requirements.txt;
	@echo "Activate the virtual env: source .venv/bin/activate"
	@echo "Deactivate when done: deactivate"

clean:
	find . -name "*.pyc" -o -name "__pycache__" | xargs rm -rf
	rm -rf .venv
	rm -rf deployment_pallckage*.zip

# Auto-format to pep8
format:
	source .venv/bin/activate && $(PYTHON) -m docformatter --in-place --recursive bps
	source .venv/bin/activate && $(PYTHON) -m autopep8 --aggressive --in-place --max-line-length 120 --recursive bps

synth:
	source .venv/bin/activate && source nitro_env.sh && cdk synth

deploy:
	source .venv/bin/activate && source nitro_env.sh && cdk deploy $(stack)

destroy:
	source .venv/bin/activate && source nitro_env.sh && cdk destroy $(stack)

diff:
	source .venv/bin/activate && source nitro_env.sh && cdk diff $(stack)

check:
	source .venv/bin/activate && source nitro_env.sh && cdk doctor $(stack)
