/***************************************************************************
 Copyright (C) 2008 Lawrence Livermore National Security, LLC
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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <unistd.h>
#include <ctype.h>
#include <fcntl.h>
#include <getopt.h>
#include <dirent.h>

#include "list.h"
#include "hash.h"
#include "md5sum.h"
#include "base64.h"

#define FILEINFO_MAGIC 0x2345abcd
struct fileinfo_struct {
	int 	fi_magic;
	char   *fi_pkg;
	char   *fi_path;
	char   *fi_md5sum;
	char   *fi_linkdata;
	int     fi_confFlag;
};
typedef struct fileinfo_struct *fileinfo_t;

typedef enum { FT_DIR, FT_REG, FT_SYMLINK } ftype_t;

struct error_summary {
	int	missing;
	int	dangsym;
	int	type;
	int 	ownergroup;
	int 	setuid;
	int	too_open;
	int	too_restricted;
	int	md5sum;
	int	linkdata;
	int	metadata;
};


static void 		add_pkg_glob(List pkgs, char *glob);
static void 		get_dpkg_uid(uid_t *up, gid_t *gp);

static int		verify_file(fileinfo_t fi, const void *key, char *arg);
static void     	verify_stat(char *pkg, char *path, ftype_t ft);
static void 		verify_md5sum(char *pkg, char *path, char *md5sum);
static void		verify_linkdata(char *pkg, char *path, char *linkdata);

static void		find_unpackaged(hash_t files, const char *dir);

static void     	read_pkg_info(char *pkg, hash_t files);
static void     	read_pkg_md5sums(char *pkg, hash_t files);
static void     	read_pkg_conffiles(char *pkg, hash_t files);
static void     	read_pkg_linkdata(char *pkg, hash_t files);
static void		usage(void);

static char 	       *pathnorm(const char *s);
static char 	       *pathdenorm(const char *s);
static char            *pathcat(const char *p1, const char *p2);
static char            *xstrdup(const char *s);
static void            *xmalloc(const size_t size);

static fileinfo_t	fi_create(char *pkg, char *path);
static void		fi_destroy(fileinfo_t fi);


static const char *prog = "dpkg-verify";

static const char *list_cmd_tmpl = "dpkg-query -Wf '${package} ${status}\n' \
    '%s' | awk '$4 == \"installed\" {print $1}'";

static const char *root_path           = "/usr/local";
static const char *dpkg_db_path        = "/usr/local/dpkg-db";
static const char *list_path_tmpl      = "/usr/local/dpkg-db/info/%s.list";
static const char *md5sums_path_tmpl   = "/usr/local/dpkg-db/info/%s.md5sums";
static const char *linkdata_path_tmpl  = "/usr/local/dpkg-db/info/%s.linkdata2";
static const char *conffiles_path_tmpl = "/usr/local/dpkg-db/info/%s.conffiles";
static const char *ignore_dirs[] = {
    "/usr/local/dpkg-db/", /* trailing slash is important */
    "/usr/local/var/",
    NULL,
};   

#define MD5LEN 		32
#define HASH_BUCKETS	1000000

#define OPTIONS "umh?"
static struct option longopts[] = {
    {"help",            no_argument,       0, 'h'},
    {"unpackaged",      no_argument,       0, 'u'},
    {"md5sums",         no_argument,       0, 'm'},
    {0, 0, 0, 0},
};

static uid_t dpkg_uid;
static gid_t dpkg_gid;
static struct error_summary e;

int
main(int argc, char *argv[])
{
	List pkgs = list_create(free);
	ListIterator itr;
	hash_t files;
	char *pkg;
	int uopt = 0;
	int mopt = 0;
	int c;

	while ((c = getopt_long(argc, argv, OPTIONS, longopts, NULL)) != EOF) {
		switch (c) {
			case 'u': /* --unpackaged */
				uopt++;
				break;
			case 'm': /* --md5sums */
				mopt++;
				break;
			default:
				usage();
				break;
		}
	}
	if (uopt && optind < argc)
		usage();

	/* Create list of packages from command line.
	 */
	if (optind == argc) {
		add_pkg_glob(pkgs, "*");
	} else {
		while (optind < argc)
			add_pkg_glob(pkgs, argv[optind++]);
	}

	/* Cache package metadata.
	 */
	files = hash_create(HASH_BUCKETS, (hash_key_f)hash_key_string,
			                  (hash_cmp_f)strcmp,
			                  (hash_del_f)fi_destroy);
	itr = list_iterator_create(pkgs);
	while ((pkg = list_next(itr)) != NULL) {
		read_pkg_info(pkg, files);
		if (!uopt) {
			read_pkg_md5sums(pkg, files);
			read_pkg_linkdata(pkg, files);
			read_pkg_conffiles(pkg, files);
		}
	}
	list_iterator_destroy(itr);
	fprintf(stderr, "%s: cached metadata for %d packages (%d files)\n", 
		prog, list_count(pkgs), hash_count(files));

	/* Now check.
	 */
	if (uopt) {
		find_unpackaged(files, root_path);
	} else {
		get_dpkg_uid(&dpkg_uid, &dpkg_gid);
		memset(&e, 0, sizeof(e));

		hash_for_each(files, (hash_arg_f)verify_file, &mopt);

		printf("======================================\n");
		printf("Verification summary:\n");
		printf("Missing files: %d\n", e.missing);
		printf("Damaged files: %d\n", e.md5sum);
		printf("Dangling symlinks: %d\n", e.dangsym);
		printf("Wrong file type: %d\n", e.type);
		printf("Wrong owner/group: %d\n", e.ownergroup);
		printf("Setuid/setgid/sticky: %d\n", e.setuid);
		printf("Mode too open: %d\n", e.too_open);
		printf("Mode too restrictive: %d\n", e.too_restricted);
		printf("Metadata corruption: %d\n", e.metadata);
		printf("Symlink pointing to wrong target: %d\n", e.linkdata);
	}

	list_destroy(pkgs);
	hash_destroy(files);
	exit(0);
}

static void
usage(void)
{
	fprintf(stderr, "Usage: %s [--md5sum] [pkg-glob] ...\n", prog);
	fprintf(stderr, "       %s --unpackaged\n", prog);
	exit(1);
}

static int
unpackaged_ignore(char *path)
{
	int i;

	for (i = 0; ignore_dirs[i] != NULL; i++)
		if (!strncmp(path, ignore_dirs[i], strlen(ignore_dirs[i])))
			return 1;
	return 0;
}

static void
find_unpackaged(hash_t files, const char *path)
{
	struct dirent *dp;
	char *fqp, *norm;
	DIR *dir;

	if (!(dir = opendir(path))) {
		fprintf(stderr, "%s: could not open %s\n", prog, path);
		return;
	}
	while ((dp = readdir(dir))) {
		if (!strcmp(dp->d_name, ".") || !strcmp(dp->d_name, ".."))
			continue;
		fqp = pathcat(path, dp->d_name);
		norm = pathnorm(fqp);
		if (dp->d_type == DT_DIR)
			find_unpackaged(files, fqp);
		else if (! hash_find (files, norm) && !unpackaged_ignore(fqp))
			fprintf(stderr, "%s: unpackaged: %s\n", prog, fqp);
		free(fqp);
		free(norm);
	}
	if (closedir(dir) < 0)
		fprintf(stderr, "%s: closedir %s: %m\n", prog, path);
}


/* Verify one file in a package
 */
static int
verify_file(fileinfo_t fi, const void *key, char *arg)
{
	int mopt = *(int *)arg;
	char *path;

	assert(fi->fi_magic == FILEINFO_MAGIC);
	path = pathdenorm(fi->fi_path);
	verify_stat(fi->fi_pkg, path, fi->fi_md5sum ? FT_REG 
                             : fi->fi_linkdata ? FT_SYMLINK : FT_DIR);
	if (mopt && !fi->fi_confFlag && fi->fi_md5sum)
		verify_md5sum(fi->fi_pkg, path, fi->fi_md5sum);
	if (!fi->fi_confFlag && fi->fi_linkdata)
		verify_linkdata(fi->fi_pkg, path, fi->fi_linkdata);
	free(path);
	return 0;
}

/* Verify that file modes conform to packaging constraints.
 */
static void
verify_stat(char *pkg, char *path, ftype_t ft)
{
	struct stat sb, sb2;

	if (lstat(path, &sb) < 0) {
		fprintf(stderr, "%s: %s: missing %s\n", 
				prog, pkg, path);
		e.missing++;
		return;
	}
	/* Verify that file type matches expected type.
	 */
	if ((ft == FT_REG && !S_ISREG(sb.st_mode))
	    || (ft == FT_DIR && !S_ISDIR(sb.st_mode))
	    || (ft == FT_SYMLINK && !S_ISLNK(sb.st_mode))) {
		fprintf(stderr, "%s: %s: wrong type %s\n", prog, pkg, path);
		e.type++;
	}
	
	/* Check for existence of link target if symlink.
	 */
	if (S_ISLNK(sb.st_mode) && stat(path, &sb2) < 0) {
		fprintf(stderr, "%s: %s: dangling symlink %s\n", 
				prog, pkg, path);
		e.dangsym++;
	}
	/* Owner and group should match that of dpkg-db directory.
	 */
	if (sb.st_uid != dpkg_uid) {
		fprintf(stderr, "%s: %s: wrong owner %d %s\n", 
				prog, pkg, sb.st_uid, path);
		e.ownergroup++;
	}
	if (sb.st_gid != dpkg_gid) {
		fprintf(stderr, "%s: %s: wrong group %d %s\n", 
				prog, pkg, sb.st_gid, path);
		e.ownergroup++;
	}
	/* No publicly writeable files/dirs.
	 */
	if (!S_ISLNK(sb.st_mode) && (sb.st_mode & (S_IWOTH | S_IWGRP))) {
		fprintf(stderr, "%s: %s: mode too permissive%s\n", 
			prog, pkg, path);
		e.too_open++;
	}
	/* No unsearchable directories.
	 */
	if (S_ISDIR(sb.st_mode)
	  && (!(sb.st_mode & S_IXOTH) || !(sb.st_mode & S_IXGRP))) {
		fprintf(stderr, "%s: %s: mode too restrictive %s\n", 
			prog, pkg, path);
		e.too_restricted++;
	}
	/* No unreadable files/dirs.
	 */
	if (!(sb.st_mode & S_IROTH) || !(sb.st_mode & S_IRGRP)) {
		fprintf(stderr, "%s: %s: mode too restrictive %s\n", 
			prog, pkg, path);
		e.too_restricted++;
	}
	/* No files that are executably by owner but not group/other.
	 */
	if (S_ISREG(sb.st_mode) && (sb.st_mode & S_IXUSR)
	  && (!(sb.st_mode & S_IXOTH) || !(sb.st_mode & S_IXGRP))) {
		fprintf(stderr, "%s: %s: mode too restrictive %s\n", 
			prog, pkg, path);
		e.too_restricted++;
	}
	/* No setuid, setgid, or sticky bits set.
 	 */
	if ((sb.st_mode & (S_ISUID | S_ISGID | S_ISVTX))) {
		fprintf(stderr, "%s: %s: has setuid %s\n", prog, pkg, path);
		e.setuid++;
	}
}

static void
verify_md5sum(char *pkg, char *path, char *md5sum)
{
	char *cpy = NULL; 
	char *newsum;

	if (*path != '/') {
		cpy = xmalloc(strlen(path) + 2);
		sprintf(cpy, "/%s", path);
	}
	if (!(newsum = generate_md5sum(cpy ? cpy : path))) {
		fprintf(stderr, "%s: %s: %s: %m\n", prog, pkg, path);
		goto done;
	}
	if (strcmp(newsum, md5sum) != 0) {
		fprintf(stderr, "%s: %s: wrong md5sum %s\n", prog, pkg, path);
		e.md5sum++;
	}
done:
	if (cpy)
		free(cpy);
}

static void
verify_linkdata(char *pkg, char *path, char *linkdata)
{
	char *base64 = NULL;
	char buf[MAXPATHLEN + 1];
	int n; 

	if ((n = readlink(path, buf, MAXPATHLEN)) < 0) {
		fprintf(stderr, "%s: %s: %s: %m\n", prog, pkg, path);
		goto done;
	}
	buf[n] = '\0';
	if (!(base64 = encode_base64(buf))) {
		fprintf(stderr, "%s: %s: %s: %m\n", prog, pkg, path);
		goto done;
	}
	if (strcmp(base64, linkdata) != 0) {
		fprintf(stderr, "%s: %s: wrong link target %s\n", 
			prog, pkg, path);
		e.linkdata++;
	}
done:
	if (base64)
		free(base64);
}

/* Create a fileinfo_t for the specified 'path'.
 */
static fileinfo_t
fi_create(char *pkg, char *path)
{
	char *p = pathnorm(path);
	fileinfo_t fi = NULL;

	if (p != NULL) {
		fi = xmalloc(sizeof(struct fileinfo_struct));
		fi->fi_magic = FILEINFO_MAGIC;
		fi->fi_pkg = xstrdup(pkg);
		fi->fi_path = p;
		fi->fi_md5sum = NULL;
		fi->fi_confFlag = 0;
		fi->fi_linkdata = NULL;
	}
	return fi;
}

/* Destroy a fileinfo_t.
 */
static void
fi_destroy(fileinfo_t fi)
{
	assert(fi->fi_magic == FILEINFO_MAGIC);
	fi->fi_magic = 0;
	if (fi->fi_pkg)
		free(fi->fi_pkg);
	if (fi->fi_path)
		free(fi->fi_path);
	if (fi->fi_md5sum)
		free(fi->fi_md5sum);
	if (fi->fi_linkdata)
		free(fi->fi_linkdata);
	free(fi);
}

static void
zap_trailing_newline(char *s)
{
	if (strlen(s) > 0 && s[strlen(s) - 1] == '\n')
		s[strlen(s) - 1] = '\0';	
}

/* Populate fileinfo_t hash with package's files.
 */
static void
read_pkg_info(char *pkg, hash_t files)
{
	char list_path[MAXPATHLEN + 1];
	char buf[4096];
	FILE *f;
	fileinfo_t fi;
	
	snprintf(list_path, sizeof(list_path), list_path_tmpl, pkg);
	f = fopen(list_path, "r");
	if (!f) {
		fprintf(stderr, "%s: %s: failed to open %s\n", 
				prog, pkg, list_path);
		hash_destroy(files);
		files = NULL;
		e.metadata++;
		return;
	}
	while (fgets(buf, sizeof(buf), f) != NULL) {
		zap_trailing_newline(buf);
		fi = fi_create(pkg, buf);
		if (fi == NULL) { 
			fprintf(stderr, "%s: %s: %s: mangled list entry\n",
				prog, pkg, buf);
			e.metadata++;
			continue;
		}
		if (!hash_insert(files, fi->fi_path, fi)) {
			struct stat sb;
			char *path = pathdenorm(fi->fi_path);

			if (errno == EEXIST && lstat(path, &sb) == 0 
			  && S_ISDIR(sb.st_mode)) {
				free(path);
				continue;
			}
			fprintf(stderr, "%s: %s: %s: %m\n",
					prog, pkg, fi->fi_path);
			free(path);
			e.metadata++;
			continue;
		}
	}
	fclose(f);
}

static char *
next_tok(char *s)
{
	int n;

	for (n = 0; *s != '\0'; s++) {
		if (n > 0 && !isspace(*s))
			break;
		if (isspace(*s)) {
			n++;
			*s = '\0';
		}
	}
	return s;
}

/* Add md5sum information to fileinfo_t hash.
 */
static void     
read_pkg_md5sums(char *pkg, hash_t files)
{
	char md5sums_path[MAXPATHLEN + 1];
	char buf[4096], *md5sum, *path, *norm;
	fileinfo_t fi;	
	FILE *f;

	/* File format is one file per line:
	 *   md5sum\s*path
	 */
	snprintf(md5sums_path, sizeof(md5sums_path), md5sums_path_tmpl, pkg);
	f = fopen(md5sums_path, "r");
	if (!f)
		return;
	while (fgets(buf, sizeof(buf), f) != NULL) {
		zap_trailing_newline(buf);
		if (strlen(buf) == 0)
			continue;
		md5sum = buf;
		path = next_tok(buf);
		norm = pathnorm(path);
		if (norm == NULL || strlen(md5sum) != MD5LEN) {
			fprintf(stderr, "%s: %s: %s: mangled md5sum entry\n",
				prog, pkg, norm ? norm : path);
			e.metadata++;
			if (norm)
				free(norm);
			continue;
		}
		fi = hash_find (files, norm);
		if (fi == NULL) {
			fprintf(stderr, "%s: %s: %s: bogus md5sum entry\n",
				prog, pkg, norm);
			e.metadata++;
			free(norm);
			continue;
		}
		free(norm);
		assert(fi->fi_magic == FILEINFO_MAGIC);
		if (fi->fi_md5sum != NULL) {
			fprintf(stderr, "%s: %s: %s: duplicate md5sum entry\n",
				prog, pkg, fi->fi_path);
			e.metadata++;
			continue;
		}
		fi->fi_md5sum = xstrdup(md5sum);
	}
	fclose(f);
}

/* Add conffiles information to fileinfo_t hash.
 */
static void
read_pkg_conffiles(char *pkg, hash_t files)
{
	char conffiles_path[MAXPATHLEN + 1];
	char buf[4096];
	fileinfo_t fi;	
	FILE *f;
	char *norm;

	/* File format is one file per line.
	 */
	snprintf(conffiles_path, sizeof(conffiles_path), 
                 conffiles_path_tmpl, pkg);
	f = fopen(conffiles_path, "r");
	if (!f)
		return;
	while (fgets(buf, sizeof(buf), f) != NULL) {
		zap_trailing_newline(buf);
		if (strlen(buf) == 0)
			continue;
		norm = pathnorm(buf);
		if (norm == NULL) {
			fprintf(stderr, "%s: %s: %s: mangled conffiles entry\n",
				prog, pkg, buf);
			e.metadata++;
			continue;
		}
		fi = hash_find (files, norm);
		if (fi == NULL) {
			fprintf(stderr, "%s: %s: %s: bogus conffiles entry\n",
				prog, pkg, norm);
			e.metadata++;
			free(norm);
			continue;
		}
		free(norm);
		assert(fi->fi_magic == FILEINFO_MAGIC);
		fi->fi_confFlag = 1;
	}
	fclose(f);
}

/* Add linkdata information to fileinfo_t hash.
 */
static void
read_pkg_linkdata(char *pkg, hash_t files)
{
	char linkdata_path[MAXPATHLEN + 1];
	char buf[4096], base64[4096], *path, *norm;
	fileinfo_t fi;	
	FILE *f;

	/* File format is one file per line:
	 *   base64\s+path
	 * Note: we must handle base64 strings with extra line breaks 
	 * after col 77 (bug fixed in dpkg-scripts-1.63).
	 */
	snprintf(linkdata_path, sizeof(linkdata_path), 
		 linkdata_path_tmpl, pkg);
	f = fopen(linkdata_path, "r");
	if (!f)
		return;
	base64[0] = '\0';
	while (fgets(buf, sizeof(buf), f) != NULL) {
		zap_trailing_newline(buf);
		if (strlen(buf) == 0)
			continue;
		if (strlen(buf) == 76 && !strchr(buf, ' ')) {
			strcat(base64, buf);
			continue;
		}
		path = next_tok(buf);
		strcat(base64, buf);
		norm = pathnorm(path);
		if (norm == NULL) {
			fprintf(stderr, "%s: %s: %s: mangled linkdata entry\n",
				prog, pkg, path);
			e.metadata++;
			continue;
		}
		fi = hash_find (files, norm);
		if (fi == NULL) {
			fprintf(stderr, "%s: %s: %s: bogus linkdata2 entry\n",
				prog, pkg, norm);
			base64[0] = '\0';
			e.metadata++;
			free(norm);
			continue;
		}
		free(norm);
		assert(fi->fi_magic == FILEINFO_MAGIC);
		fi->fi_linkdata = xstrdup(base64);
		base64[0] = '\0';
	}
	fclose(f);
}

/* Add the listed package-glob to the 'pkgs' list.
 */
static void
add_pkg_glob(List pkgs, char *glob)
{
	FILE *p;
	char buf[256], cmd[256], *c;
	int n;

	n = snprintf(cmd, sizeof(cmd), list_cmd_tmpl, glob);
	if (n >= sizeof(cmd)) {
		fprintf(stderr, "%s: package glob too long\n", prog);
		exit(1);
	}

	p = popen(cmd, "r");
	if (!p) {
		fprintf(stderr, "%s: popen dpkg-deb: %m\n", prog);
		exit(1);
	}
	while (fgets(buf, sizeof(buf), p) != NULL) {
		c = &buf[strlen(buf) - 1];
		if (*c == '\n')
			*c = '\0';
		if (strlen(buf) > 0) {
			list_append(pkgs, xstrdup(buf));
		}
	}
	if (pclose(p) == -1) {
		fprintf(stderr, "%s: pclose dpkg-deb failed: %m\n", prog);
		exit(1);
	}
}

/* Read the uid/gid of the dpkg-db directory.  All the installed files
 * should have the same uid/gid.  It is not necesssarily root:root 
 * because users may install sandbox /usr/local's as themselves.
 */
static void
get_dpkg_uid(uid_t *up, gid_t *gp)
{
	struct stat sb;

	if (stat(dpkg_db_path, &sb) < 0) {
		fprintf(stderr, "%s: could not stat %s\n", prog, dpkg_db_path);
		exit(1);
	}
	*up = sb.st_uid;
	*gp = sb.st_gid;
}

/* Wrapper for malloc that never returns NULL.
 */
static void *
xmalloc(const size_t size)
{
	void *p = malloc(size);
	if (!p) {
		fprintf(stderr, "%s: out of memory\n", prog);
		exit(1);
	}
	return p;
}

/* Normalizing strdup for paths.
 * Normalization consists of truncating paths to make them relative to 
 * a cwd of /usr/local.
 */
static char *
pathnorm(const char *s)
{
	char *p = NULL;

	if (!strncmp(s, "/usr/local/", 11))
		p = xstrdup(s + 11);
	else if (!strncmp(s, "usr/local/", 10))
		p = xstrdup(s + 10);
	return p;
}

/* De-normalizing strdup for paths.
 * Given a path normalized by pathnorm(), return a fully-qualified path name.
 */
static char *
pathdenorm(const char *s)
{
	char *p = xmalloc(strlen(s) + 11 + 1);

	sprintf(p, "/usr/local/%s", s);

	return p;
}

void
zap_trailing_slashes(char *buf)
{
        char *p = buf + strlen(buf) - 1;

        while (p > buf && *p == '/')
                *p-- = '\0';
}

const char *
skip_leading_slashes(const char *buf)
{
        const char *p = buf;

        while (*p && *p == '/')
                p++;
        return p;
}

static char *
pathcat(const char *p1, const char *p2)
{
	int len = strlen(p1) + strlen(p2) + 2;
	char *new = xmalloc(len);

	strcpy(new, p1);
	zap_trailing_slashes(new);
	strcat(new, "/");
	strcat(new, skip_leading_slashes(p2));

	return new;
}

/* Wrapper for strdup that never returns NULL.
 */
static char *
xstrdup(const char *s)
{
	char *p = strdup(s);
	if (!p) {
		fprintf(stderr, "%s: out of memory\n", prog);
		exit(1);
	}
	return p;
}

/* Generic error handling for use by list.c
 */
void
lsd_fatal_error(char *file, int line, char *mesg)
{
	fprintf(stderr, "%s: %s: fatal error: %m\n", prog, mesg);
	exit(1);
}

/* Memory error handling for use by list.c
 */
void * 
lsd_nomem_error(char *file, int line, char *mesg)
{
	fprintf(stderr, "%s: out of memory\n", prog);
	exit(1);
}
