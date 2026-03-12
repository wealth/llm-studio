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
