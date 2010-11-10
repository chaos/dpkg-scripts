/***************************************************************************
 Copyright (C) 2007 Lawrence Livermore National Security, LLC
 Produced at Lawrence Livermore National Laboratory.
 Written by Jim Garlick <garlick@llnl.gov>.
 UCRL-CODE-235516
 
 This file is part of dpkg-scripts, a set of utilities for managing 
 packages in /usr/local with dpkg.
 
 dpkg-scripts is free software; you can redistribute it and/or modify it 
 under the terms of the GNU General Public License as published by the Free
 Software Foundation; either version 2 of the License, or (at your option)
 any later version. 

 dpkg-scripts is distributed in the hope that it will be useful, but WITHOUT 
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
 FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for 
 more details.

 You should have received a copy of the GNU General Public License along
 with dpkg-scripts; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA.
***************************************************************************/

/* dpkg-tmplocal - bind a writeable tmpdir over /usr/local in private namespace 
 *
 * This file is installed setuid.  It does the following as root:
 * 1. creates tmp directory (chowned to the user)
 * 2. forks child process
 * 3. (child) unshares the namespace
 * 4. (child) binds tmp directory on /usr/local
 * The child process then loses its effective root id and runs the command as 
 * the real userid (which cannot be root).  Since the bind mount is 
 * performed in the private namespace of the child process, it is invisible 
 * to others and is automatically cleaned up when the child process exits.
 * The parent (still root) just waits for the child and removes the tmp
 * directory.
 */

#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/mount.h>
#include <sched.h>
#include <errno.h>
#include <libgen.h>
#include <string.h>
#include <grp.h>
#include <pwd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <getopt.h>

static char 	*create_tmpdir(uid_t uid, gid_t gid);
static void	exec_cmd(uid_t uid, gid_t gid, int oopt,
			 int vopt, char *dir,char **argv);
static int	recursive_remove(char *name);

static char *prog;

#define OPTIONS "+od:vp"
static struct option longopts[] = {
    {"slash-opt",       no_argument,       0, 'o'},
    {"dir",             required_argument, 0, 'd'},
    {"verbose",         no_argument,       0, 'v'},
    {"preserve",        no_argument,       0, 'p'},
    {0, 0, 0, 0},
};

static void
usage(void)
{
	fprintf(stderr, "Usage: %s [-ovp] [-d dir] cmd [args...]\n", prog);
	exit(1);
}


int
main(int argc, char **argv)
{
	pid_t pid, p;
	int exit_code = 0;
	uid_t uid;
	gid_t gid;
	int wstat;
	int c;
	char *dir = NULL;
	struct stat sb;
	int vopt = 0;
	int popt = 0;
	int oopt = 0;
	
	prog = basename(argv[0]);
        while ((c = getopt_long(argc, argv, OPTIONS, longopts, NULL)) != EOF) {
                switch (c) {
			case 'o': /* --slash-opt */
				oopt++;
				break;
                        case 'd': /* --dir */
                                dir = optarg;
                                break;
                        case 'v': /* --verbose */
				vopt++;
				break;
                        case 'p': /* --preserve */
				popt++;
				break;
                        default:
                                usage();
                                break;
                }
        }
	if (optind == argc)
		usage();
	uid = getuid();
	gid = getgid();
	if (uid == 0) {
		fprintf(stderr, "%s: will not run as root\n", prog);
		exit(1);
	}

	if (dir || popt) {	/* no need to clean up so no fork */
		if (dir && (lstat(dir, &sb) < 0 || !S_ISDIR(sb.st_mode))) {
			fprintf(stderr, "%s: %s: not a directory\n", prog, dir);
			exit(1);
		}
		if (!dir && !(dir = create_tmpdir(uid, gid)))
			exit(1);
		exec_cmd(uid, gid, oopt, vopt, dir, &argv[optind]);
		exit_code = 1;
	} else {
		if (!(dir = create_tmpdir(uid, gid)))
			exit(1);
		switch ((pid = fork())) {
			case -1:	/* error */
				fprintf(stderr, "%s: fork: %m\n", prog);
				exit_code = 1;
			case 0:		/* child */
				exec_cmd(uid, gid, oopt, vopt, dir, &argv[optind]);
				exit(1);
			default:	/* parent */
				p = waitpid(pid, &wstat, 0);
				if ((int) p == -1) {
					fprintf(stderr, "%s: waitpid: %m\n", 
							prog);
					exit_code = 1;
				} else if (WIFEXITED(wstat)) {
					exit_code = WEXITSTATUS(wstat);
				} else { /* signal = error */
					exit_code = 1;
				}
				break;
		}
		if (!popt) {
			if (vopt)
				fprintf(stderr, "%s: removing %s\n", prog, dir);
			if (!recursive_remove(dir)) {
				fprintf(stderr, "%s: failed to clean up %s\n", 
					prog, dir);
				exit_code = 1;
			}
		}
	}
	exit(exit_code);
}

static void
exec_cmd(uid_t uid, gid_t gid, int oopt, int vopt, char *dir, char *argv[])
{
	char *target = oopt ? "/opt" : "/usr/local";

	if (unshare(CLONE_NEWNS) < 0) {
		fprintf(stderr, "%s: unshare: %m\n", prog);
		return;
	}
	if (vopt)
		fprintf(stderr, "%s: binding %s on %s\n", prog, dir, target);
	if (mount(dir, target, NULL, MS_BIND, NULL) < 0) {
		fprintf(stderr, "%s: mount: %m\n", prog);
		return;
	}
	if (vopt)
		fprintf(stderr, "%s: dropping root privileges\n", prog);
	if (setgid(gid) < 0) {
		fprintf(stderr, "%s: setgid: %m\n", prog);
		return;
	}
	if (setuid(uid) < 0) {
		fprintf(stderr, "%s: setuid: %m\n", prog);
		return;
	}
	if (vopt)
		fprintf(stderr, "%s: execing %s\n", prog, argv[0]);
	execvp(argv[0], argv);
	fprintf(stderr, "%s: exec: %s: %m\n", prog, argv[0]);
}

static int
recursive_remove(char *name)
{
	struct dirent *dp;
	DIR *dir; 
	int res = 1;
	char path[MAXPATHLEN];

	if (!(dir = opendir(name))) {
		fprintf(stderr, "%s: opendir %s: %m\n", prog, name);
		return 0;
	}
	while ((dp = readdir(dir))) {
		if (!strcmp(dp->d_name, "."))
			continue;
		if (!strcmp(dp->d_name, ".."))
			continue;
		snprintf(path, sizeof(path), "%s/%s", name, dp->d_name);
		if (dp->d_type == DT_DIR) { 
			if (!recursive_remove(path)) {
				res = 0;
				break;
			}
		} else {
			if (unlink(path) < 0) {
				fprintf(stderr, "%s: unlink %s: %m\n", prog, path);
				res = 0;
				break;
			}
		}
	}
	if (closedir(dir) < 0) {
		fprintf(stderr, "%s: closedir %s: %m\n", prog, name);
		res = 0;
	}
	if (rmdir(name) < 0) {
		fprintf(stderr, "%s: rmdir %s: %m\n", prog, name);
		res = 0;
	}
	return res;
}


static char *
create_tmpdir(uid_t uid, gid_t gid)
{
	static char template[] = "/tmp/tmplocal-XXXXXX";

	if (mkdtemp(template) == NULL) { /* mode 0700 */
		fprintf(stderr, "%s: mkdtemp failed\n", prog);
		return NULL;
	}
	if (chown(template, uid, gid) < 0) {
		fprintf(stderr, "%s: chown: %m\n", prog);
		recursive_remove(template);
		return NULL;
	}
	return template;
}

