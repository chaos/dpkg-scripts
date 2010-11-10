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

/* dpkg-lndir - like lndir(1) with rootdir arguments
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

static char *prog;

void
zap_trailing_slashes(char *buf)
{
	char *p = buf + strlen(buf) - 1;

	while (p > buf && *p == '/')
		*p-- = '\0';
}

char *
skip_leading_slashes(char *buf)
{
	char *p = buf;

	while (*p && *p == '/')
		p++;
	return p;
}

char *
pathcat(char *p1, char *p2)
{
	int len = strlen(p1) + strlen(p2) + 2;
	char *new = malloc(len);

	if (!new) {
		fprintf(stderr, "%s: out of memory\n", prog);
		exit(1);
	}
	strcpy(new, p1);
	zap_trailing_slashes(new);
	strcat(new, "/");
	strcat(new, skip_leading_slashes(p2));

	return new;
}

static void
lndir(char *r1, char *p1, char *r2, char *p2)
{
	struct dirent *dp;
	struct stat sb;
	DIR *dir; 
	char *rp1 = pathcat(r1, p1);
	char *rp2 = pathcat(r2, p2);

	if (mkdir(rp2, 0755) == -1) {
		fprintf(stderr, "%s: %s: %m\n", prog, rp2);
		exit(1);
	}
	if (!(dir = opendir(rp1))) {
		fprintf(stderr, "%s: opendir %s: %m\n", prog, rp1);
		exit(1);
	}
	while ((dp = readdir(dir))) {
		if (strcmp(dp->d_name, ".") && strcmp(dp->d_name, "..")) {
			char *n1 = pathcat(p1, dp->d_name);
			char *n2 = pathcat(p2, dp->d_name);
			char *rn1 = pathcat(r1, n1);
			char *rn2 = pathcat(r2, n2);

			if (lstat(rn1, &sb) < 0) {
				fprintf(stderr, "%s: lstat %s: %m\n", 
					prog, rn1);
				exit(1);
			}
			if (S_ISDIR(sb.st_mode)) {
				lndir(r1, n1, r2, n2);
			} else if (symlink(n1, rn2) < 0) {
				fprintf(stderr, "%s: symlink %s -> %s: %m\n", 
					prog, n1, rn2);
				exit(1);
			}

			free(n1);
			free(n2);
			free(rn1);
			free(rn2);
		}
	}
	if (closedir(dir) < 0) {
		fprintf(stderr, "%s: closedir %s: %m\n", prog, rp1);
		exit(1);
	}
	free(rp1);
	free(rp2);
}

void 
test_exist_dir(char *path)
{
	struct stat sb;

	if (stat(path, &sb) == -1) {
		fprintf(stderr, "%s: %s does not exist\n", prog, path);
		exit(1);
	}
	if (!S_ISDIR(sb.st_mode)) {
		fprintf(stderr, "%s: %s is not a directory\n", prog, path);
		exit(1);
	}
}

void
test_noexist(char *path)
{
	struct stat sb;

	if (stat(path, &sb) != -1) {
		fprintf(stderr, "%s: %s exists\n", prog, path);
		exit(1);
	}
}

void
test_fq_path(char *path)
{
	if (*path != '/') {
		fprintf(stderr, "%s: directories must start with /\n", prog);
		exit(1);
	}
}

int
main(int argc, char **argv)
{
	char *r1, *p1, *r2, *p2;
	char *path;
	
	prog = basename(argv[0]);
	if (argc != 5) {
		fprintf(stderr, "Usage: %s fromroot fromdir toroot todir\n", prog);
		exit(1);
	}
	r1 = argv[1];
	p1 = argv[2];
	r2 = argv[3];
	p2 = argv[4];

	if (getuid() == 0) {
		fprintf(stderr, "%s: will not run as root\n", prog);
		exit(1);
	}

	/* only fully qualified paths allowed */
	test_fq_path(r1);
	test_fq_path(p1);
	test_fq_path(r2);
	test_fq_path(p2);

	/* source (fromroot + fromdir) must be existing directory */
	path = pathcat(r1, p1);
	test_exist_dir(path);
	free(path);

	/* destination (toroot + todir) must not exist */
	path = pathcat(r2, p2);
	test_noexist(path);
	/* but directory containing it must exist */
	test_exist_dir(dirname(path));
	free(path);

	lndir(r1, p1, r2, p2);
	exit(0);
}
