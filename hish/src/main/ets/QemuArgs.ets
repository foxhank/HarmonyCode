/** A TCP port forwarded from the device's 127.0.0.1 into the VM. */
export interface PortForward {
  host: number;
  guest: number;
}

/** Everything needed to boot one hiSH VM. */
export interface HishVmOptions {
  /** arm64 Linux kernel (hiSH's kernel_aarch64). */
  kernelPath: string;
  /** qcow2 root filesystem (ext4, whole disk). */
  rootfsPath: string;
  /** Folder QEMU searches for firmware (efi-virtio.rom). */
  firmwareDir: string;
  /** Host folder exported over virtio-9p with tag 'hostshare'; hiSH images mount it at /mnt/share. */
  sharedDir: string;
  /** Unix socket path for the serial console (created by QEMU). */
  serialSocket: string;
  cpus: number;
  memoryMb: number;
  forwards: PortForward[];
}

/** 9p tag hiSH images mount at /mnt/share (see their /etc/fstab). */
export const SHARE_TAG: string = 'hostshare';
const ROOT_DEVICE: string = '/dev/sda';
const INIT: string = '/init';

/**
 * QEMU command line for a hiSH VM. Ported from hiSH's startVm.ets: an aarch64 'virt' machine with TCG,
 * user-mode networking, a virtio-scsi root disk, a 9p shared folder and the console on the serial port.
 * The 9p share uses security_model=none so no metadata files are written into the user's projects.
 */
export function buildQemuArgs(o: HishVmOptions): string[] {
  const machine: string[] = [
    '-machine', 'virt,acpi=on,gic-version=max,iommu=none,its=off,usb=off,virtualization=off,' +
      'memory-backend=mem0,compact-highmem=on,dump-guest-core=off,mem-merge=off,hmat=off',
    '-overcommit', 'cpu-pm=off',
    '-cpu', 'max,pauth-impdef=on,sve=off,pmu=off',
    '-accel', 'tcg,thread=multi,tb-size=2048',
    '-object', 'rng-random,filename=/dev/urandom,id=rng0',
    '-device', 'virtio-rng-pci-non-transitional,rng=rng0',
    '-rtc', 'base=utc,clock=host',
    '-L', o.firmwareDir,
    '-display', 'none',
    '-monitor', 'none'
  ];
  const cpuMem: string[] = [
    '-smp', `cpus=${o.cpus},sockets=1,cores=${o.cpus},threads=1`,
    '-object', `memory-backend-ram,id=mem0,size=${o.memoryMb}M,merge=off,prealloc=off`,
    '-m', `${o.memoryMb}M`
  ];
  const serial: string[] = ['-serial', `unix:${o.serialSocket},server,nowait`];
  const forwards = o.forwards.map((f: PortForward) => `,hostfwd=tcp:127.0.0.1:${f.host}-:${f.guest}`).join('');
  const network: string[] = [
    '-global', 'virtio-net-pci.ctrl_guest_offloads=off',
    '-global', 'virtio-net-pci.packed=on',
    '-device', 'virtio-net-pci-non-transitional,netdev=eth0,csum=on,gso=on,guest_tso4=on,guest_tso6=on,' +
      'guest_ecn=off,mrg_rxbuf=on,tx=bh',
    '-netdev', 'user,id=eth0' + forwards
  ];
  const shared: string[] = [
    '-fsdev', `local,security_model=none,id=fsdev0,path=${o.sharedDir}`,
    '-device', `virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=${SHARE_TAG}`
  ];
  const disk: string[] = [
    '-global', 'virtio-blk-pci.scsi=off',
    '-global', 'virtio-scsi-pci.cmd_per_lun=128',
    '-global', 'virtio-scsi-pci.packed=on',
    '-drive', `if=none,format=qcow2,file=${o.rootfsPath},id=hd0,cache=writeback,aio=threads,discard=unmap`,
    '-object', 'iothread,id=iothread0,poll-max-ns=2000000',
    '-device', `virtio-scsi-pci-non-transitional,id=scsi0,num_queues=${o.cpus},virtqueue_size=256,iothread=iothread0`,
    '-device', 'scsi-hd,drive=hd0,bus=scsi0.0,logical_block_size=4096,physical_block_size=4096,rotation_rate=1,' +
      'bootindex=1'
  ];
  const kernel: string[] = [
    '-kernel', o.kernelPath,
    '-append', `root=${ROOT_DEVICE} rw rootfstype=ext4 rootwait console=tty0 console=ttyAMA0 consoleblank=0 ` +
      'elevator=noop skew_tick=1 acpi=on mitigations=off audit=0 nmi_watchdog=0 hardened_usercopy=off ' +
      'random.trust_cpu=on virtio_balloon.config_impl=0 security=none selinux=0 apparmor=0 psi=0 ' +
      'page_alloc.shuffle=0 swiotlb=noforce idle=halt cpuidle.off=1 transparent_hugepage=always pci=noaer ' +
      'scsi_mod.use_blk_mq=1 rng_core.default_quality=1000 systemd.mask=run-lock.mount ' +
      'systemd.mask=sys-kernel-debug.mount systemd.mask=dev-hugepages.mount cryptomgr.notests rodata=off ' +
      'rcupdate.rcu_cpu_stall_timeout=60 rcu_expedited=1 init_on_free=0 init_on_alloc=1 page_poison=0 ' +
      `slub_debug=- TERM=xterm-256color init=${INIT}`
  ];
  return ['qemu-system-aarch64'].concat(machine, cpuMem, serial, network, shared, disk, kernel);
}
