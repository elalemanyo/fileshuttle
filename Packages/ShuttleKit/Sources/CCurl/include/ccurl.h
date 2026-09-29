#ifndef CCURL_H
#define CCURL_H

#include <stddef.h>
#include <stdint.h>

/// Thin, non-variadic wrapper around the system libcurl so Swift can drive FTP/FTPS.

typedef struct {
    const char *url;          // ftp://host:port/path/ (directory URLs end with '/')
    const char *username;
    const char *password;
    int require_tls;          // 1 = explicit FTPS (AUTH TLS), fail if unsupported
    long connect_timeout;     // seconds
} ccurl_options;

/// Return non-zero to abort the transfer.
typedef int (*ccurl_progress_fn)(void *ctx, int64_t sent, int64_t total);

/// Uploads `local_path` to `options->url`, creating missing remote directories.
/// Returns 0 on success, otherwise a CURLcode with a message in `errbuf`.
int ccurl_upload(const ccurl_options *options,
                 const char *local_path,
                 ccurl_progress_fn progress,
                 void *ctx,
                 char *errbuf,
                 size_t errbuf_len);

/// Logs in, changes into `options->url` and optionally sends one raw FTP command
/// (e.g. "DELE file"). Pass NULL to only verify the connection.
int ccurl_command(const ccurl_options *options,
                  const char *command,
                  char *errbuf,
                  size_t errbuf_len);

#endif
