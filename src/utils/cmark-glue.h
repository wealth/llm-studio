#pragma once
#include <glib.h>

/* Convert CommonMark markdown to an HTML fragment string.
   The returned string is g_malloc'd; the caller must g_free it.  */
char *llm_cmark_to_html (const char *markdown);
