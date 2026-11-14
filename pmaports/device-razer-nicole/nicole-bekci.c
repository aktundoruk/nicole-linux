// SPDX-License-Identifier: MIT
/*
 * nicole-bekci: returns the phone to fastboot when the initramfs never reaches the real root.
 *
 * A failed pmOS initramfs ends in a debug shell that loops forever, and on this phone USB does
 * not come up in that state, so only a key press gets it back (5 Nov 2026). Runs as the first
 * process (rdinit=/nicole-bekci nicole.bekci=SECONDS), forks a watcher and execs /init, which
 * keeps PID 1. The watcher does nothing while PID 1's root changes in time.
 *
 * With nicole.bekci.yeniden on the cmdline it restarts instead (8 Nov 2026): slot A, whose
 * rescue is now the Linux in slot B, so a kernel written from Linux that never reaches its root
 * uses up one boot try per start and after seven ABL boots B, with no key press and no Mac.
 * Slot B keeps going to fastboot: it is the last Linux, a restart would loop on it.
 *
 * Every doubt means "do not reboot", which is the behaviour without this program:
 *  - no nicole.bekci= or pmos.debug-shell on the cmdline: no watcher at all;
 *  - it cannot read PID 1's root: exits;
 *  - no reboot-mode driver offers "bootloader" (a plain reboot would use up one of slot A's
 *    seven boot attempts and end in Android): exits.
 *
 * Does not cover a kernel panic before this runs, or a system that fails after switch_root.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <linux/reboot.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define KOK "/.bekci"

static int kmsg = -1;

static void yaz(const char *s)
{
	if (kmsg >= 0 && write(kmsg, s, strlen(s)) < 0)
		kmsg = -1;
}

static ssize_t oku(int dir, const char *ad, char *buf, size_t n)
{
	int fd = openat(dir, ad, O_RDONLY | O_CLOEXEC);
	ssize_t r;

	if (fd < 0)
		return -1;
	r = read(fd, buf, n - 1);
	close(fd);
	if (r >= 0)
		buf[r] = 0;
	return r;
}

/* The word on a space-separated list, not a piece of a longer word. */
static const char *kelime(const char *s, const char *k)
{
	size_t n = strlen(k);

	for (const char *p = s; (p = strstr(p, k)); p += n)
		if ((p == s || p[-1] == ' ') && (!p[n] || strchr(" \n=", p[n])))
			return p;
	return NULL;
}

static int bootloader_var(int sys)
{
	char ad[300], buf[512];
	int fd = openat(sys, "class/reboot-mode", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
	DIR *d = fd < 0 ? NULL : fdopendir(fd);
	struct dirent *e;
	int var = 0;

	if (!d)
		return 0;
	while (!var && (e = readdir(d))) {
		if (e->d_name[0] == '.')
			continue;
		snprintf(ad, sizeof(ad), "class/reboot-mode/%s/reboot_modes", e->d_name);
		var = oku(sys, ad, buf, sizeof(buf)) > 0 && kelime(buf, "bootloader");
	}
	closedir(d);
	return var;
}

static void bekle(void)
{
	struct stat ilk, st;
	char buf[4096], ileti[160];
	const char *p;
	long sure;
	int proc, sys, yeniden;

	/* Own mounts: init's switch_root moves and deletes its own. These fds outlive that. */
	if (unshare(CLONE_NEWNS) || mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL))
		_exit(0);
	mkdir(KOK, 0700);
	mkdir(KOK "/proc", 0700);
	mkdir(KOK "/sys", 0700);
	mkdir(KOK "/dev", 0700);
	if (mount("proc", KOK "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL) ||
	    mount("sysfs", KOK "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL))
		_exit(0);
	if (!mount("dev", KOK "/dev", "devtmpfs", MS_NOSUID, NULL))
		kmsg = open(KOK "/dev/kmsg", O_WRONLY | O_CLOEXEC);
	proc = open(KOK "/proc", O_PATH | O_DIRECTORY | O_CLOEXEC);
	sys = open(KOK "/sys", O_PATH | O_DIRECTORY | O_CLOEXEC);
	if (proc < 0 || sys < 0 || stat("/", &ilk))
		_exit(0);

	if (oku(proc, "cmdline", buf, sizeof(buf)) <= 0 || kelime(buf, "pmos.debug-shell") ||
	    !(p = kelime(buf, "nicole.bekci")) || p[12] != '=')
		_exit(0);
	sure = strtol(p + 13, NULL, 10);
	if (sure <= 0)
		_exit(0);
	yeniden = kelime(buf, "nicole.bekci.yeniden") != NULL;

	for (long t = 0; t < sure; t++) {
		sleep(1);
		if (fstatat(proc, "1/root/", &st, 0))
			_exit(0);
		if (st.st_dev != ilk.st_dev || st.st_ino != ilk.st_ino)
			_exit(0);
	}
	if (yeniden) {
		snprintf(ileti, sizeof(ileti), "<3>nicole-bekci: root not reached in %ld s, restarting\n", sure);
		yaz(ileti);
		sync();
		syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, LINUX_REBOOT_CMD_RESTART, NULL);
		_exit(0);
	}
	if (!bootloader_var(sys)) {
		yaz("<3>nicole-bekci: no reboot mode offers bootloader, staying here\n");
		_exit(0);
	}
	snprintf(ileti, sizeof(ileti), "<3>nicole-bekci: root not reached in %ld s, going to fastboot\n", sure);
	yaz(ileti);
	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, LINUX_REBOOT_CMD_RESTART2, "bootloader");
	_exit(0);
}

int main(int argc, char **argv)
{
	(void)argc;
	if (getpid() != 1) {
		fprintf(stderr, "nicole-bekci: only runs as the first process\n");
		return 1;
	}
	if (fork() == 0)
		bekle();
	argv[0] = "/init";
	execv("/init", argv);
	/* PID 1 must not exit: that panics into a plain reboot. The watcher still ends this. */
	for (;;)
		pause();
}
