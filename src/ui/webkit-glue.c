/* webkit-glue.c — isolated WebKit wrapper (no libsoup-2.4 headers here).
   This file is compiled as a separate static library so that webkitgtk-6.0
   include paths (which pull in libsoup-3.0) never mix with the rest of the
   project that uses libsoup-2.4.                                           */

#include "webkit-glue.h"
#include <webkitgtk-6.0/webkit/webkit.h>
#include <string.h>

/* Per-webview state: pending scripts queued while the page is loading. */
typedef struct {
    GPtrArray *queue;   /* char* entries, owned */
    gboolean   loading;
} WVState;

static GHashTable *wv_states = NULL;  /* WebKitWebView* → WVState* */

static void wv_state_free (gpointer p) {
    WVState *s = p;
    g_ptr_array_unref (s->queue);
    g_free (s);
}

static void on_load_changed (WebKitWebView  *wv,
                              WebKitLoadEvent ev,
                              gpointer        ud)
{
    (void) ud;
    if (ev != WEBKIT_LOAD_FINISHED) return;

    WVState *s = g_hash_table_lookup (wv_states, wv);
    if (!s) return;

    s->loading = FALSE;
    for (guint i = 0; i < s->queue->len; i++) {
        const char *js = g_ptr_array_index (s->queue, i);
        webkit_web_view_evaluate_javascript (wv, js, -1, NULL, NULL,
                                             NULL, NULL, NULL);
    }
    g_ptr_array_set_size (s->queue, 0);
}

GtkWidget *llm_webkit_new_webview (void)
{
    if (!wv_states)
        wv_states = g_hash_table_new_full (NULL, NULL, NULL, wv_state_free);

    WebKitWebView *wv = WEBKIT_WEB_VIEW (webkit_web_view_new ());

    /* Eliminate the white flash on load: make the view transparent so the
       parent GTK widget background (matching the app theme) shows through
       before the page CSS has been applied.                               */
    GdkRGBA transparent = {0.0, 0.0, 0.0, 0.0};
    webkit_web_view_set_background_color (wv, &transparent);

    WebKitSettings *settings = webkit_web_view_get_settings (wv);
    webkit_settings_set_enable_javascript                      (settings, TRUE);
    webkit_settings_set_allow_file_access_from_file_urls       (settings, TRUE);
    webkit_settings_set_allow_universal_access_from_file_urls  (settings, TRUE);

    WVState *s    = g_new0 (WVState, 1);
    s->queue      = g_ptr_array_new_with_free_func (g_free);
    s->loading    = FALSE;
    g_hash_table_insert (wv_states, wv, s);

    g_signal_connect (wv, "load-changed", G_CALLBACK (on_load_changed), NULL);

    return GTK_WIDGET (wv);
}

void llm_webkit_load_html (GtkWidget *gw, const char *html, const char *base_uri)
{
    WebKitWebView *wv = WEBKIT_WEB_VIEW (gw);
    WVState       *s  = g_hash_table_lookup (wv_states, wv);
    if (s) {
        s->loading = TRUE;
        g_ptr_array_set_size (s->queue, 0);   /* clear stale pending scripts */
    }
    webkit_web_view_load_html (wv, html, base_uri);
}

typedef struct {
    LlmJsCallback cb;
    gpointer      user_data;
} MsgHandlerData;

static void on_msg_received (WebKitUserContentManager *ucm,
                              JSCValue                 *value,
                              gpointer                  ud)
{
    (void) ucm;
    MsgHandlerData *d = ud;
    char *str = jsc_value_to_string (value);
    if (str && d->cb)
        d->cb (str, d->user_data);
    g_free (str);
}

void llm_webkit_add_message_handler (GtkWidget     *gw,
                                     const char    *name,
                                     LlmJsCallback  cb,
                                     gpointer       user_data)
{
    WebKitWebView            *wv  = WEBKIT_WEB_VIEW (gw);
    WebKitUserContentManager *ucm = webkit_web_view_get_user_content_manager (wv);

    MsgHandlerData *d = g_new (MsgHandlerData, 1);
    d->cb        = cb;
    d->user_data = user_data;

    /* Connect BEFORE registering to avoid race conditions. */
    char *signal = g_strdup_printf ("script-message-received::%s", name);
    g_signal_connect_data (ucm, signal, G_CALLBACK (on_msg_received),
                           d, (GClosureNotify) g_free, 0);
    g_free (signal);

    webkit_user_content_manager_register_script_message_handler (ucm, name, NULL);
}

void llm_webkit_add_user_script (GtkWidget *gw, const char *source)
{
    WebKitWebView            *wv  = WEBKIT_WEB_VIEW (gw);
    WebKitUserContentManager *ucm = webkit_web_view_get_user_content_manager (wv);
    WebKitUserScript *script = webkit_user_script_new (
        source,
        WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
        NULL, NULL);
    webkit_user_content_manager_add_script (ucm, script);
    webkit_user_script_unref (script);
}

void llm_webkit_run_js (GtkWidget *gw, const char *js)
{
    WebKitWebView *wv = WEBKIT_WEB_VIEW (gw);
    WVState       *s  = g_hash_table_lookup (wv_states, wv);
    if (s && s->loading) {
        g_ptr_array_add (s->queue, g_strdup (js));
        return;
    }
    webkit_web_view_evaluate_javascript (wv, js, -1, NULL, NULL,
                                         NULL, NULL, NULL);
}
