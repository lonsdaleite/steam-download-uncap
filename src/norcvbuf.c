/*
 * norcvbuf.so - swallow SO_RCVBUF and SO_SNDBUF so the kernel keeps
 * autotuning the socket buffers.
 *
 * The Steam client pins SO_RCVBUF to 128 KiB on its content-download sockets.
 * An explicit SO_RCVBUF turns off Linux receive-buffer autotuning and freezes
 * the advertised receive window, which caps throughput at window/RTT no matter
 * how much bandwidth the link has. On the sending side of a LAN transfer the
 * client pins SO_SNDBUF to the kernel minimum, which starves the socket in the
 * same way. Reporting success without forwarding the call leaves the buffers
 * under kernel control.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/socket.h>

static int (*real_setsockopt)(int, int, int, const void *, socklen_t);

int setsockopt(int fd, int level, int optname,
               const void *optval, socklen_t optlen)
{
	if (!real_setsockopt)
		real_setsockopt = dlsym(RTLD_NEXT, "setsockopt");

	if (level == SOL_SOCKET &&
	    (optname == SO_RCVBUF || optname == SO_RCVBUFFORCE ||
	     optname == SO_SNDBUF || optname == SO_SNDBUFFORCE))
		return 0; /* report success, leave the buffer to the kernel */

	return real_setsockopt(fd, level, optname, optval, optlen);
}
