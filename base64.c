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
#include <string.h>
#include <openssl/sha.h>
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>
#include "base64.h"

char *
encode_base64(char *s)
{
	BIO *bmem, *b64;
	BUF_MEM *bptr;
	char *res = NULL;
	int len = strlen(s);

	if (!(b64 = BIO_new(BIO_f_base64())))
		goto done;
	BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
	if (!(bmem = BIO_new(BIO_s_mem())))
		goto done;
	b64 = BIO_push(b64, bmem);
	if (BIO_write(b64, s, len) != len)
		goto done;
	if (BIO_flush(b64) != 1)
		goto done;
	BIO_get_mem_ptr(b64, &bptr);
	if (!(res = malloc(bptr->length + 1)))
		goto done;
	memcpy(res, bptr->data, bptr->length);
	res[bptr->length] = '\0';
done:
	if (b64)
		BIO_free_all(b64);
	return res;
}


#ifdef STAND
/* like base64 -w0 */
int
main(int argc, char *argv[])
{
	char buf[1024];
	char *base64;
	int n;

	if (argc != 1) {
		fprintf(stderr, "Usage: base64\n");
		exit(1);
	}
	while ((n = read(0, buf, sizeof(buf) - 1)) > 0) {
		buf[n] = '\0';
		if (!(base64 = encode_base64(buf))) {
			fprintf(stderr, "base64: %m\n");
			exit(1);
		}
		printf("%s", base64);
		free(base64);
	}
	exit(0);
}
#endif
