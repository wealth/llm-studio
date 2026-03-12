/* cmark-glue.c — thin wrapper around libcmark-gfm with GFM extensions.
   Compiled in the isolated static library (no libsoup headers).  */

#include "cmark-glue.h"
#include <cmark-gfm.h>
#include <cmark-gfm-core-extensions.h>
#include <string.h>
#include <stdlib.h>

char *llm_cmark_to_html (const char *markdown)
{
    if (!markdown || !*markdown)
        return g_strdup ("");

    /* Register GFM extensions (idempotent). */
    cmark_gfm_core_extensions_ensure_registered ();

    int opts = CMARK_OPT_DEFAULT | CMARK_OPT_UNSAFE;

    cmark_parser *parser = cmark_parser_new (opts);

    /* Attach the extensions we want. */
    const char *ext_names[] = { "table", "strikethrough", "autolink", "tasklist" };
    for (int i = 0; i < 4; i++) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension (ext_names[i]);
        if (ext)
            cmark_parser_attach_syntax_extension (parser, ext);
    }

    cmark_parser_feed (parser, markdown, strlen (markdown));
    cmark_node *doc = cmark_parser_finish (parser);
    cmark_parser_free (parser);

    char *raw    = cmark_render_html (doc, opts, NULL);
    cmark_node_free (doc);

    char *result = g_strdup (raw);
    free (raw);
    return result;
}
