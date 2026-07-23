# Motivation

This is my first attempt to test my ansible code with molecule. As I know this playbook quite well, it was a natural approach to introduce molecule here.

## Design goals

* enable local testing
* enable testing in a CI/CD pipeline with as few changes as possible

## Molecule test environments

There are currently three different environments for molecule tests supported (architecture names taken from `uname -m`):
* manual test locally on your workstation (architecture `x86_64`)
* automated test on github in a ubuntu container (architecture: `x86_64`)
* automated test on github on a self-hosted raspberry pi runner (architecture `aarch64`)

Instruction for the local tests are given below. Automated tests are driven by `.github/workflows/ci.yml`

Tests on `x86_64` are much faster, but only on `aarch64` real audio cards and bluetooth is available. In order to make all tests successful on `x86_64`, the ansible tag `hifiberry-only` is used to tag individual tasks where testing on `x86_64` breaks. Note that molecule also does an **idempotence** test, so also tasks that break idempotence (on `x86_64` only) must be tagged accordingly.

### Bluetooth and Sound Hardware

On `x86_64`, these are not available.

On the self hosted raspberry pi runner, these are mapped into the test container that is built dynamically to run the molecule test.

Note to the admins: As tests showed, this only works on a **privileged** container that has full access to the underlying operating system. Therefore, the Github option *Approval for running fork pull request workflows from contributors* (below *Settings->Actions->General*) must be on **Require approval for all external contributors** and if there is any change that is not fully understood, the workflow (i.e. testing on Raspberry Pi) **must not be approved**.

## Molecule setup

### test locally on your workstation

The following has been tested on ubuntu2404 on `x86_64`

* Install packages:
  ~~~
  apt install python3-pip python3-venv libssl-dev docker.io
  ~~~
* Add your user to the `docker` group.
* Create venv
  ~~~
  python3 -m venv ~/.venv/molecule
  ~~~
* Activate and configure venv
  ~~~
  source ~/.venv/molecule/bin/activate
  pip install --upgrade pip
  pip install molecule "molecule-plugins[docker]" ansible-lint
  ~~~
* Basic test of molecule (in the venv)
  ~~~
  molecule --version
  ~~~

#### Run a test scenario

Change into the repo dir and activate the `venv` created above
~~~
cd <local repo dir>
source ~/.venv/molecule/bin/activate
~~~

In order to keep all molecule files below the `molecule` directory, I use
a non standard path for the molecule base config.

Therefore, always call molecule like this:
~~~
molecule --base-config molecule/config.yml ...
~~~

To run a full test cycle, do
~~~
molecule --base-config molecule/config.yml test
~~~

All tests run in the same container, but in order to keep the test/fix cycle short,
the tests are separated by using specific tags in the playbook (still WIP):

* `molecule::snapclient` tests the base role and the snapclients
* `molecule::cabling` tests the internal cabling with the `acable` role as far as possible (not implemented yet)
* `molecule::small_server` tests a setup with just a `snapserver` (not implemented yet)
* `molecule::server` tests a full blown setup with `mpd`, `snapserver` and the frontends. (not implemented yet)

To run only a subset of the tests, you can use e.g.:

~~~
molecule --base-config molecule/config.yml test -- --tags=molecule::snapclient
~~~

#### Stages

You can also run individual stages only:
~~~
molecule --base-config molecule/config.yml destroy
molecule --base-config molecule/config.yml create
molecule --base-config molecule/config.yml converge
molecule --base-config molecule/config.yml verify
molecule --base-config molecule/config.yml idempotence
molecule --base-config molecule/config.yml destroy
~~~

You can also execute a single stage for a certain tag only, e.g.:

~~~
molecule --base-config molecule/config.yml converge -- --tags=molecule::snapclient
molecule --base-config molecule/config.yml idempotence -- --tags=molecule::snapclient
~~~

For `verify`, the syntax is different due to technical reasons:

~~~
MOLECULE_TAG=molecule::snapclient molecule --base-config molecule/config.yml verify
~~~


#### Debugging on the container

If the container is still running, you can connect to it with:

~~~
docker exec -it test-snapclient /bin/bash
~~~

## Github Molecule setup

In order to really test the code, a self-hosted, raspberry pi based gitlab runner is deployed.

TODO: 
* describe arbitration (no external devs are allowed to use that without approval)
* difference between dependabot (execution on ubuntu without hardware specifics) and human devs (execution on self hosted runner)


