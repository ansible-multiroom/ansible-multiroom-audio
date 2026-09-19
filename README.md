# ansible-multiroom-audio
This collection is being used to maintain (at least) three quite different multiroom audio setups based on Raspberry Pi and high quality audio HATs. We use [hifiberry](https://www.hifiberry.com/), but this works with any supported audio HAT. We are happy to hear from anyone else being successful using these roles.

## Features

The roles support setting up an audio multiroom system from a collection of Raspberry Pis. We try to make available all audio sources, so you can

* use every Pi as bluetooth sink to stream audio e.g. from your mobile
* use the analog input to stream audio from e.g. the rec out of your hifi amp
* use the USB ports to stream audio from e.g. a turntable with a builtin USB-Soundcard
* use the Pi as standalone music center controlled via WLAN and use it as access point when you add connectivity over a 2nd network interface

As a side product, it is also possible with these roles to create a standalone mpd music box that can be used offline. If you are crazy enough, you could run `snapcast` there too :smile:.

## Architecture

### Audio Hardware Limitations

Hardware audio sources and sinks need to be **driven individually**, so that we can receive audio from the analog input, digitize it, stream it synchronously
over the network to (all other clients and) the local client that sends the audio to the analog output. This will have some delay,  but exactly the same delay
as all other networked clients. On the other hand, a soundcard has one global digital clock for all inputs/outputs. Therefore, we use only one digital audio
format in all components and set that format explicitly wherever possible. This also minimizes the CPU load (and audio quality loss) for unwanted format
conversions.

ALSA **dmix** devices can be used to mix multiple streams together (provided that all streams have the same digital audio format) without any conversion.
**dsnoop** devices can be used to consume the same audio stream by multiple recorders. `dmix`/`dsnoop` devices proved to be very useful, but they are
apparently not usable for `alsaloop` as sinks/sources.

In order to support multiple audio inputs and mix them with a `dmix` device, we use the **snd_aloop**
kernel module. This creates a virtual soundcard and whatever you stream to `dmix:CARD=Loopback,DEV=0` comes out of `device=dsnoop:CARD=Loopback,DEV=1`
(and 1->2 and 2->3 etc). To make that work without any audio stuttering or other issues, the default audio format for `dmix`/`dsnoop` has to be set
in `/etc/asound.conf`.

### Design Goals
Implementation on Pi

* minimal: e.g. use only ALSA
* generic: use all interfaces without limitations (e.g. a node can be both source and sink)

Ansible implementation

* support a wide range of configurations
* roles should be generic enough that end users have to supply only
  * an `inventory` mapping Pi hosts to `group_vars`
  * a `playbook` mapping roles to hosts or host groups
  * maybe some own `host_vars`/`group_vars`
* Fully automated setup

# Roles

* base
  * Installs and configures the alsa config in /etc/asound.conf, needed as soon as you use `dmix` or `dsnoop` devices. That means always.

* Multiroom (snapcast)
  * snapclient
    * Installs the snapclient package and configures one or more snapclients. Usually on all nodes, at least two
  * snapserver
    * Installs the snapserver package and configures it. At least on one node, but not more than one snapserver per node.
  * snapweb
    * Adds a web application (on port `1780`) to snapserver that allows to control the snapclient volumes with a browser.

* Connecting the ALSA streams
  * snd_aloop
    * Loads the `snd_aloop` kernel module if you need an alsa loopback device
  * acable
    * Installs a systemd unit template with which you can create 'virtual cables' between alsa audio sources and sinks
    * These virtual cables are `arec | aplay` commands with configurable variables (e.g. an `alsaloop` that can use `dmix`/`dsnoop` devices)
    * Can also create a bluetooth sink, but only when the additional role `bluetooth_sink` is also mapped to that node.

* Bluetooth
  * bluetooth_sink
    * To be run after `acable`.
    * Installs and configures all components needed to enable `acable`  to accept an audio stream via bluetooth A2DP:
      * `bluetoothd` drives the hardware
      * a2dp_agent
        * Taken from mill1000's [python a2dp-agent](https://gist.github.com/mill1000/74c7473ee3b4a5b13f6325e9994ff84c)
        * Installs `a2dp-agent.py` configures a systemd unit
        * The a2dp agent handles the bluetooth connection initiation and authentication
      * bluealsa
        * Installs and configures bluealsa aka [bluez-alsa](https://github.com/Arkq/bluez-alsa), which configures the device as a bluetooth audio sink aka bluetooth loudspeaker
    * Ensures that bluetooth hardware is disabled (using `rfkill`) if not used
    * **WARNING**: There is still bug [#14](https://github.com/Daenou/ansible-multiroom-audio/issues/14), needs a one time manual intervention.
  * bluetooth_disable
    * Disable bluetooth with `rfkill`. Needed as separate role to handle devices without `acable` at all.

* MPD
  * mpd
    * A simple mpd config, used as (additional) audio stream to snapserver
  * mpdutils
    * An mpd playlist bot to eliminate duplicate playlist entries and manage playlist backup copies in mpd.
  * usbmount
    * any plugged in usb storage device is automatically mounted read only and scanned by mpd for audio files.
  * rompr
    * a container based web frontend for mpd (on port 80)
    * beautiful, easy to use, but [does not scale](https://github.com/fatg3erman/RompR/issues/168) for large playlists on large collections.

  * ampd
    * another container based web frontend for mpd (on port 8080)
    * scales well

* Spotify
  * raspotify
    * A simple (passwordless) raspotify configuration, used as (additional) audio stream to snapserver. Makes the multiroom system available to the spotify app as a speaker - provided you have a Spotify Premium account. This is a known limitation of [librespot](https://github.com/librespot-org/librespot), the code that actually makes your system talk to the spotify servers.

* Standalone Music Box
  * accesspoint
    * converts the built in WLAN adapter to a WLAN hotspot. Has no internet connectivity, but enough to control e.g. the volume via a mobile mpd client app. Useful for offline use.
  * uplink
    * needs the `accesspoint` role to be executed before
    * adds simple `firewalld` and `udev` based management of all other network interfaces (on top of the Raspbian default `dhcpcd`). As soon as e.g. the builtin ethernet or an additional WLAN USB dongle has internet connectivity, the `accesspoint` clients will have too.

# Requirements
Ansible host:

* ansible installed (This playbook was tested on ansible 2.10.8)
* ansible galaxy `community.general` collection for `community.general.modprobe`, install with `ansible-galaxy collection install community.general`.
* ansible galaxy `t2d.raspotify` role as base for the raspotify role here, install with `ansible-galaxy install t2d.raspotify`.
* ansible galaxy `ansible.posix` for the `usbmount` role.
* ansible galaxy `community.docker` for the `rompr` role.

Pi:

* Raspbian Bookworm image.
* Strongly suggested: The Pis can reach each other using a DNS-Name.
* Hints after a fresh install / a clone
  * reset password of user `pi`
  * enable ssh daemon: `touch /boot/ssh`
  * create a valid `/boot/wpa_supplicant.conf` when you need WLAN from the start
  * internal (low quality) audio is disabled in `/boot/config.txt`: `# dtparam=audio=on`
  * Audio HAT is working, you should see it with `aplay -L`. Maybe needs explicit enabling in `/boot/config.txt`.
  * If you cloned the sd card from an already working raspi:
    * Change hostname `sed -iBAK -e "s/raspberrypi/NEWHOSTNAME/g" /etc/hostname /etc/hosts`
    * regenerate sshd keys: `rm -v /etc/ssh/ssh_host_*` and `dpkg-reconfigure openssh-server`
    * reset machine id: `rm /etc/machine-id`, `systemd-machine-id-setup`
    * reboot
    * hard refresh DHCP leases on raspi, e.g. `rm /var/lib/dhcpcd/*.lease*`, `systemctl restart dhcpcd`
  * in some cases, DHCP servers get confused when the same MAC address is seen with a new name while the lease for the old name is still valid. Check and clean up your DHCP server cache.
* Passwordless ssh login from ansible host to hostname in the inventory file. If you use passwordless login to the user `pi` (and not `root`) use the `-u pi` for the `ansible-playbook` command.
* ~~Either python2 or~~ python3 for the bluetooth_sink role (a2dp_agent)

Your Environment:
* A mobile phone or a computer to control the snapclient volumes and mpd.
* A Spotify premium account if you want to use your multiroom system as Spotify speaker.
* Some pairs of decent loudspeakers (connected to a `hifiberry` AMP module) or a stereo equipment and a `hifiberry` DAC/ADC module.
* Hint for connecting a stereo amp: In order to be able to stream a local source (like a turntable) to the multiroom system **and** play it locally with the same delay as all other sinks for a true multiroom experience, your amp needs to have a *tape monitor* (or a *rec selector*) control. Connect the hifiberry cinch output (DAC) to the *tape in*, the hifiberry 3.5mm jack input (ADC) to the *tape rec out* of the amp and setup the internal "wiring" (see e.g. the `amsel_small_server` setup) correctly.

# Howto
## Config
1) Create a new environment directory.
2) Populate the variables in the `environment/$YOURENVIRONMENT/host_vars/$HOSTGROUPNAME/main.yml` files with your settings. Checkout `roles/*/defaults/main.yml` to see all variables available.
3) Populate the `inventory` file with the `host` or `hostgroup`
4) Write a playbook

Let you inspire by the files in the `environments` directory, e.g.
* `amsel`:
  * Playbook: `multiroom.yml`
  * Inventory: `inventory`
  * Group vars: `group_vars/*`

## Deployment

In the docroot of this repo, do the following:

Switch to the environment you want to deploy (taking `amsel` here as example):

```
cd environments/amsel
```

Execute the playbook as follows:

```
ANSIBLE_CONFIG=../../ansible.cfg ansible-playbook multiroom.yml -CD -u pi -i inventory
```

Notes:

* To apply the changes (and not only check), remove `C` from the command line.
* If your passwordless login makes you `root` on the Pi (and not `pi`), remove `-u pi` from the command line
