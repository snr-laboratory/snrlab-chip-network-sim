# snrlab-ic-q-pix-v1

Q-Pix front end design and coupling to a digital data transmission back-end

## MOS + COTS OpAmp Simulation

Files under [./mos_cots_opamp_sim/] simulate a MOS (in an ASIC, wire-bonded out) plus COTS OpAmp formed Q-Pix front-end.  The procedure and results are detailed at (arXiv:2311.09568)[https://arxiv.org/abs/2311.09568].

## Python `venv`

- Create: `$(PYTHON) -m venv --symlinks --system-site-packages --clear $(PYVENV)`
- Upgrade: `$(PYTHON) -m venv --symlinks --system-site-packages --upgrade --upgrade-deps $(PYVENV)`
- Update all packages: `pip --disable-pip-version-check list --outdated --format=json | python -c "import json, sys; print('\n'.join([x['name'] for x in json.load(sys.stdin)]))" | xargs -n1 pip install -U`

## Git

- `git clone --recurse-submodules`
- `git pull --recurse-submodules --all --rebase --prune && git gc --aggressive`
