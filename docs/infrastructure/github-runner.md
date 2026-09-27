# Goal

As the target of our ansible code is a Raspberry Pi anyway, a self hosted Raspberry Pi runner
allows much better testing than testing locally on the development workstation or on a
standard Github runner (both being an `x86_64` architecture).

However, there are also some drawbacks:
* A self hosted runner runs in my personal home network and is basically a remote execution device that can be fed with arbitrary code via github. The fact that we need privileged containers so that we can access the soundcard and other hardware makes that risk even bigger. Therefore, great care must be taken to configure both the selection of the target runner and the permissions required to run a test run there.
* A Raspberry Pi runner is slower than a `x86_64` runner and has less ressources. Some tuning is needed both in the test setup and also the system setup of the runner.

# Hardware

RaspberryPi (at least a **4**) with **8GB RAM**: As molecule/ansible is quite intensive at writing to disk, it makes sense move some of the filesystems into RAM so that you can minimize the wear of the SD card.

Choose a stable and fast SD card, **16GB** at least.

# Software

As the Raspberry Pi is already slow, we want to preinstall as much software on the runner so that tests don't need to repeat those steps again and again. 

## Required Software

* Raspberry OS: Take the newest one available and ensure that you can login as user `pi` and need a password to become `root` (not `sudo` without password).
* verify with `aplay -L` that you see the soundcard you want to test with.
* disable the onboard audio and (if you don't need it) wifi in `/boot/firmware/config.txt`
~~~
# dtparam=audio=on
dtoverlay=disable-wifi
~~~

* `docker`: 
   * install from `download.docker.com` the following packages (follow one of the install guides to configure the repo correctly etc): 
      * docker-ce
      * docker-ce-cli
      * containerd.io
      * docker-buildx-plugin
      * docker-compose-plugin
   * add the user `pi` to the docker group: `usermod -aG docker pi`
   * test (as user `pi`, you might need to relogin) the docker installation: `docker run hello-world`
* `python` and `molecule`
   * as root: `apt install -y python3-pip`
   * as pi:
~~~
$ python3 -m pip install --upgrade pip --break-system-packages
$ python3 -m pip install "molecule[docker]" "molecule-plugins[docker]" ansible-lint --break-system-packages
~~~
* Runner software, start in the GitHub GUI
   * In the project, choose *Actions* -> *General* -> *Approval for running fork pull request workflows from contributors*: 
     * [x] *Require approval for all external contributors*
     * **THIS IS A VERY IMPORTANT SECURITY SETTING!**
   * In the project, choose *Settings* -> *Actions* -> *Runners* -> *New self hosted runner* -> *Linux* -> *ARM64*
     * Execute all instructions as user `pi`
     * Then, execute `config.sh`:
         * group: Default
         * name: raspirunner
         * additional label: hifiberry
         * work folder: `_work`
     * Then, create systemd service
         * `sudo ./svc.sh install`
     * And reboot
     * After the reboot, you should see a running service: `systemctl status actions.runner.ansible-multiroom-ansible-multiroom-audio.raspirunner`
   
## Disk tuning

In order to move almost all writes into a RAM Filesystem, I have configured four directories in `/etc/fstab`:

~~~
tmpfs  /home/pi/actions-runner/_work  tmpfs  defaults,noatime,uid=1000,gid=1000,size=100M  0  0
tmpfs  /home/pi/actions-runner/_diag  tmpfs  defaults,noatime,uid=1000,gid=1000,size=100M  0  0
tmpfs  /var/lib/docker                tmpfs  defaults,noatime,mode=0710,uid=0,gid=0,size=512M 0 0
tmpfs  /var/lib/containerd            tmpfs  defaults,noatime,mode=0710,uid=0,gid=0,size=3G 0 0
~~~

For the ones in `/home/pi`, you need to **stop the runner service**, then remove all data in those directories and then mount them with `mount -a`.

For the ones in `/var/lib`, you need to **stop the docker service**, then remove all data in those directories and then mount them with `mount -a`.

In addition, you have to 
* create a global `/etc/ansible/ansible.cfg` to move the ansible tmp dir into `tmp` which is also a RAM FS:
~~~
[defaults]
local_tmp  = /tmp/.ansible/tmp
remote_tmp = /tmp/.ansible/tmp
async_dir  = /tmp/.ansible_async
~~~

* create an override file for the runner (with `systemctl edit ...`):
~~~
[Service]
Environment="ANSIBLE_LOCAL_TEMP=/tmp/.ansible/tmp"
Environment="ANSIBLE_REMOTE_TEMP=/tmp/.ansible/tmp"
Environment="ANSIBLE_ASYNC_DIR=/tmp/.ansible_async"
Environment="MOLECULE_EPHEMERAL_DIRECTORY=/tmp/.cache/molecule"
~~~

* Ensure in the repository `.github/workflows/ci.yml` that the docker space is cleaned up:
~~~
- name: Cleanup caches
  run: |
    docker system prune -f
    docker rmi molecule_local/geerlingguy/docker-debian12-ansible:latest || true
~~~

* Ensure in the repository `molecule/config.yml` that no build cache is used (this is probably redundant):
~~~
driver:
  name: docker
  options:
    build_cache: false
~~~

* Ensure in the repository `/molecule/*/molecule.yml` that we don't need to improve the `geerlingguy` image:
~~~
platforms:
  - name: ...
    pre_build_image: true
~~~

* Finally, test that all writes go to a RAM FS during test while running the following command on the runner:
   * `fatrace -t | grep " W "`
   * the only writes you should see during a test run are a few writes to the `/home/pi/.ansible_async/` directory. According to my research, there is no configuration option to fix these, so either you create a separate RAM-FS for this directory or symlink it to `/tmp/.ansible_async/`.
