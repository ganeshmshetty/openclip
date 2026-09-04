// ActionSearchKeywords.swift
// OpenClip
//
// Pure Core lookup providing multi-lingual search keywords (English, Chinese Simplified,
// Chinese Traditional, French, Japanese) and common synonyms for builtin actions, AI presets,
// and popular extension catalog actions.
import Foundation

public enum ActionSearchKeywords {
    /// Returns multi-lingual search keywords (synonyms in EN, ZH-Hans, ZH-Hant, FR, JA) for an action.
    public static func keywords(for actionID: String, actionTitle: String = "") -> [String] {
        var results = Set<String>()
        let lowerID = actionID.lowercased()

        // 1. Direct dictionary match by action ID
        if let direct = dictionary[lowerID] {
            results.formUnion(direct)
        }

        // 2. AI Preset ID lookup (e.g. "ai.preset.proofread" -> "proofread")
        if lowerID.hasPrefix("ai.preset.") {
            let presetID = String(lowerID.dropFirst("ai.preset.".count))
            if let presetKeywords = dictionary[presetID] {
                results.formUnion(presetKeywords)
            }
        }

        // 3. Normalized title slug lookup (e.g. "Character Count" -> "charactercount")
        let titleSlug = normalizedSlug(actionTitle)
        if !titleSlug.isEmpty, let titleKeywords = dictionary[titleSlug] {
            results.formUnion(titleKeywords)
        }

        // 4. Suffix matching for package/action IDs (e.g. "com.openclip.charactercount" -> "charactercount")
        for (key, words) in dictionary {
            if lowerID.hasSuffix("." + key) || lowerID.hasSuffix("/" + key) || lowerID == key {
                results.formUnion(words)
            }
        }

        return Array(results)
    }

    /// Strips spaces, punctuation, and non-alphanumeric characters for slug matching.
    public static func normalizedSlug(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Keyword Dictionary (EN, ZH-Hans, ZH-Hant, FR, JA)

    public static let dictionary: [String: [String]] = [
        // Builtin Actions
        "builtin.search": [
            "search", "google", "query", "web", "find", "lookup", "browse", "baidu", "yahoo",
            "搜索", "查找", "检索", "谷歌", "网页搜索", "百度",
            "搜尋", "檢索", "網頁搜尋",
            "recherche", "chercher", "trouver",
            "検索", "探す", "調べる", "ぐぐる", "グーグル", "ヤフー"
        ],
        "builtin.calculate": [
            "calculate", "calc", "math", "evaluate", "sum", "plus", "calculator", "computation", "1+1",
            "计算", "算数", "数学", "求和", "计算器", "口算", "等于",
            "計算", "算數", "數學", "計算器", "等於",
            "calculer", "calcul", "maths", "calculatrice", "somme",
            "計算", "算数", "数学", "電卓", "計算機", "合計"
        ],
        "builtin.define": [
            "define", "dictionary", "lookup", "meaning", "definition", "word", "dict", "vocabulary",
            "词典", "查词", "定义", "释义", "字典", "查单词", "意思",
            "詞典", "查詞", "定義", "釋義", "查單詞",
            "définir", "dictionnaire", "définition", "sens", "mot",
            "辞書", "定義", "意味", "辞書引き", "国語辞典", "単語"
        ],
        "builtin.calendar": [
            "calendar", "event", "reminder", "schedule", "date", "meeting", "appointment",
            "日历", "日程", "事件", "提醒", "会议", "安排", "日期",
            "日曆", "提醒事項", "安排",
            "calendrier", "événement", "rendez-vous", "agenda", "date",
            "カレンダー", "予定", "スケジュール", "イベント", "日程"
        ],
        "builtin.copy": [
            "copy", "clipboard", "duplicate",
            "复制", "拷贝", "剪贴板",
            "複製", "拷貝", "剪貼板",
            "copier", "presse-papier", "dupliquer",
            "コピー", "クリップボード", "複製"
        ],
        "builtin.cut": [
            "cut", "clipboard", "snip",
            "剪切", "剪下",
            "couper",
            "カット", "切り取り"
        ],
        "builtin.paste": [
            "paste", "clipboard", "insert",
            "粘贴", "贴上",
            "貼上",
            "coller", "insérer",
            "ペースト", "貼り付け"
        ],
        "builtin.reveal_in_finder": [
            "finder", "reveal", "folder", "show", "directory", "file", "path", "open folder",
            "访达", "文件夹", "打开目录", "显示文件", "路径", "定位",
            "訪達", "檔案夾", "打開目錄", "顯示檔案", "路徑",
            "finder", "dossier", "fichier", "répertoire", "afficher",
            "ファインダー", "フォルダ", "ファイル", "ディレクトリ", "表示"
        ],
        "builtin.openurl": [
            "open", "url", "link", "browser", "web", "safari", "chrome", "navigate",
            "打开", "网址", "链接", "浏览器", "跳转",
            "打開", "網址", "鏈接", "瀏覽器", "跳轉",
            "ouvrir", "lien", "navigateur", "adresse",
            "開く", "ブラウザ", "リンク", "URL", "ウェブ"
        ],
        "builtin.completion": [
            "completion", "suggest", "autocomplete", "word",
            "补全", "建议", "自动补全",
            "補全", "建議", "自動補全",
            "complétion", "saisie automatique", "suggestion",
            "補完", "サジェスト", "入力補完"
        ],
        "builtin.aitools": [
            "ai", "intelligence", "assistant", "bot", "smart",
            "智能", "助手", "人工智能", "大模型", "助理",
            "ia", "intelligence artificielle", "assistant",
            "AI", "人工知能", "アシスタント"
        ],
        "builtin.ai_tools": [
            "ai", "intelligence", "assistant", "bot", "smart",
            "智能", "助手", "人工智能", "大模型", "助理",
            "ia", "intelligence artificielle", "assistant",
            "AI", "人工知能", "アシスタント"
        ],

        // AI Presets
        "proofread": [
            "proofread", "grammar", "spelling", "typo", "check", "correct", "editing",
            "润色", "语法", "拼写", "纠错", "错别字", "改错", "修改",
            "潤色", "語法", "拼寫", "糾錯", "錯別字",
            "corriger", "grammaire", "orthographe", "correction", "relecture",
            "校正", "添削", "スペルチェック", "文法", "誤字", "修正"
        ],
        "rewrite": [
            "rewrite", "rephrase", "paraphrase", "improve", "polish", "reword",
            "改写", "重写", "润饰", "优化语言", "转述",
            "改寫", "重寫", "潤飾", "優化語言", "轉述",
            "réécrire", "reformuler", "paraphraser", "amélioration",
            "書き直し", "リライト", "言い換え", "推敲", "表現変更"
        ],
        "summarize": [
            "summarize", "summary", "tl;dr", "tldr", "brief", "overview", "key points", "digest",
            "总结", "摘要", "概述", "提炼", "简述", "要点",
            "總結", "摘要", "概述", "提煉", "簡述", "要點",
            "résumer", "résumé", "synthèse", "points clés",
            "要約", "まとめ", "概要", "要点", "短く"
        ],
        "explain": [
            "explain", "clarify", "details", "understand", "what is", "elaborate",
            "解释", "说明", "阐述", "解读", "含义", "介绍",
            "解釋", "說明", "闡述", "解讀", "含義", "介紹",
            "expliquer", "explication", "détails", "éclaircir",
            "説明", "解説", "詳しく", "意味", "理解"
        ],
        "translate": [
            "translate", "translation", "language", "multilingual", "localize",
            "翻译", "译", "语言", "多语言", "英译中", "中译英",
            "翻譯", "譯", "語言", "多語言", "英譯中", "中譯英",
            "traduire", "traduction", "langue", "multilingue",
            "翻訳", "訳す", "多言語", "和訳", "英訳"
        ],
        "fix_code": [
            "fix code", "fix", "code", "bug", "debug", "syntax", "error", "compile",
            "修复代码", "找错", "报错", "调试", "修bug", "代码纠错",
            "修復代碼", "找錯", "報錯", "調試", "代碼糾錯",
            "corriger code", "bogue", "débogage", "erreur", "code",
            "バグ修正", "コード修正", "デバッグ", "エラー修正", "コード"
        ],
        "make_shorter": [
            "make shorter", "shorten", "concise", "condense", "trim", "compact",
            "缩短", "精简", "更简短", "浓缩", "删减",
            "縮短", "精簡", "更簡短", "濃縮", "刪減",
            "raccourcir", "plus court", "concis", "condenser",
            "短縮", "短く", "簡潔に", "凝縮"
        ],
        "formal_tone": [
            "formal tone", "formal", "business", "polite", "professional", "official",
            "正式", "严肃", "商务", "礼貌", "语气", "公文",
            "正式", "嚴肅", "商務", "禮貌", "語氣", "公文",
            "ton formel", "professionnel", "poli", "soutenu",
            "ビジネス", "丁寧", "敬語", "改まった表現", "フォーマル"
        ],

        // Catalog Extensions: Counters & Stats
        "charactercount": [
            "character count", "characters", "char count", "length", "len", "count", "stats",
            "字数", "字符数", "字符", "字数统计", "长度",
            "字數", "字符數", "字數統計", "長度",
            "nombre de caractères", "caractères", "longueur", "compter",
            "文字数", "文字カウント", "長さ", "文字数カウント"
        ],
        "wordcount": [
            "word count", "words", "count", "tokens",
            "单词数", "词数", "单词统计", "词频",
            "單詞數", "詞數", "單詞統計", "詞頻",
            "nombre de mots", "mots", "compter les mots",
            "単語数", "ワードカウント", "単語"
        ],
        "linecount": [
            "line count", "lines", "total lines",
            "行数", "行数统计", "总行数",
            "行數", "行數統計", "總行數",
            "nombre de lignes", "lignes",
            "行数", "ライン数", "行カウント"
        ],
        "paragraphcount": [
            "paragraph count", "paragraphs",
            "段落数", "段落",
            "段落數", "段落",
            "nombre de paragraphes", "paragraphes",
            "段落数", "パラグラフ"
        ],

        // Catalog Extensions: Letter Casing
        "uppercase": [
            "uppercase", "upper", "caps", "all caps", "capitalize",
            "大写", "全部大写", "转大写", "字母大写",
            "大寫", "全部大寫", "轉大寫", "字母大寫",
            "majuscule", "tout majuscule", "lettres majuscules",
            "大文字", "全て大文字", "アッパーケース"
        ],
        "lowercase": [
            "lowercase", "lower", "small letters",
            "小写", "全部小写", "转小写",
            "小寫", "全部小寫", "轉小寫",
            "minuscule", "tout minuscule",
            "小文字", "全て小文字", "ロワーケース"
        ],
        "titlecase": [
            "title case", "title", "heading case",
            "首字母大写", "词首大写", "标题大写",
            "首字母大寫", "詞首大寫", "標題大寫",
            "casse de titre", "majuscule au début",
            "タイトルケース", "先頭大文字"
        ],
        "capitalizewords": [
            "capitalize words", "capitalize", "capital",
            "首字母大写", "每个单词大写",
            "首字母大寫", "每個單詞大寫",
            "majuscule aux mots",
            "各単語を大文字"
        ],
        "sentencecase": [
            "sentence case", "sentence",
            "句首大写", "句子大写",
            "句首大寫", "句子大寫",
            "casse de phrase",
            "センテンスケース", "文頭大文字"
        ],
        "camelcase": [
            "camelcase", "camel", "camelCase", "naming",
            "驼峰", "小驼峰", "驼峰命名",
            "駝峰", "小駝峰", "駝峰命名",
            "casse chameau", "camel case",
            "キャメルケース"
        ],
        "pascalcase": [
            "pascalcase", "pascal", "upper camel",
            "大驼峰", "帕斯卡", "帕斯卡命名",
            "大駝峰", "帕斯卡", "帕斯卡命名",
            "pascal case",
            "パスカルケース"
        ],
        "snakecase": [
            "snakecase", "snake", "snake_case", "underscore",
            "下划线", "蛇形", "蛇形命名",
            "下劃線", "蛇形", "蛇形命名",
            "snake case",
            "スネークケース", "アンダースコア"
        ],
        "kebabcase": [
            "kebabcase", "kebab", "kebab-case", "dash", "hyphen",
            "短横线", "中划线", "烤串命名", "脊柱命名",
            "短橫線", "中劃線", "烤串命名",
            "kebab case", "tiret",
            "ケバブケース", "ハイフン区切り"
        ],
        "constantcase": [
            "constant case", "constant", "upper snake",
            "常量命名", "大写下划线",
            "常量命名", "大寫下劃線",
            "constante",
            "定数名"
        ],
        "dotcase": [
            "dotcase", "dot", "period",
            "点分隔", "点号命名",
            "點分隔", "點號命名",
            "point",
            "ドット区切り"
        ],
        "hyphenate": [
            "hyphenate", "hyphen", "dash",
            "连字符", "短横",
            "連字符", "短橫",
            "trait d'union",
            "ハイフン"
        ],
        "slugify": [
            "slugify", "slug", "url slug",
            "别名", "网址别名", "slug",
            "別名", "網址別名", "slug",
            "slugifier", "slug",
            "スラッグ化"
        ],
        "rot13": [
            "rot13", "cipher", "caesar",
            "凯撒密码", "rot13加密",
            "凱撒密碼", "rot13加密",
            "chiffrement rot13",
            "暗号化", "rot13"
        ],

        // Catalog Extensions: Line & Text Manipulation
        "sortalphabetical": [
            "sort alphabetical", "sort", "alphabetical", "a-z", "az", "order",
            "字母排序", "按字母排序", "排序", "字典序",
            "字母排序", "按字母排序", "排序", "字典序",
            "tri alphabétique", "trier",
            "アルファベット順", "ソート", "並び替え"
        ],
        "sortnumerical": [
            "sort numerical", "sort numbers", "numerical sort", "1-9",
            "数字排序", "按数字排序", "排序",
            "數字排序", "按數字排序", "排序",
            "tri numérique",
            "数値ソート", "数字順"
        ],
        "reverselines": [
            "reverse lines", "invert lines",
            "行倒序", "反转行", "倒序",
            "行倒序", "反轉行", "倒序",
            "inverser les lignes",
            "行の反転", "逆順"
        ],
        "reversetext": [
            "reverse text", "mirror text",
            "文本反转", "倒放文字",
            "文本反轉", "倒放文字",
            "inverser le texte",
            "文字列反転", "テキスト反転"
        ],
        "reversewords": [
            "reverse words",
            "词反转", "单词倒序",
            "詞反轉", "單詞倒序",
            "inverser les mots",
            "単語の反転"
        ],
        "deduplicatelines": [
            "deduplicate lines", "deduplicate", "unique", "remove duplicates", "distinct",
            "去重", "去除重复", "去重复行", "唯一",
            "去重", "去除重複", "去重複行", "唯一",
            "supprimer doublons", "lignes uniques",
            "重複削除", "ユニーク行"
        ],
        "shufflelines": [
            "shuffle lines", "randomize lines", "random",
            "打乱行", "随机排序", "乱序",
            "打亂行", "隨機排序", "亂序",
            "mélanger les lignes", "aléatoire",
            "行シャッフル", "ランダム"
        ],
        "trimlines": [
            "trim lines", "trim", "strip", "whitespace",
            "去空格", "去除空白", "首尾空格",
            "去空格", "去除空白", "首尾空格",
            "supprimer espaces", "élaguer",
            "空白削除", "トリム"
        ],
        "normalizespaces": [
            "normalize spaces", "normalize", "whitespace",
            "规范空格", "整理空格", "合并空格",
            "規範空格", "整理空格", "合併空格",
            "normaliser espaces",
            "スペース正規化"
        ],
        "removeallspaces": [
            "remove all spaces", "no space",
            "删除所有空格", "无空格",
            "刪除所有空格", "無空格",
            "supprimer tous les espaces",
            "すべてのスペースを削除"
        ],
        "removelinebreaks": [
            "remove line breaks", "unwrap", "join lines",
            "删除换行", "合并单行",
            "刪除換行", "合併單行",
            "supprimer retours à la ligne",
            "改行削除", "一行化"
        ],
        "numberlines": [
            "number lines", "index lines", "line numbers",
            "添加行号", "行编号",
            "添加行號", "行編號",
            "numéroter les lignes",
            "行番号付加"
        ],
        "quotelines": [
            "quote lines", "quotation",
            "加引号", "行加引号",
            "加引號", "行加引號",
            "guillemets aux lignes",
            "行を引用符で囲む"
        ],
        "bulletlines": [
            "bullet lines", "list", "bullet point",
            "无序列表", "项目符号", "加圆点",
            "無序列表", "項目符號",
            "puces", "liste à puces",
            "箇条書き", "リスト"
        ],
        "tasklines": [
            "task lines", "todo list", "checkbox",
            "任务列表", "待办列表", "复选框",
            "任務列表", "待辦列表", "核取方塊",
            "liste de tâches", "cases à cocher",
            "タスクリスト", "チェックボックス"
        ],
        "joincommas": [
            "join commas", "csv join", "join",
            "逗号连接", "逗号合并",
            "逗號連接", "逗號合併",
            "joindre virgules",
            "カンマ結合"
        ],
        "splitcommas": [
            "split commas", "csv split", "split",
            "逗号分割", "逗号拆分",
            "逗號分割", "逗號拆分",
            "séparer virgules",
            "カンマ分割"
        ],
        "deleteselection": [
            "delete selection", "delete", "erase", "remove", "clear",
            "删除选中", "清空",
            "刪除選取", "清空",
            "supprimer", "effacer",
            "選択削除", "クリア"
        ],
        "selectall": [
            "select all", "choose all",
            "全选",
            "全選",
            "tout sélectionner",
            "全選択"
        ],
        "speakselection": [
            "speak selection", "speak", "tts", "read aloud", "voice", "pronounce",
            "朗读", "发音", "语音播放", "读出",
            "朗讀", "發音", "語音播放", "讀出",
            "lire à haute voix", "voix", "prononcer",
            "読み上げ", "音声", "発音"
        ],
        "pasteenter": [
            "paste enter", "paste return", "send",
            "粘贴并发送", "回车",
            "貼上並發送", "回車",
            "coller et envoyer",
            "ペーストして送信"
        ],

        // Catalog Extensions: Markdown & Formatting
        "copyasmarkdown": [
            "copy as markdown", "markdown", "md",
            "复制为markdown", "md格式",
            "拷貝為Markdown", "md格式",
            "copier en markdown",
            "Markdownとしてコピー"
        ],
        "renderhtml": [
            "render html", "html preview", "html",
            "渲染html", "html预览",
            "渲染HTML", "HTML預覽",
            "prévisualiser html",
            "HTMLプレビュー"
        ],
        "rendermarkdown": [
            "render markdown", "markdown preview",
            "渲染markdown", "markdown预览",
            "渲染Markdown", "Markdown預覽",
            "prévisualiser markdown",
            "Markdownプレビュー"
        ],
        "bold": [
            "bold", "strong", "**",
            "加粗", "粗体",
            "加粗", "粗體",
            "gras",
            "太字", "ボールド"
        ],
        "markdownbold": [
            "markdown bold", "bold", "strong", "**",
            "加粗", "粗体",
            "加粗", "粗體",
            "gras",
            "太字", "ボールド"
        ],
        "italic": [
            "italic", "emphasis", "*",
            "斜体",
            "斜體",
            "italique",
            "斜体", "イタリック"
        ],
        "markdownitalic": [
            "markdown italic", "italic", "emphasis", "*",
            "斜体",
            "斜體",
            "italique",
            "斜体", "イタリック"
        ],
        "strikethrough": [
            "strikethrough", "strike", "~~",
            "删除线",
            "刪除線",
            "barré",
            "取り消し線"
        ],
        "markdownstrikethrough": [
            "markdown strikethrough", "strikethrough", "strike", "~~",
            "删除线",
            "刪除線",
            "barré",
            "取り消し線"
        ],
        "markdownlink": [
            "markdown link", "link", "[url]()",
            "超链接", "插入链接",
            "超連結", "插入鏈接",
            "lien markdown",
            "リンク"
        ],
        "markdownblockquote": [
            "markdown blockquote", "blockquote", "quote", ">",
            "块引用", "引用",
            "引用區塊", "引用",
            "citation", "bloc citation",
            "引用"
        ],
        "codeblock": [
            "code block", "code",
            "代码块",
            "程式碼區塊",
            "bloc de code",
            "コードブロック"
        ],
        "inlinecode": [
            "inline code", "code",
            "行内代码",
            "行內程式碼",
            "code en ligne",
            "インラインコード"
        ],
        "headerone": [
            "header one", "heading 1", "h1",
            "一级标题", "标题一",
            "標題一", "一級標題",
            "titre 1",
            "見出し1"
        ],
        "headertwo": [
            "header two", "heading 2", "h2",
            "二级标题", "标题二",
            "標題二", "二級標題",
            "titre 2",
            "見出し2"
        ],
        "headerthree": [
            "header three", "heading 3", "h3",
            "三级标题", "标题三",
            "標題三", "三級標題",
            "titre 3",
            "見出し3"
        ],
        "underline": [
            "underline", "<u>",
            "下划线",
            "下劃線",
            "souligné",
            "下線"
        ],

        // Catalog Extensions: Enclosing & Quotes
        "anglebrackets": [
            "angle brackets", "<>",
            "尖括号",
            "尖括號",
            "chevrons",
            "山括弧"
        ],
        "curlybrackets": [
            "curly brackets", "braces", "{}",
            "大括号", "花括号",
            "大括號", "花括號",
            "accolades",
            "波括弧"
        ],
        "roundbrackets": [
            "round brackets", "parentheses", "()",
            "圆括号", "小括号",
            "圓括號", "小括號",
            "parenthèses",
            "丸括弧"
        ],
        "squarebrackets": [
            "square brackets", "[]",
            "方括号", "中括号",
            "方括號", "中括號",
            "crochets",
            "角括弧"
        ],
        "doublequotes": [
            "double quotes", "\"\"",
            "双引号",
            "雙引號",
            "guillemets doubles",
            "二重引用符"
        ],
        "singlequotes": [
            "single quotes", "''",
            "单引号",
            "單引號",
            "guillemets simples",
            "一重引用符"
        ],

        // Catalog Extensions: Web, Search & Extraction
        "googletranslate": [
            "google translate", "translate", "web translate",
            "谷歌翻译", "在线翻译",
            "谷歌翻譯", "線上翻譯",
            "google traduction",
            "Google翻訳"
        ],
        "quicktranslate": [
            "quick translate", "translate",
            "快速翻译",
            "快速翻譯",
            "traduction rapide",
            "クイック翻訳"
        ],
        "googlemaps": [
            "google maps", "maps", "directions", "navigation",
            "谷歌地图", "地图导航",
            "谷歌地圖", "地圖導航",
            "google maps", "carte", "itinéraire",
            "Googleマップ", "地図", "ルート"
        ],
        "googlescholar": [
            "google scholar", "academic", "paper",
            "谷歌学术", "论文搜索",
            "谷歌學術", "論文搜尋",
            "google scholar", "recherche universitaire",
            "Googleスカラー", "論文"
        ],
        "githubsearch": [
            "github search", "github", "git", "open source", "repository",
            "github搜索", "开源代码",
            "github搜尋", "開源程式碼",
            "recherche github",
            "GitHub検索"
        ],
        "devdocssearch": [
            "devdocs search", "devdocs", "api docs", "developer documentation",
            "开发文档", "devdocs速查",
            "開發文檔", "devdocs速查",
            "documentation devdocs",
            "開発ドキュメント"
        ],
        "mdndocs": [
            "mdn docs", "mdn", "mozilla", "web docs",
            "mdn文档", "前端文档",
            "mdn文檔", "前端文檔",
            "documentation mdn",
            "MDNドキュメント"
        ],
        "caniuse": [
            "caniuse", "browser compatibility", "support",
            "兼容性", "浏览器支持",
            "相容性", "瀏覽器支援",
            "compatibilité navigateur",
            "ブラウザ対応状況"
        ],
        "npmsearch": [
            "npm search", "npm", "package", "node",
            "npm包", "node模块",
            "npm套件", "node模組",
            "paquet npm",
            "npmパッケージ"
        ],
        "pypisearch": [
            "pypi search", "pypi", "pip", "python package",
            "python包", "pip安装",
            "python套件", "pip安裝",
            "paquet pypi",
            "PyPIパッケージ"
        ],
        "stackoverflow": [
            "stackoverflow", "stack overflow", "code error",
            "编程问答", "技术问答",
            "編程問答", "技術問答",
            "questions stack overflow",
            "技術質問"
        ],
        "wikipediasearch": [
            "wikipedia search", "wikipedia", "wiki", "encyclopedia",
            "维基百科", "百科",
            "維基百科", "百科",
            "wikipédia", "encyclopédie",
            "ウィキペディア", "百科事典"
        ],
        "wolframalpha": [
            "wolfram alpha", "wolfram", "computation",
            "知识计算", "数学引擎",
            "知識計算", "數學引擎",
            "moteur de calcul wolfram",
            "計算エンジン"
        ],
        "searchyoutube": [
            "search youtube", "youtube", "video", "yt",
            "油管", "视频搜索",
            "油管", "影片搜尋",
            "vidéo youtube",
            "YouTube検索", "動画"
        ],
        "waybackmachine": [
            "wayback machine", "internet archive", "cached",
            "网页时光机", "历史快照",
            "網頁時光機", "歷史快照",
            "archives web",
            "ウェブアーカイブ"
        ],
        "extracturls": [
            "extract urls", "get links", "urls", "links",
            "提取网址", "提取链接", "抓取链接",
            "提取網址", "提取鏈接",
            "extraire liens",
            "URL抽出", "リンク抽出"
        ],
        "extractemails": [
            "extract emails", "get emails", "mail",
            "提取邮箱", "抓取邮箱",
            "提取郵箱",
            "extraire adresses email",
            "メールアドレス抽出"
        ],
        "extractphones": [
            "extract phones", "get phone numbers", "mobile",
            "提取电话", "提取手机号",
            "提取電話", "提取手機號",
            "extraire numéros téléphone",
            "電話番号抽出"
        ],
        "extractips": [
            "extract ips", "ip addresses",
            "提取ip",
            "提取IP",
            "extraire adresses ip",
            "IPアドレス抽出"
        ],
        "extracthashtags": [
            "extract hashtags", "tags", "#",
            "提取标签", "话题",
            "提取標籤", "話題",
            "extraire hashtags",
            "ハッシュタグ抽出"
        ],

        // Catalog Extensions: Notes & Apps
        "notes": [
            "notes", "apple notes", "memo", "quick note",
            "备忘录", "苹果备忘录",
            "備忘錄", "蘋果備忘錄",
            "notes apple",
            "メモ", "Appleメモ"
        ],
        "applenotes": [
            "apple notes", "notes", "memo",
            "备忘录", "苹果备忘录",
            "備忘錄", "蘋果備忘錄",
            "notes apple",
            "メモ", "Appleメモ"
        ],
        "applereminders": [
            "apple reminders", "reminders", "todo",
            "提醒事项",
            "提醒事項",
            "rappels apple",
            "リマインダー"
        ],
        "applemessages": [
            "apple messages", "messages", "sms", "imessage",
            "信息", "短信",
            "訊息", "簡訊",
            "messages apple",
            "メッセージ"
        ],
        "applemusic": [
            "apple music", "music", "song", "play",
            "音乐",
            "音樂",
            "musique apple",
            "ミュージック"
        ],
        "mailcompose": [
            "mail compose", "send email", "email",
            "写邮件", "发邮件",
            "寫郵件", "寄信",
            "écrire un email",
            "メール作成"
        ],
        "draftsnote": [
            "drafts note", "drafts",
            "草稿",
            "草稿",
            "note drafts",
            "下書き"
        ],
        "bearnotes": [
            "bear notes", "bear",
            "熊掌记",
            "熊掌記",
            "notes bear",
            "ベアナイト"
        ],
        "craftdocs": [
            "craft docs", "craft",
            "craft笔记",
            "craft筆記",
            "documents craft",
            "クラフト"
        ],
        "obsidiancapture": [
            "obsidian capture", "obsidian", "vault",
            "黑曜石", "obsidian笔记",
            "黑曜石", "obsidian筆記",
            "note obsidian",
            "オブシディアン"
        ],
        "logseqcapture": [
            "logseq capture", "logseq",
            "大纲", "logseq笔记",
            "大綱", "logseq筆記",
            "note logseq",
            "ログシーク"
        ],
        "fantasticalevent": [
            "fantastical event", "fantastical",
            "日历事件",
            "日曆事件",
            "événement fantastical",
            "ファンタスティカル"
        ],
        "thingsthree": [
            "things three", "things", "task",
            "things任务",
            "things任務",
            "tâche things",
            "シングス"
        ],
        "todoisttask": [
            "todoist task", "todoist", "task",
            "todoist任务",
            "todoist任務",
            "tâche todoist",
            "トゥードゥーイスト"
        ],

        // General Data Formats & Encodings
        "json": [
            "json", "format", "pretty", "minify", "parse",
            "json格式化", "美化", "压缩",
            "json格式化", "美化", "壓縮",
            "formater json",
            "JSON整形", "JSONフォーマット"
        ],
        "base64": [
            "base64", "b64", "encode", "decode",
            "base64编码", "base64解码",
            "base64編碼", "base64解碼",
            "base64",
            "Base64エンコード", "Base64デコード"
        ],
        "url": [
            "url encode", "url decode", "percent encode",
            "url编码", "url解码",
            "url編碼", "url解碼",
            "encoder url",
            "URLエンコード", "URLデコード"
        ]
    ]
}
