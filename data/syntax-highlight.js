/* Minimal syntax highlighter for code blocks.
   Operates on <pre><code class="language-*"> elements produced by cmark-gfm.
   Covers: Python, JavaScript/TypeScript, C/C++/Vala, Bash/Shell, Rust, Go,
           Java, JSON, HTML/XML, CSS, SQL, Ruby, YAML, Diff, Markdown.      */

var _HL_LANGS={};

/* ── Token types → CSS classes ─────────────────────────────────────────── */
/* kw=keyword, str=string, cm=comment, num=number, fn=function,
   op=operator, bi=builtin, dc=decorator, re=regex                        */

/* Helper: build a rule list from compact definitions. */
function _hlRules(defs){
  var rules=[];
  for(var i=0;i<defs.length;i+=2){
    rules.push({re:defs[i],cls:defs[i+1]});
  }
  return rules;
}

/* ── Python ────────────────────────────────────────────────────────────── */
_HL_LANGS['python']=_HL_LANGS['py']=_hlRules([
  /("""[\s\S]*?"""|'''[\s\S]*?''')/g, 'str',
  /(#.*$)/gm, 'cm',
  /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g, 'str',
  /\b(and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)\b/g, 'kw',
  /\b(True|False|None|self|cls)\b/g, 'bi',
  /\b(print|len|range|int|str|float|list|dict|set|tuple|type|isinstance|enumerate|zip|map|filter|sorted|reversed|open|super|property|staticmethod|classmethod|abs|all|any|bin|bool|bytes|chr|complex|dir|divmod|eval|exec|format|getattr|globals|hasattr|hash|hex|id|input|iter|locals|max|min|next|object|oct|ord|pow|repr|round|slice|sum|vars)\b(?=\s*\()/g, 'bi',
  /(@\w+)/g, 'dc',
  /\b(\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?[jJ]?|0[xX][\da-fA-F_]+|0[oO][0-7_]+|0[bB][01_]+)\b/g, 'num',
  /([+\-*/%=<>!&|^~]+|\.\.\.)/g, 'op',
  /\b([A-Za-z_]\w*)\s*(?=\()/g, 'fn'
]);

/* ── JavaScript / TypeScript ───────────────────────────────────────────── */
_HL_LANGS['javascript']=_HL_LANGS['js']=_HL_LANGS['typescript']=_HL_LANGS['ts']=_hlRules([
  /(\/\/.*$)/gm, 'cm',
  /(\/\*[\s\S]*?\*\/)/g, 'cm',
  /(`(?:\\.|[^`\\])*`)/g, 'str',
  /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g, 'str',
  /\b(async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|from|function|if|import|in|instanceof|let|new|of|return|static|super|switch|this|throw|try|typeof|var|void|while|with|yield)\b/g, 'kw',
  /\b(true|false|null|undefined|NaN|Infinity)\b/g, 'bi',
  /\b(console|document|window|Array|Object|String|Number|Boolean|Map|Set|Promise|RegExp|JSON|Math|Date|Error|Symbol|BigInt|parseInt|parseFloat|setTimeout|setInterval|fetch|require)\b/g, 'bi',
  /\b(\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?n?|0[xX][\da-fA-F_]+n?|0[oO][0-7_]+n?|0[bB][01_]+n?)\b/g, 'num',
  /(=>|[+\-*/%=<>!&|^~?:]+|\.\.\.)/g, 'op',
  /\b([A-Za-z_$]\w*)\s*(?=\()/g, 'fn'
]);

/* ── C / C++ / Vala ────────────────────────────────────────────────────── */
_HL_LANGS['c']=_HL_LANGS['cpp']=_HL_LANGS['vala']=_HL_LANGS['cxx']=_hlRules([
  /(\/\/.*$)/gm, 'cm',
  /(\/\*[\s\S]*?\*\/)/g, 'cm',
  /(#\s*\w+.*$)/gm, 'dc',
  /("(?:\\.|[^"\\])*")/g, 'str',
  /('(?:\\.|[^'\\])')/g, 'str',
  /\b(auto|break|case|catch|class|const|constexpr|continue|default|delete|do|else|enum|explicit|extern|final|for|friend|goto|if|inline|mutable|namespace|new|noexcept|nullptr|operator|override|private|protected|public|register|return|sizeof|static|static_cast|struct|switch|template|this|throw|try|typedef|typeid|typename|union|using|virtual|void|volatile|while|yield|async|signal|owned|unowned|weak|abstract|construct|var|get|set|out|ref)\b/g, 'kw',
  /\b(int|long|short|float|double|char|unsigned|signed|bool|int8|int16|int32|int64|uint8|uint16|uint32|uint64|size_t|ssize_t|string|true|false|null|NULL)\b/g, 'bi',
  /\b(\d[\d']*(?:\.[\d']+)?(?:[eE][+-]?\d+)?[fFlLuU]*|0[xX][\da-fA-F']+[uUlL]*|0[bB][01']+[uUlL]*)\b/g, 'num',
  /([+\-*/%=<>!&|^~?:]+|->|::)/g, 'op',
  /\b([A-Za-z_]\w*)\s*(?=\()/g, 'fn'
]);

/* ── Bash / Shell ──────────────────────────────────────────────────────── */
_HL_LANGS['bash']=_HL_LANGS['sh']=_HL_LANGS['shell']=_HL_LANGS['zsh']=_hlRules([
  /(#.*$)/gm, 'cm',
  /("(?:\\.|[^"\\])*")/g, 'str',
  /('(?:[^'\\]|\\.)*')/g, 'str',
  /\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|local|export|source|alias|unalias|set|unset|declare|readonly|shift|exit|break|continue|trap|eval|exec|select|until|coproc)\b/g, 'kw',
  /(\$\{[^}]*\}|\$\w+|\$[?!#@*0-9])/g, 'bi',
  /\b(echo|cd|ls|grep|sed|awk|find|cat|mkdir|rm|cp|mv|chmod|chown|curl|wget|tar|git|sudo|apt|pip|npm|make|cmake|meson|ninja|docker|ssh|kill|ps|head|tail|sort|uniq|wc|cut|tr|xargs|tee|diff|patch|which|type|test|read)\b/g, 'fn',
  /\b(\d+)\b/g, 'num',
  /([|&;<>]+|>>|<<|\|\||&&)/g, 'op'
]);

/* ── Rust ──────────────────────────────────────────────────────────────── */
_HL_LANGS['rust']=_HL_LANGS['rs']=_hlRules([
  /(\/\/.*$)/gm, 'cm',
  /(\/\*[\s\S]*?\*\/)/g, 'cm',
  /("(?:\\.|[^"\\])*")/g, 'str',
  /(#!\[[\s\S]*?\]|#\[[\s\S]*?\])/g, 'dc',
  /\b(as|async|await|break|const|continue|crate|dyn|else|enum|extern|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|type|unsafe|use|where|while|yield)\b/g, 'kw',
  /\b(true|false|None|Some|Ok|Err|Vec|String|Box|Rc|Arc|Option|Result)\b/g, 'bi',
  /\b(\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?(?:f32|f64|i8|i16|i32|i64|i128|u8|u16|u32|u64|u128|usize|isize)?|0[xX][\da-fA-F_]+|0[oO][0-7_]+|0[bB][01_]+)\b/g, 'num',
  /([+\-*/%=<>!&|^~?:]+|=>|->|::)/g, 'op',
  /\b([A-Za-z_]\w*)\s*(?=\()/g, 'fn'
]);

/* ── Go ────────────────────────────────────────────────────────────────── */
_HL_LANGS['go']=_HL_LANGS['golang']=_hlRules([
  /(\/\/.*$)/gm, 'cm',
  /(\/\*[\s\S]*?\*\/)/g, 'cm',
  /(`[^`]*`)/g, 'str',
  /("(?:\\.|[^"\\])*")/g, 'str',
  /\b(break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var)\b/g, 'kw',
  /\b(true|false|nil|iota)\b/g, 'bi',
  /\b(int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|byte|rune|string|bool|error|any)\b/g, 'bi',
  /\b(\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?|0[xX][\da-fA-F_]+|0[oO][0-7_]+|0[bB][01_]+)\b/g, 'num',
  /([+\-*/%=<>!&|^~:]+|<-|:=)/g, 'op',
  /\b([A-Za-z_]\w*)\s*(?=\()/g, 'fn'
]);

/* ── Java ──────────────────────────────────────────────────────────────── */
_HL_LANGS['java']=_hlRules([
  /(\/\/.*$)/gm, 'cm',
  /(\/\*[\s\S]*?\*\/)/g, 'cm',
  /("(?:\\.|[^"\\])*")/g, 'str',
  /\b(abstract|assert|break|case|catch|class|const|continue|default|do|else|enum|extends|final|finally|for|goto|if|implements|import|instanceof|interface|native|new|package|private|protected|public|return|static|strictfp|super|switch|synchronized|this|throw|throws|transient|try|var|void|volatile|while|yield|record|sealed|permits)\b/g, 'kw',
  /\b(true|false|null)\b/g, 'bi',
  /(@\w+)/g, 'dc',
  /\b(\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?[fFdDlL]?|0[xX][\da-fA-F_]+[lL]?|0[bB][01_]+[lL]?)\b/g, 'num',
  /([+\-*/%=<>!&|^~?:]+|->|::)/g, 'op',
  /\b([A-Za-z_]\w*)\s*(?=\()/g, 'fn'
]);

/* ── JSON ──────────────────────────────────────────────────────────────── */
_HL_LANGS['json']=_hlRules([
  /("(?:\\.|[^"\\])*")\s*:/g, 'fn',
  /("(?:\\.|[^"\\])*")/g, 'str',
  /\b(true|false|null)\b/g, 'bi',
  /(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/g, 'num'
]);

/* ── HTML / XML ────────────────────────────────────────────────────────── */
_HL_LANGS['html']=_HL_LANGS['xml']=_HL_LANGS['svg']=_hlRules([
  /(&lt;!--[\s\S]*?--&gt;)/g, 'cm',
  /(&lt;\/?)([\w-]+)/g, 'kw',
  /([\w-]+)(=)/g, 'fn',
  /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g, 'str',
  /(&gt;)/g, 'kw'
]);

/* ── CSS ───────────────────────────────────────────────────────────────── */
_HL_LANGS['css']=_hlRules([
  /(\/\*[\s\S]*?\*\/)/g, 'cm',
  /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g, 'str',
  /([\w-]+)\s*(?=:)/g, 'fn',
  /(#[\da-fA-F]{3,8})\b/g, 'num',
  /(-?\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg|fr)?)/g, 'num',
  /([.#][\w-]+|@[\w-]+)/g, 'kw'
]);

/* ── SQL ───────────────────────────────────────────────────────────────── */
_HL_LANGS['sql']=_hlRules([
  /(--.*$)/gm, 'cm',
  /(\/\*[\s\S]*?\*\/)/g, 'cm',
  /('(?:''|[^'])*')/g, 'str',
  /\b(SELECT|FROM|WHERE|INSERT|INTO|UPDATE|DELETE|SET|CREATE|DROP|ALTER|TABLE|INDEX|VIEW|JOIN|LEFT|RIGHT|INNER|OUTER|CROSS|ON|AND|OR|NOT|IN|IS|NULL|AS|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|UNION|ALL|DISTINCT|EXISTS|BETWEEN|LIKE|CASE|WHEN|THEN|ELSE|END|BEGIN|COMMIT|ROLLBACK|VALUES|PRIMARY|KEY|FOREIGN|REFERENCES|CONSTRAINT|DEFAULT|CHECK|UNIQUE|CASCADE|GRANT|REVOKE|WITH)\b/gi, 'kw',
  /\b(\d+(?:\.\d+)?)\b/g, 'num',
  /\b(COUNT|SUM|AVG|MIN|MAX|COALESCE|IFNULL|CAST|CONVERT|TRIM|UPPER|LOWER|LENGTH|SUBSTRING|CONCAT|NOW|DATE|TIME)\b/gi, 'bi'
]);

/* ── Ruby ──────────────────────────────────────────────────────────────── */
_HL_LANGS['ruby']=_HL_LANGS['rb']=_hlRules([
  /(#.*$)/gm, 'cm',
  /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g, 'str',
  /\b(alias|and|begin|break|case|class|def|defined|do|else|elsif|end|ensure|for|if|in|module|next|nil|not|or|raise|redo|rescue|retry|return|self|super|then|undef|unless|until|when|while|yield)\b/g, 'kw',
  /\b(true|false|nil)\b/g, 'bi',
  /(:\w+)/g, 'str',
  /(@\w+|@@\w+|\$\w+)/g, 'bi',
  /\b(\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?|0[xX][\da-fA-F_]+|0[bB][01_]+)\b/g, 'num',
  /\b([A-Za-z_]\w*)\s*(?=\()/g, 'fn'
]);

/* ── YAML ──────────────────────────────────────────────────────────────── */
_HL_LANGS['yaml']=_HL_LANGS['yml']=_hlRules([
  /(#.*$)/gm, 'cm',
  /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g, 'str',
  /^([\w][\w. -]*)(:)/gm, 'fn',
  /\b(true|false|null|yes|no|on|off)\b/gi, 'bi',
  /(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b/g, 'num'
]);

/* ── Diff ──────────────────────────────────────────────────────────────── */
_HL_LANGS['diff']=_HL_LANGS['patch']=_hlRules([
  /^(\+.*)$/gm, 'str',
  /^(-.*)$/gm, 'dc',
  /^(@@.*@@)/gm, 'kw'
]);

/* ── Markdown ──────────────────────────────────────────────────────────── */
_HL_LANGS['markdown']=_HL_LANGS['md']=_hlRules([
  /^(#{1,6}\s+.*)$/gm, 'kw',
  /(\*\*[^*]+\*\*|__[^_]+__)/g, 'str',
  /(\*[^*]+\*|_[^_]+_)/g, 'str',
  /(`[^`]+`)/g, 'fn',
  /^(\s*[-*+]\s)/gm, 'op',
  /(\[.*?\]\(.*?\))/g, 'bi'
]);

/* ── Highlight engine ──────────────────────────────────────────────────── */
function _hlApply(text,rules){
  /* Tokenise: find all matches, sort by position, skip overlaps,
     then rebuild with <span> wrappers. */
  var tokens=[];
  for(var r=0;r<rules.length;r++){
    var rule=rules[r];
    rule.re.lastIndex=0;
    var m;
    while((m=rule.re.exec(text))!==null){
      /* Use the first capturing group if present, else full match. */
      var s=m[1]!==undefined?m[1]:m[0];
      var idx=m.index+(m[0].indexOf(s));
      tokens.push({start:idx,end:idx+s.length,cls:rule.cls});
    }
  }
  /* Sort by start position, then longer match first. */
  tokens.sort(function(a,b){return a.start-b.start||(b.end-a.end);});
  /* Remove overlaps. */
  var result=[];
  var last=0;
  for(var i=0;i<tokens.length;i++){
    var t=tokens[i];
    if(t.start<last)continue;
    if(t.start>last)result.push(escHtml(text.substring(last,t.start)));
    result.push('<span class="hl-'+t.cls+'">'+escHtml(text.substring(t.start,t.end))+'</span>');
    last=t.end;
  }
  if(last<text.length)result.push(escHtml(text.substring(last)));
  return result.join('');
}

/* Highlight all <code class="language-*"> blocks within a root element. */
function hlElement(root){
  var blocks=root.querySelectorAll('pre code[class*="language-"]');
  for(var i=0;i<blocks.length;i++){
    var code=blocks[i];
    var cls=code.className;
    var lang='';
    var m=cls.match(/language-(\S+)/);
    if(m)lang=m[1].toLowerCase();
    var rules=_HL_LANGS[lang];
    if(!rules)continue;
    /* Decode HTML entities back to text, highlight, then set innerHTML. */
    var text=code.textContent;
    code.innerHTML=_hlApply(text,rules);
    code.classList.add('hl-done');
  }
}
