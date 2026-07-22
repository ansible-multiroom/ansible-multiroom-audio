# Motivation

This is my first attempt to test my ansible code with molecule. As I know this playbook quite well, it was a natural approach to introduce molecule here.

## Design goals

* enable local testing
* enable testing in a CI/CD pipeline with as few as possible changes.

## Limitations

As the code is designed to run on an raspberry pi with arm64 architecture and a hifiberry hat, but molecule
runs the tests in a debian container with amd64 architecture, many parts of this code are not suited to be
tested with molecule.

* roles that can be tested fully on a raspberry pi with an hifiberry HAT only have some tasks with the tag "hifiberry-only". Molecule is configured to skip such tasks when running on a non raspberry pi container. For example, the systemd services for snapclients can be configured and started, but terminate immediately when the required target audio device is not available. Therefore, the idempotence for such service is tested only when running on a raspberry pi.

Bluetooth and Sound Hardware is not available on a amd64 container like ubuntu-latest.

TODO: can mpd run without an smb server even when it is defined to find its music there?

## Molecule setup

### install molecule on your workstation

The following has been tested on ubuntu2404.

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
* Test molecule
  ~~~
  molecule --version
  ~~~

### Run a test scenario

Switch to the `venv` created above
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
the tests are separated by using specific tags in the playbook:

* `molecule::snapclient` tests the base role and the snapclients
* `molecule::cabling` tests the internal cabling with the `acable` role as far as possible
* `molecule::small_server` tests a setup with just a `snapserver`
* `molecule::server` tests a full blown setup with `mpd`, `snapserver` and the frontends.

To run only a subset of the tests, you can use e.g.:

~~~
molecule --base-config molecule/config.yml test -- --tags=molecule::snapclient
~~~

### Stages

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


### Debugging on the container

If the container is still running, you can connect to it with:

~~~
docker exec -it test-snapclient /bin/bash
~~~


