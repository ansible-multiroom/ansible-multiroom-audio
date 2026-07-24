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

Instructions to execute the local tests are given below. Automated tests are driven by `.github/workflows/ci.yml`. The setup is explained in more detail further down.

Tests on `x86_64` are much faster, but only on `aarch64` real audio cards and bluetooth is available. In order to make all tests successful on `x86_64`, the ansible tag `hifiberry-only` is used to tag individual tasks where testing on `x86_64` breaks. Note that molecule also does an **idempotence** test, so also tasks that break idempotence (on `x86_64` only) must be tagged accordingly.

### Bluetooth and Sound Hardware

On `x86_64`, these are not available.

On the self hosted raspberry pi runner, these are mapped into the test container that is built dynamically to run the molecule test.

Note to the admins: As tests showed, this only works on a **privileged** container that has full access to the underlying operating system. Therefore, the Github option *Approval for running fork pull request workflows from contributors* (below *Settings->Actions->General*) must be on **Require approval for all external contributors**. This prevents triggering pipeline runs on the self-hosted runner automatically. Pull requests from outsiders must be carefully reviewed **before approving the CI run** and if there is any change that is not fully understood, the workflow (i.e. testing on Raspberry Pi) **must not be approved**. It is easy to escape from a privileged container.

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

#### Debugging in the container

If the container is still running, you can connect to it with:

~~~
docker exec -it test-snapclient /bin/bash
~~~

#### Main config files

* `molecule/config.yml          `: Base configuration, define `--skip-tags` to distinguish between `x86_64` and `aarch64` tests
* `molecule/default/molecule.yml`: Test container definition, parametrized by more variables to distinguish between `x86_64` and `aarch64` tests

The following variables are used to parametrize the config. If they are unset, they all default
to values applicable to `x86_64` testing. So you don't have to care about them as long as you test on your workstation:

* `PROVISIONER_SKIP_TAGS`: defaults to `hifiberry-only` so that code that is not testable on `x86_64` is skipped
* `PLATFORMS_NETWORK_MODE`: defaults to `bridge`. This is safe, but would prevent the test container on the Raspberry Pi from accessing bluetooth
* `PLATFORMS_PRIVILEGED`: defaults to `false`. This is safe, but would prevent the test container on the Raspberry Pi from accessing bluetooth and the sound card
* `PLATFORMS_SND_DEV_PATH`: default to `/tmp/dummy-snd`. This is safe for the test container, but needs a different setting on the Raspberry Pi to access the real sound card.
* `PLATFORMS_SYSTEM_DBUS_SOCKET`: defaults to `/tmp/dummy-dbus`. Needs a different value to access the bluetooth hardware on the Raspberry Pi

## Github testing with the CI pipeline

On Github, the file `.github/workflows/ci.yml` defines everything.

### Arbitration Github vs self-hosted runner

* the only actions triggering a pipeline run are pushes and pull requests to the main branch. Although we never push directly to `main`, any open pull request can get multiple commits as long as the pull request is not merged.
* if the commit happens to a merge request in our own repository, the self-hosted runner is selected
* if the commit happens to a merge request in a foreign fork, the Github runner is selected
* if the commit happens to a merge request from a foreign fork to our own repository, the self-hosted runner is selected, but due to the Github project setting *Require approval for all external contributors*, such runs are blocked by Github until one of the organization members approves it (see above). This allows to check the contributed code **before** potential malicious code is executed on the self-hosted runner.

The variables listed above are set to the exactly same values when the logic selects the `x86_64` runner. For the self-hosted runner, the following values are set:

* `PROVISIONER_SKIP_TAGS`: `tag-does-not-exist` so no code is skipped (as long as you don't use that tag in your ansible code which you shouldn't)
* `PLATFORMS_NETWORK_MODE`: `host`
* `PLATFORMS_PRIVILEGED`: `true`
* `PLATFORMS_SND_DEV_PATH`: `/dev/snd` to make the sound card visible in the test container
* `PLATFORMS_SYSTEM_DBUS_SOCKET`: `/var/run/dbus/system_bus_socket` to enable access to bluetooth in the test container

### Checking Pipeline runs

In the gitlab GUI, navigate to *Actions* and you see all past and - if one is still running - the current Pipeline run. Click on one and after a click on *1 job completed* you'll either see **Molecule Test (Hifiberry)** or **Molecule Test (Github)**, depending on whether the test ran on the self-hosted runner or a Gitlab runner. Click on this and you will see the steps (as defined in `ci.yml`).

On the Raspberry Pi, `ansible` and `molecule` are preinstalled and can be used (provided the `PATH` is set correctly), on the Github runner we need to install them as Github provides us with a fresh, minimal ubuntu VM for each test run.

The most interesting step is *Run Molecule*. Due to `MOLECULE_DEBUG` being set to `true` **and** having `provisioner.log` set to `true`, the ansible `--diff` output is visible in the output.

The most interesting steps within *Run Molecule* are

* `converge`: the application ansible code is executed for the first time and applies all changes to the ephemeral test container and no error should occur.
* `idempotence`: the code is executed a second time and no changes should be applied any more.

If one of the steps fails, the pipeline run is failed and you should fix your code and add commits to your pull request until no error happens again. A run on the Raspberry Pi takes at least 4 minutes, so I strongly suggest to run local tests before pushing as this is usually faster.

The pipeline is configured to abort a running job as soon as new one comes in.
