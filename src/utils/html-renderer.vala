namespace LLMStudio {

    /* Vala binding to our isolated C cmark wrapper. */
    [CCode (cname = "llm_cmark_to_html", cheader_filename = "utils/cmark-glue.h")]
    extern string llm_cmark_to_html (string markdown);

    public class HtmlRenderer {

        /* Base URI for WebKit load_html() — makes KaTeX JS/CSS/fonts resolvable
           via relative paths from the libjs-katex system package.             */
        public const string BASE_URI = "file:///usr/share/javascript/katex/";

        /* Render a Markdown string to an HTML fragment via libcmark.  */
        public static string render_markdown (string md) {
            if (md == "") return "";
            return llm_cmark_to_html (md);
        }

        /* Escape a string for safe embedding as a JavaScript double-quoted
           string literal.  Also escapes < > to avoid XSS via innerHTML.  */
        public static string js_str (string s) {
            return s
                .replace ("\\",  "\\\\")
                .replace ("\"",  "\\\"")
                .replace ("\n",  "\\n")
                .replace ("\r",  "\\r")
                .replace ("\t",  "\\t")
                .replace ("<",   "\\x3c")
                .replace (">",   "\\x3e");
        }

        /* Escape plain text for safe embedding in HTML markup.  */
        public static string html_esc (string s) {
            return s
                .replace ("&", "&amp;")
                .replace ("<", "&lt;")
                .replace (">", "&gt;")
                .replace ("\"", "&quot;");
        }

        /* Return the complete initial HTML page (empty conversation).  */
        public static string get_page_html () {
            return
                "<!DOCTYPE html>\n" +
                "<html><head><meta charset=\"utf-8\">" +
                "<meta name=\"color-scheme\" content=\"light dark\">\n" +
                "<link rel=\"stylesheet\" href=\"katex.min.css\">\n" +
                "<script src=\"katex.min.js\"></script>\n" +
                "<script src=\"contrib/auto-render.js\"></script>\n" +
                "<style>" + CSS + "</style>\n" +
                "<script>" + JS  + "</script>\n" +
                "</head><body><div id=\"chat\"></div></body></html>";
        }

        /* Build the full HTML page for an entire conversation (used by
           load_session to load all messages at once).                    */
        public static string get_session_html (GLib.List<ChatMessage> messages,
                                               string model_name)
        {
            var sb = new StringBuilder ();
            sb.append (
                "<!DOCTYPE html>\n" +
                "<html><head><meta charset=\"utf-8\">" +
                "<meta name=\"color-scheme\" content=\"light dark\">\n" +
                "<link rel=\"stylesheet\" href=\"katex.min.css\">\n" +
                "<script src=\"katex.min.js\"></script>\n" +
                "<script src=\"contrib/auto-render.js\"></script>\n" +
                "<style>" + CSS + "</style>\n" +
                "<script>" + JS  + "</script>\n" +
                "</head><body><div id=\"chat\">\n");

            int id = 0;
            foreach (var msg in messages) {
                if (msg.role == "user") {
                    sb.append (user_html (id, msg.content, msg.attachments));
                } else if (msg.role == "assistant") {
                    string name = msg.model_name != "" ? msg.model_name : model_name;
                    sb.append (assistant_html (id, msg.content, name, msg.stats_text));
                    id++;
                }
            }

            sb.append ("\n</div><script>llmRenderAll();</script></body></html>");
            return sb.str;
        }

        /* ── Private HTML builders ───────────────────────────────────── */

        private static string user_html (int idx, string text,
                                         GLib.List<ChatAttachment>? attachments = null)
        {
            var sb = new StringBuilder ();
            sb.append ("<div class=\"user-row\" id=\"u-");
            sb.append (idx.to_string ());
            sb.append ("\"><div class=\"user-col\">");

            if (attachments != null) {
                foreach (var att in attachments) {
                    if (att.is_image ()) {
                        sb.append ("<img class=\"att-img\" src=\"");
                        sb.append (html_esc (att.to_data_uri ()));
                        sb.append ("\" alt=\"");
                        sb.append (html_esc (att.filename));
                        sb.append ("\">");
                    } else {
                        sb.append ("<div class=\"att-chip\">&#x1F4C4; ");
                        sb.append (html_esc (att.filename));
                        sb.append ("</div>");
                    }
                }
            }

            if (text != "") {
                sb.append ("<div class=\"user-bubble\" data-raw=\"");
                sb.append (html_esc (text));
                sb.append ("\">");
                sb.append (render_markdown (text));
                sb.append ("</div>");
            }

            sb.append ("<div class=\"user-actions\">");
            sb.append ("<button onclick=\"llmCopyUser(%d)\">Copy</button>".printf (idx));
            sb.append ("<button onclick=\"llmDeleteExchange(%d)\">Delete</button>".printf (idx));
            sb.append ("</div>");

            sb.append ("</div></div>\n");
            return sb.str;
        }

        private static string assistant_html (int id,
                                              string content,
                                              string model_name,
                                              string stats_text = "")
        {
            string think = "";
            string resp  = content;

            if (content.has_prefix ("<think>")) {
                string remaining = content.substring (7);
                while (true) {
                    int end = remaining.index_of ("</think>");
                    if (end < 0) { think += remaining; resp = ""; break; }
                    think    += remaining.substring (0, end);
                    remaining = remaining.substring (end + 8).strip ();
                    if (remaining.has_prefix ("<think>")) {
                        think += "\n\n"; remaining = remaining.substring (7);
                    } else { resp = remaining; break; }
                }
                think = think.strip ();
                resp  = resp.strip ();
            }

            string resp_html = resp  != "" ? render_markdown (resp) : "";
            string raw_resp  = resp;
            string sid       = "m%d".printf (id);

            var sb = new StringBuilder ();
            sb.append ("<div class=\"asst-row\" id=\"row-" + sid + "\">");
            sb.append ("<div class=\"asst-name\">" + html_esc (model_name) + "</div>");

            if (think != "") {
                /* Store raw think text; llmRenderAll() will call renderThinkText() on it. */
                sb.append ("<details class=\"think\"><summary>Thinking\u2026</summary>");
                sb.append ("<div data-think-raw=\"");
                sb.append (html_esc (think));
                sb.append ("\"></div></details>");
            }

            sb.append ("<div class=\"asst-content\" id=\"" + sid + "\" data-raw=\"");
            sb.append (html_esc (raw_resp));
            sb.append ("\">");
            sb.append (resp_html);
            sb.append ("</div>");
            sb.append ("<div class=\"asst-stats\">" + html_esc (stats_text) + "</div>");
            sb.append ("<div class=\"asst-actions\">" +
                       "<button onclick=\"llmCopy('" + sid + "')\">Copy</button>" +
                       "<button onclick=\"llmDeleteExchange(%d)\">Delete</button>".printf (id) +
                       "</div>");
            sb.append ("</div>\n");
            return sb.str;
        }

        /* ── CSS ─────────────────────────────────────────────────────── */

        private const string CSS = """
*{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#ffffff;--fg:#2d2d2d;--user-bg:#1c71d8;--user-fg:#ffffff;
  --code-bg:rgba(0,0,0,.06);--border:rgba(0,0,0,.12);
  --think-bg:rgba(0,0,0,.03);--dim:#767676;
}
@media(prefers-color-scheme:dark){:root{
  --bg:#242424;--fg:#deddda;--user-bg:#1c71d8;--user-fg:#ffffff;
  --code-bg:rgba(255,255,255,.08);--border:rgba(255,255,255,.12);
  --think-bg:rgba(255,255,255,.04);--dim:#9a9996;
}}
html,body{background:var(--bg);color:var(--fg);
  font-family:-apple-system,system-ui,Cantarell,sans-serif;
  font-size:14px;line-height:1.6;word-wrap:break-word;overflow-wrap:break-word;
  -webkit-user-select:text;user-select:text}
.katex-error{color:inherit !important}
body{padding:0}
#chat{width:100%;max-width:1080px;margin:0 auto;padding:0 16px 24px;box-sizing:border-box}
.user-row{display:flex;justify-content:flex-end;margin:8px 0 4px 80px}
.user-col{display:flex;flex-direction:column;align-items:flex-end;gap:4px;max-width:100%}
.user-bubble{background:var(--user-bg);color:var(--user-fg);
  border-radius:18px 18px 4px 18px;padding:10px 14px;
  white-space:pre-wrap;word-break:break-word;max-width:100%}
.user-bubble p{margin:.4em 0;white-space:normal}
.user-bubble p:first-child{margin-top:0}.user-bubble p:last-child{margin-bottom:0}
.user-bubble ul,.user-bubble ol{padding-left:1.4em;margin:.3em 0;white-space:normal}
.user-bubble li{margin:.1em 0}
.user-bubble code{font-family:"JetBrains Mono","Fira Code","Cascadia Code",monospace;
  font-size:.88em;background:rgba(255,255,255,.2);padding:1px 5px;border-radius:4px}
.user-bubble pre{background:rgba(0,0,0,.25);border-radius:8px;padding:10px 12px;
  overflow-x:auto;margin:.5em 0;white-space:normal}
.user-bubble pre code{background:none;padding:0;font-size:.86em;white-space:pre}
.user-bubble blockquote{border-left:3px solid rgba(255,255,255,.5);
  margin:.5em 0;padding-left:10px;opacity:.85}
.user-bubble a{color:rgba(255,255,255,.9)}
.att-img{max-width:320px;max-height:220px;border-radius:12px;object-fit:contain;display:block}
.att-chip{background:rgba(28,113,216,.15);color:var(--fg);border-radius:10px;
  padding:4px 10px;font-size:12px}
.asst-row{margin:16px 0 8px}
.asst-name{font-size:11px;color:var(--dim);font-weight:500;margin-bottom:6px}
details.tool-call{background:var(--think-bg);border:1px solid var(--border);
  border-radius:8px;padding:2px 10px;margin-bottom:8px;font-size:12px;color:var(--dim)}
details.tool-call summary{cursor:pointer;padding:4px 0}
details.tool-call pre{font-size:11px;max-height:160px;overflow-y:auto;
  white-space:pre-wrap;word-break:break-word;margin-top:4px}
details.think{background:var(--think-bg);border:1px solid var(--border);
  border-radius:8px;padding:2px 10px;margin-bottom:10px;
  font-size:13px;color:var(--dim)}
details.think .katex,.details.think .katex-display{color:var(--fg)}
details.think summary{cursor:pointer;padding:4px 0;font-style:italic}
details.think[open] summary{margin-bottom:4px}
.asst-content h1,.asst-content h2,.asst-content h3,
.asst-content h4,.asst-content h5,.asst-content h6
  {margin:.9em 0 .3em;line-height:1.3}
.asst-content h1{font-size:1.5em}.asst-content h2{font-size:1.3em}
.asst-content h3{font-size:1.15em}
.asst-content p{margin:.5em 0}
.asst-content p:first-child{margin-top:0}.asst-content p:last-child{margin-bottom:0}
.asst-content ul,.asst-content ol{padding-left:1.6em;margin:.4em 0}
.asst-content li{margin:.15em 0}
.asst-content code{font-family:"JetBrains Mono","Fira Code","Cascadia Code",monospace;
  font-size:.88em;background:var(--code-bg);padding:1px 5px;border-radius:4px}
.asst-content pre{background:var(--code-bg);border-radius:8px;
  padding:12px 14px;overflow-x:auto;margin:.6em 0}
.asst-content pre code{background:none;padding:0;font-size:.86em;line-height:1.5}
.asst-content blockquote{border-left:3px solid var(--dim);margin:.6em 0;
  padding-left:12px;color:var(--dim)}
.asst-content hr{border:none;border-top:1px solid var(--border);margin:.8em 0}
.asst-content table{border-collapse:collapse;width:100%;margin:.6em 0;font-size:.93em}
.asst-content th,.asst-content td{border:1px solid var(--border);padding:5px 10px;text-align:left}
.asst-content th{background:var(--code-bg);font-weight:600}
.asst-content a{color:var(--user-bg)}
.katex-display{overflow-x:auto;overflow-y:hidden;margin:.7em 0}
.asst-stats{font-size:11px;color:var(--dim);margin-top:6px}
.asst-actions{margin-top:6px;display:flex;gap:4px}
.asst-actions button{background:none;border:1px solid var(--border);
  border-radius:6px;padding:2px 8px;font-size:11px;cursor:pointer;color:var(--fg)}
.asst-actions button:hover{background:var(--code-bg)}
.user-actions{display:flex;gap:4px;justify-content:flex-end;margin-top:4px}
.user-actions button{background:none;border:1px solid rgba(255,255,255,.35);
  border-radius:6px;padding:2px 8px;font-size:11px;cursor:pointer;color:rgba(255,255,255,.85)}
.user-actions button:hover{background:rgba(255,255,255,.15)}
@keyframes pulse{0%,100%{opacity:.3}50%{opacity:1}}
.dot{display:inline-block;width:6px;height:6px;border-radius:50%;
  background:var(--dim);animation:pulse 1.2s ease-in-out infinite;margin:2px}
""";

        /* ── JavaScript ──────────────────────────────────────────────── */

        private const string JS = """
var KATEX_OPTS={
  delimiters:[
    {left:"$$",right:"$$",display:true},
    {left:"\\[",right:"\\]",display:true},
    {left:"$",right:"$",display:false},
    {left:"\\(",right:"\\)",display:false}
  ],
  throwOnError:false,output:"html"
};
function katexEl(el){
  if(typeof renderMathInElement!=='undefined'){
    try{renderMathInElement(el,KATEX_OPTS);}catch(e){console.error(e);}
  }
}
/* Normalise non-standard math delimiters to ones KaTeX understands.
   Protects code blocks and already-valid math delimiters first, then:
     ( \...  )  →  \( \... \)   inline
     [ \...  ]  →  \[ \... \]   display                              */
function normalizeMathDelimiters(html){
  var saved=[];
  function save(m){saved.push(m);return'\x01'+(saved.length-1)+'\x01';}
  // Protect code blocks
  html=html.replace(/<(pre|code)[\s\S]*?<\/\1>/gi,save);
  // Protect existing valid math delimiters ($...$, $$...$$, \(...\), \[...\])
  html=html.replace(/\$\$[\s\S]*?\$\$|\$[^$\n]+?\$/g,save);
  html=html.replace(/\\\([\s\S]*?\\\)|\\\[[\s\S]*?\\\]/g,save);
  // Convert ( ... ) → \( ... \) and [ ... ] → \[ ... \] when content contains a backslash
  html=html.replace(/\(\s*([^()]*\\[^()]*)\s*\)/g,'\\($1\\)');
  html=html.replace(/\[\s*([^\[\]]*\\[^\[\]]*)\s*\]/g,'\\[$1\\]');
  return html.replace(/\x01(\d+)\x01/g,function(_,i){return saved[+i];});
}
function llmRenderAll(){
  /* Render think-block placeholders from session-loaded messages. */
  document.querySelectorAll('[data-think-raw]').forEach(function(el){
    el.innerHTML=renderThinkText(el.dataset.thinkRaw);
    el.removeAttribute('data-think-raw');
  });
  /* Normalise non-standard delimiters before KaTeX pass. */
  document.querySelectorAll('.asst-content,.user-bubble').forEach(function(el){
    el.innerHTML=normalizeMathDelimiters(el.innerHTML);
  });
  katexEl(document.body);
}
function scrollBottom(){window.scrollTo(0,document.body.scrollHeight);}
function escHtml(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function llmClear(){document.getElementById('chat').innerHTML='';}
function llmAddToolCall(id,display,result){
  var row=document.getElementById('row-'+id);
  if(!row)return;
  var tc=document.createElement('details');
  tc.className='tool-call';
  tc.innerHTML='<summary>'+escHtml(display)+'</summary><pre>'+escHtml(result)+'</pre>';
  var container=row.querySelector('.tool-calls');
  if(container)container.appendChild(tc);
  scrollBottom();
}
function llmCopy(id){
  var el=document.getElementById(id);
  if(el){navigator.clipboard.writeText(el.dataset.raw||el.textContent).catch(function(){});}
}
function llmCopyUser(idx){
  var row=document.getElementById('u-'+idx);
  if(!row)return;
  var bubble=row.querySelector('.user-bubble');
  navigator.clipboard.writeText(bubble?bubble.dataset.raw||bubble.textContent:row.textContent).catch(function(){});
}
function llmDeleteExchange(idx){
  var ur=document.getElementById('u-'+idx);
  var ar=document.getElementById('row-m'+idx);
  if(ur)ur.remove();
  if(ar)ar.remove();
  if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.llm)
    window.webkit.messageHandlers.llm.postMessage(JSON.stringify({action:'delete',index:idx}));
}
function llmAddUser(idx,text,attsJson){
  var d=document.createElement('div');
  d.className='user-row';
  d.id='u-'+idx;
  var col=document.createElement('div');
  col.className='user-col';
  if(attsJson){try{
    var atts=JSON.parse(attsJson);
    for(var i=0;i<atts.length;i++){
      var a=atts[i];
      if(a.type==='image'){
        var img=document.createElement('img');
        img.className='att-img';img.src=a.src;img.alt=escHtml(a.filename);
        col.appendChild(img);
      }else{
        var chip=document.createElement('div');
        chip.className='att-chip';
        chip.textContent='\uD83D\uDCC4 '+a.filename;
        col.appendChild(chip);
      }
    }
  }catch(e){}}
  if(text){
    var b=document.createElement('div');
    b.className='user-bubble';b.dataset.raw=b.dataset.raw||'';
    b.innerHTML=normalizeMathDelimiters(text);
    katexEl(b);
    col.appendChild(b);
  }
  var acts=document.createElement('div');
  acts.className='user-actions';
  acts.innerHTML='<button onclick="llmCopyUser('+idx+')">Copy</button>'+
                 '<button onclick="llmDeleteExchange('+idx+')">Delete</button>';
  col.appendChild(acts);
  d.appendChild(col);
  document.getElementById('chat').appendChild(d);
  scrollBottom();
}
function llmStartAssistant(id,model){
  var d=document.createElement('div');
  d.className='asst-row';
  d.id='row-'+id;
  d.innerHTML=
    '<div class="asst-name">'+escHtml(model)+'</div>'+
    '<div class="tool-calls"></div>'+
    '<div class="asst-content">'+
      '<div class="resp"><span class="dot"></span></div>'+
    '</div>'+
    '<div class="asst-stats"></div>'+
    '<div class="asst-actions" style="display:none"></div>';
  document.getElementById('chat').appendChild(d);
  scrollBottom();
}
function wrapInlineMath(s){
  /* Detect common LaTeX/math patterns that lack $...$ delimiters and wrap them.
     Works in two protected passes so inner \commands aren't double-wrapped. */
  var sv=[];
  function save(m){sv.push(m);return'\x01'+(sv.length-1)+'\x01';}
  // Pass 0: protect already-delimited math
  s=s.replace(/\$\$[\s\S]*?\$\$|\$[^$\n]+?\$|\\\[[\s\S]*?\\\]|\\\([^)]*?\\\)/g,save);
  // Pass 1: subscript/superscript expressions — G_{\mu\nu}, x^2, T_μν, e^{i\pi}
  s=s.replace(/([A-Za-z\u0370-\u03FF\d]+)([_^])(\{[^{}]+\}|[A-Za-z\u0370-\u03FF\d\\]+)/g,
    function(m){return save('$'+m+'$');});
  // Pass 2: standalone backslash commands — \alpha, \frac{a}{b}, \mu
  s=s.replace(/(\\[A-Za-z]+(?:\{[^{}]*\})*)/g,
    function(m){return save('$'+m+'$');});
  return s.replace(/\x01(\d+)\x01/g,function(_,i){return sv[+i];});
}
function renderThinkText(raw){
  /* Render think content as markdown-like HTML (with KaTeX support) */
  if(!raw)return'';
  var s=wrapInlineMath(raw);
  s=s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  return s.split(/\n{2,}/).map(function(p){
    var t=p.trim();return t?'<p>'+t.replace(/\n/g,'<br>')+'</p>':'';
  }).join('');
}
function llmSetThink(id,raw){
  var row=document.getElementById('row-'+id);
  if(!row)return;
  var el=row.querySelector('.asst-content');
  if(!el)return;
  var det=el.querySelector('details.think');
  if(!det){
    det=document.createElement('details');
    det.className='think';
    det.open=true;
    det.innerHTML='<summary>Thinking\u2026</summary><div class="tk"></div>';
    el.insertBefore(det,el.firstChild);
  }
  var tk=det.querySelector('.tk');
  if(tk){tk.innerHTML=renderThinkText(raw);katexEl(tk);}
  scrollBottom();
}
function llmSetContent(id,html){
  var row=document.getElementById('row-'+id);
  if(!row)return;
  var resp=row.querySelector('.resp');
  if(!resp)return;
  resp.innerHTML=html;
  scrollBottom();
}
function llmFinalize(id,thinkRaw,contentHtml,rawContent){
  var row=document.getElementById('row-'+id);
  if(!row)return;
  var el=row.querySelector('.asst-content');
  if(!el)return;
  /* Update think block in-place (reuse streaming element, don't rebuild). */
  var det=el.querySelector('details.think');
  if(thinkRaw){
    if(!det){
      det=document.createElement('details');
      det.className='think';
      det.innerHTML='<summary>Thinking\u2026</summary><div class="tk"></div>';
      el.insertBefore(det,el.firstChild);
    }
    det.open=false;
    var tk=det.querySelector('.tk');
    if(!tk){tk=document.createElement('div');tk.className='tk';det.appendChild(tk);}
    tk.innerHTML=renderThinkText(thinkRaw);
  } else if(det){
    el.removeChild(det);
  }
  /* Update response div in-place. */
  var resp=row.querySelector('.resp');
  if(!resp){resp=document.createElement('div');resp.className='resp';el.appendChild(resp);}
  resp.innerHTML=normalizeMathDelimiters(contentHtml);
  row.dataset.raw=rawContent;
  katexEl(el);
  var act=row.querySelector('.asst-actions');
  if(act){
    act.style.display='';
    var exIdx=parseInt(id.slice(1));
    act.innerHTML='<button onclick="llmCopyRow(\''+id+'\')">Copy</button>'+
                  '<button onclick="llmDeleteExchange('+exIdx+')">Delete</button>';
  }
  scrollBottom();
}
function llmSetStats(id,text){
  var row=document.getElementById('row-'+id);
  if(row){var el=row.querySelector('.asst-stats');if(el)el.textContent=text;}
}
function llmCopyRow(id){
  var row=document.getElementById('row-'+id);
  if(row){navigator.clipboard.writeText(row.dataset.raw||row.textContent).catch(function(){});}
}
function llmCopyChat(){
  var chat=document.getElementById('chat');
  if(!chat)return false;
  navigator.clipboard.writeText(chat.outerHTML).catch(function(){});
  return true;
}
""";

    }  // class HtmlRenderer
}  // namespace LLMStudio
