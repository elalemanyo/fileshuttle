#include "ccurl.h"

#include <curl/curl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static pthread_once_t global_init_once = PTHREAD_ONCE_INIT;

static void global_init(void) {
    curl_global_init(CURL_GLOBAL_DEFAULT);
}

typedef struct {
    ccurl_progress_fn fn;
    void *ctx;
} progress_state;

static int xferinfo(void *p, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow) {
    (void)dltotal;
    (void)dlnow;
    progress_state *state = p;
    return state->fn ? state->fn(state->ctx, (int64_t)ulnow, (int64_t)ultotal) : 0;
}

static CURL *make_handle(const ccurl_options *o, char *errbuf) {
    pthread_once(&global_init_once, global_init);

    CURL *curl = curl_easy_init();
    if (!curl) return NULL;

    errbuf[0] = '\0';
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errbuf);
    curl_easy_setopt(curl, CURLOPT_URL, o->url);
    curl_easy_setopt(curl, CURLOPT_USERNAME, o->username);
    curl_easy_setopt(curl, CURLOPT_PASSWORD, o->password);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, o->connect_timeout > 0 ? o->connect_timeout : 20L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_USE_SSL, o->require_tls ? (long)CURLUSESSL_ALL : (long)CURLUSESSL_NONE);
    // Abort stalled transfers: less than 1 byte/s for 60s.
    curl_easy_setopt(curl, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(curl, CURLOPT_LOW_SPEED_TIME, 60L);
    return curl;
}

static int finish(CURL *curl, CURLcode rc, char *errbuf, size_t errbuf_len) {
    if (rc != CURLE_OK && errbuf[0] == '\0') {
        snprintf(errbuf, errbuf_len, "%s", curl_easy_strerror(rc));
    }
    curl_easy_cleanup(curl);
    return (int)rc;
}

int ccurl_upload(const ccurl_options *o,
                 const char *local_path,
                 ccurl_progress_fn progress,
                 void *ctx,
                 char *out_err,
                 size_t out_err_len) {
    char errbuf[CURL_ERROR_SIZE];

    FILE *file = fopen(local_path, "rb");
    if (!file) {
        snprintf(out_err, out_err_len, "Could not open %s", local_path);
        return -1;
    }
    struct stat st;
    fstat(fileno(file), &st);

    CURL *curl = make_handle(o, errbuf);
    if (!curl) {
        fclose(file);
        snprintf(out_err, out_err_len, "Could not initialise libcurl");
        return -1;
    }

    progress_state state = { progress, ctx };
    curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);
    curl_easy_setopt(curl, CURLOPT_READDATA, file);
    curl_easy_setopt(curl, CURLOPT_INFILESIZE_LARGE, (curl_off_t)st.st_size);
    curl_easy_setopt(curl, CURLOPT_FTP_CREATE_MISSING_DIRS, (long)CURLFTP_CREATE_DIR_RETRY);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, xferinfo);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &state);

    CURLcode rc = curl_easy_perform(curl);
    fclose(file);
    int result = finish(curl, rc, errbuf, sizeof errbuf);
    snprintf(out_err, out_err_len, "%s", errbuf);
    return result;
}

int ccurl_command(const ccurl_options *o, const char *command, char *out_err, size_t out_err_len) {
    char errbuf[CURL_ERROR_SIZE];
    CURL *curl = make_handle(o, errbuf);
    if (!curl) {
        snprintf(out_err, out_err_len, "Could not initialise libcurl");
        return -1;
    }

    struct curl_slist *commands = NULL;
    curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
    if (command) {
        commands = curl_slist_append(commands, command);
        curl_easy_setopt(curl, CURLOPT_POSTQUOTE, commands);
    }

    CURLcode rc = curl_easy_perform(curl);
    curl_slist_free_all(commands);
    int result = finish(curl, rc, errbuf, sizeof errbuf);
    snprintf(out_err, out_err_len, "%s", errbuf);
    return result;
}
