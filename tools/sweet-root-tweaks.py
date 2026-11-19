#!/usr/bin/env python3
"""Apply the SWEET bring-up changes to an iOS root made by tools/mkiosroot.sh.

  sudo sweet-root-tweaks.py MOUNTED_ROOT

MOUNTED_ROOT is the HFS+ image mounted read-write (Linux: run
`fsck.hfsplus -fy` on the image, then `mount -t hfsplus -o loop,force`).
Run as root (it writes root/mobile owned files). Idempotent. This is what
turned the plain mkiosroot.sh output into the images that reach the home
screen (image versions v8-v14 in NOTES.md):

  launchd.plist   _PanicOnCrash -> _PanicOnCrasX (a crashing daemon must not
                  panic the system); CommCenter jobs removed (no baseband: it
                  crash-loops and Setup blocks on its CoreTelephony XPC)
  containers      /private/var/containers/{Bundle,Data/System,Shared/SystemGroup,Temp}
                  (on iOS they live on the data volume)
  migration       LastSystemVersion so DataMigration does not run for an hour
                  on every boot
  audio           VirtualAudio HAL plug-in disabled (mediaserverd crash) unless
                  RedwoodAudio.driver is installed (then it is the router to it)
  MediaToolbox    StartRecorderServer=false (camera filter prewarm calls a
                  NULL OpenGL function without a GPU -> mediaserverd crash loop)
  SpringBoard     BKNoWatchdogs (one slow CPU path, no scene-create watchdog
                  kills), no cloud-configuration UI
  Setup           skipped: SetupDone, SetupFinishedAllSteps, SetupVersion 11,
                  mini-buddy flags off
  activation      mobileactivationd data ark seeded; the actual Activated state
                  comes from its Hactivation branch, selected by the /chosen
                  security-status properties in tools/mkadt.py
"""
import glob, os, plistlib, shutil, sys

# Fallbacks only: main() reads the real values from the image's
# System/Library/CoreServices/SystemVersion.plist (e.g. 20F66 / 16.5 for the
# A05s root), so the migration/activation state matches the userland.
BUILD, VERSION = '20F66', '16.5'
MOBILE = 501


def load(path):
    with open(path, 'rb') as f:
        return plistlib.load(f)


def save(path, data, uid, gid, mode, fmt=plistlib.FMT_BINARY):
    with open(path, 'wb') as f:
        plistlib.dump(data, f, fmt=fmt)
    os.chown(path, uid, gid)
    os.chmod(path, mode)


def merge_pref(root, name, values):
    """Merge keys into /var/mobile/Library/Preferences/NAME.plist (mobile, 0600)."""
    path = os.path.join(root, 'private/var/mobile/Library/Preferences', name + '.plist')
    data = load(path) if os.path.exists(path) else {}
    data.update(values)
    save(path, data, MOBILE, MOBILE, 0o600)
    print('pref', name, sorted(values))


def launchd(root):
    path = os.path.join(root, 'System/Library/xpc/launchd.plist')
    st = os.stat(path)
    plist = load(path)
    jobs = plist['LaunchDaemons']
    renamed = 0
    for job in jobs.values():
        if '_PanicOnCrash' in job:
            job['_PanicOnCrasX'] = job.pop('_PanicOnCrash')
            renamed += 1
    removed = [k for k, j in jobs.items() if j.get('Label') == 'com.apple.CommCenter']
    for k in removed:
        del jobs[k]
    # rain: fairplayd.H2 and bluetoothd crash-loop (no FairPlay/BT hardware). launchd keeps their ports,
    # so clients wait forever: locationd's CLMescalSigner (sampled, MIG 1203) and with it Settings >
    # Date & Time; About on bluetoothd. Without the jobs the lookups fail at once.
    dead = [k for k, j in jobs.items() if j.get('Label') in ('com.apple.fairplayd.H2', 'com.apple.bluetoothd')]
    for k in dead:
        del jobs[k]
    print(f'launchd.plist: {len(dead)} crash-looping jobs removed (fairplayd.H2, bluetoothd)')
    # rain: grow the 16 GiB HFS+ root to the whole userdata partition (no-op once grown)
    if os.path.exists(os.path.join(root, 'topaz/bin/hfs-grow')):
        jobs['/System/Library/LaunchDaemons/org.rain.hfs-grow.plist'] = {
            'Label': 'org.rain.hfs-grow', 'ProgramArguments': ['/topaz/bin/hfs-grow'],
            'RunAtLoad': True, 'KeepAlive': False, 'LaunchOnlyOnce': True, 'UserName': 'root',
            'StandardOutPath': '/dev/console', 'StandardErrorPath': '/dev/console'}
        print('launchd.plist: org.rain.hfs-grow job installed')
    # rain: the Metal test at boot (userland/metal/metal_boot.c); does nothing unless the kernel has metal=1
    if os.path.exists(os.path.join(root, 'redwood/bin/metal_boot')):
        jobs['/System/Library/LaunchDaemons/org.rain.metal-boot.plist'] = {
            'Label': 'org.rain.metal-boot', 'ProgramArguments': ['/redwood/bin/metal_boot'],
            'RunAtLoad': True, 'KeepAlive': False, 'LaunchOnlyOnce': True, 'UserName': 'root',
            # /dev/console drops user writes once the system is up; boot with
            # sweetnull=...,metal_boot,metal_props,metal_drv_test and the kernel tees /dev/null to the log
            'StandardOutPath': '/dev/null', 'StandardErrorPath': '/dev/null'}
        print('launchd.plist: org.rain.metal-boot job installed')
    save(path, plist, st.st_uid, st.st_gid, st.st_mode & 0o7777)
    print(f'launchd.plist: {renamed} _PanicOnCrash renamed, {len(removed)} CommCenter jobs removed')


def containers(root):
    base = os.path.join(root, 'private/var/containers')
    for sub, uid in (('Bundle', 33), ('Data/System', 0), ('Shared/SystemGroup', 0), ('Temp', 0)):
        d = os.path.join(base, sub)
        if not os.path.isdir(d):
            os.makedirs(d)
            os.chown(d, uid, uid)
            os.chmod(d, 0o755)
            print('mkdir', d)


def find_container(root, kind, identifier):
    for meta in glob.glob(os.path.join(root, 'private/var/containers', kind, '*',
                                       '.com.apple.mobile_container_manager.metadata.plist')):
        if load(meta).get('MCMMetadataIdentifier') == identifier:
            return os.path.dirname(meta)
    return None


def activation(root):
    c = find_container(root, 'Data/System', 'com.apple.mobileactivationd')
    if c is None:
        print('warning: no mobileactivationd system container in the image; skipped data ark')
        return
    d = os.path.join(c, 'Library/internal')
    os.makedirs(d, exist_ok=True)
    os.chown(d, MOBILE, MOBILE)
    os.chmod(d, 0o755)
    save(os.path.join(d, 'data_ark.plist'), {
        '-ActivationState': 'Activated', '-BrickState': False,
        '-BuildVersion': BUILD, '-ProductVersion': VERSION,
        '-DataMigrationCompleted': True, '-PreSydroDataMigrationCompleted': True,
    }, MOBILE, MOBILE, 0o600)
    print('data ark', d)


def audio(root):
    src = os.path.join(root, 'Library/Audio/Plug-Ins/HAL/VirtualAudio.plugin')
    dst_dir = os.path.join(root, 'Library/Audio/Plug-Ins/HAL.disabled')
    off = os.path.join(dst_dir, 'VirtualAudio.plugin')
    # VirtualAudio crashed mediaserverd while there was no audio device at all (no 'vdef'). With
    # RedwoodAudio (Speaker, Hawking, Actuator, Codec) installed it is what routes iOS's sound to
    # them: without it the plug-in is opened but never played through (rain, 14 November).
    if os.path.isdir(os.path.join(root, 'System/Library/Audio/Plug-Ins/HAL/RedwoodAudio.driver')):
        if os.path.exists(off) and not os.path.exists(src):
            shutil.move(off, os.path.dirname(src))
            print('VirtualAudio.plugin enabled again (RedwoodAudio is installed)')
    elif os.path.exists(src):
        os.makedirs(dst_dir, exist_ok=True)
        shutil.move(src, dst_dir)
        print('VirtualAudio.plugin disabled')
    for conf in glob.glob(os.path.join(root, 'System/Library/Frameworks/MediaToolbox.framework/*/SubServerConfiguration.plist')):
        st = os.stat(conf)
        data = load(conf)
        data['StartRecorderServer'] = False
        save(conf, data, st.st_uid, st.st_gid, st.st_mode & 0o7777, plistlib.FMT_XML)
        print('StartRecorderServer off', os.path.relpath(conf, root))


# Set the owner's zone because Settings > Date & Time is unreliable; override
# with SWEET_TZ=Europe/Berlin etc. (rain used Europe/Berlin).
ZONE = os.environ.get('SWEET_TZ', 'America/Sao_Paulo')


def inside(root, path, depth=0):
    """The host path of `path` inside the image, following the image's own links (absolute ones from its root)."""
    parts, cur = [p for p in path.split('/') if p], root
    for i, part in enumerate(parts):
        cur = os.path.join(cur, part)
        if os.path.islink(cur) and depth < 16:
            target = os.readlink(cur)
            base = '' if target.startswith('/') else os.path.relpath(os.path.dirname(cur), root)
            rest = '/'.join(parts[i + 1:])
            return inside(root, '/'.join(x for x in (base, target.lstrip('/'), rest) if x and x != '.'), depth + 1)
    return cur


def timezone(root):
    """Point /var/db/timezone/localtime at ZONE, in the same zoneinfo tree the image already uses."""
    link = os.path.join(root, 'private/var/db/timezone/localtime')
    old = os.readlink(link) if os.path.islink(link) else None
    base = old.split('zoneinfo/')[0] + 'zoneinfo/' if old and 'zoneinfo/' in old else '/usr/share/zoneinfo/'
    target = base + ZONE
    if not os.path.isfile(inside(root, target)):
        print(f'warning: timezone {target} not in the image (localtime stays {old})')
        return
    os.makedirs(os.path.dirname(link), exist_ok=True)
    if os.path.lexists(link):
        os.remove(link)
    os.symlink(target, link)
    print(f'timezone: localtime {old} -> {target}')

def system_version(root):
    """ProductBuildVersion / ProductVersion of the iOS root being tweaked."""
    try:
        d = load(os.path.join(root, 'System/Library/CoreServices/SystemVersion.plist'))
        return d.get('ProductBuildVersion', BUILD), d.get('ProductVersion', VERSION)
    except Exception:
        return BUILD, VERSION


def main():
    global BUILD, VERSION
    if len(sys.argv) != 2 or not os.path.isdir(os.path.join(sys.argv[1], 'System/Library/xpc')):
        sys.exit(__doc__)
    root = sys.argv[1]
    BUILD, VERSION = system_version(root)
    print(f'root: iOS {VERSION} ({BUILD})')
    launchd(root)
    containers(root)
    activation(root)
    audio(root)
    timezone(root)
    merge_pref(root, 'com.apple.migration', {
        'LastSystemVersion': BUILD,
        'DMUserDataDisposition': {'SyntheticDidUpgrade': False, 'buildVersion': BUILD}})
    merge_pref(root, 'com.apple.springboard', {
        'BKNoWatchdogs': True,
        'FBLaunchWatchdogExceptions': {'com.apple.purplebuddy': 100.0},
        'MCForceShowCloudConfigurationUI': False})
    merge_pref(root, 'com.apple.purplebuddy', {
        'SetupDone': True, 'SetupFinishedAllSteps': True, 'SetupVersion': 11,
        'daemonizeNeedsToRun': False})
    merge_pref(root, 'com.apple.purplebuddy.notbackedup', {
        k: False for k in ('ShouldRunDiagnosticsMiniBuddy', 'ShouldRunHSA2MiniBuddy',
                           'ShouldRunKeychainSyncMiniBuddy', 'ShouldRunMesaMiniBuddy',
                           'ShouldRunPaymentMiniBuddy', 'ShouldRunStandardMiniBuddy',
                           'SilentICDPUpgrade')})
    merge_pref(root, 'com.apple.managedconfiguration.notbackedup', {
        'LockdownActivationIndicatesCloudConfigurationAvailable': False})


if __name__ == '__main__':
    main()
