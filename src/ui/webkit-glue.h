#pragma once
#include <gtk/gtk.h>

/* Creates a WebKitWebView (GTK4) with JS and file-access enabled.
   Returns a GtkWidget* owned by the caller.  */
GtkWidget* llm_webkit_new_webview (void);

/* Load HTML content with the given base URI (may be NULL).
   Queues any pending llm_webkit_run_js() calls until load finishes. */
void llm_webkit_load_html (GtkWidget *wv, const char *html, const char *base_uri);

/* Execute a JavaScript snippet. If the page is still loading the script is
   queued and executed after WEBKIT_LOAD_FINISHED. */
void llm_webkit_run_js (GtkWidget *wv, const char *js);

/* Callback type for JS → native messages. */
typedef void (*LlmJsCallback)(const char *json, gpointer user_data);

/* Register a WebKit script-message handler named @name.  When JS calls
   window.webkit.messageHandlers.<name>.postMessage(value) the string
   representation of @value is passed to @cb.                           */
void llm_webkit_add_message_handler (GtkWidget     *wv,
                                     const char    *name,
                                     LlmJsCallback  cb,
                                     gpointer       user_data);

/* Inject @source as a UserScript that runs at document-start in all
   frames.  Call this once after llm_webkit_new_webview() to install
   persistent scripts (e.g. chat.js) that survive page reloads.       */
void llm_webkit_add_user_script (GtkWidget *wv, const char *source);
