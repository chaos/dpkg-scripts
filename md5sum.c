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

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <stdio.h>
#include <openssl/evp.h>
#include <string.h>
#include "md5sum.h"

char *
generate_md5sum(char *path)
{
	static char buf[8192];
	static char md_str[EVP_MAX_MD_SIZE*2 + 1];
	unsigned char md_value[EVP_MAX_MD_SIZE];
	EVP_MD_CTX mdctx;
	unsigned int md_len, i, n;
	int fd;

	if ((fd = open(path, O_RDONLY)) < 0)
		return NULL;
        EVP_MD_CTX_init(&mdctx);
        if (EVP_DigestInit_ex(&mdctx, EVP_md5(), NULL) != 1)
		goto err;

	while ((n = read(fd, buf, sizeof(buf))) > 0)
        	if (EVP_DigestUpdate(&mdctx, buf, n) != 1)
			goto err;
	if (n < 0)
		goto err;
        if (EVP_DigestFinal_ex(&mdctx, md_value, &md_len) != 1)
		goto err;
	close(fd);
        EVP_MD_CTX_cleanup(&mdctx);
        for (i = 0; i < md_len; i++)
		sprintf(md_str + i*2, "%02x", md_value[i]);
	return md_str;
err:
	close(fd);
	EVP_MD_CTX_cleanup(&mdctx);
	return NULL;
}

#ifdef STAND
int
main(int argc, char *argv[])
{
	struct stat sb;
	char *str;

	for (; argc > 1; argc--, argv++) {
		if (stat(argv[1], &sb) < 0) {
			fprintf(stderr, "md5sum: %s: %m\n", argv[1]);
			continue;		
		}
		if (!S_ISREG(sb.st_mode)) {
			fprintf(stderr, "md5sum: %s: not a regular file\n", 
				argv[1]);
			continue;
		}
		if ((str = generate_md5sum(argv[1])) == NULL) {
			fprintf(stderr, "md5sum: %s: %m\n", argv[1]);
			continue;
		}
		printf("%s  %s\n", str, argv[1]);
	}
	exit(0);
}
#endif
