/*
 * The social media report as a PDF.
 *
 * One function, `render(snapshot)`, draws the whole report from a snapshot
 * of the saved data (the report, its accounts, its posts) and answers the
 * bytes, the page count and any warnings. The snapshot is the database's
 * (`sm_report_snapshot`), so a version drawn today and the same version
 * drawn again next year are the same file; nothing here reads a table.
 *
 * It is drawn with pdf-lib in the browser, like the letters: text stays
 * selectable, the fonts are embedded, every page break is decided here and
 * nothing depends on a print dialog or on the machine it runs on. The
 * portal's hosting (GitHub Pages and Supabase) has no server that can run a
 * browser, so an HTML template rendered server-side is not available; this
 * is the deterministic renderer that is.
 *
 * Three faces and an image: Slate for Latin text, the Chinese face the
 * letters already embed for every glyph Slate lacks, and an emoji drawn by
 * the browser to a canvas and placed as a small image, because no embedded
 * font carries colour emoji. Each character picks its face by whether the
 * face has the glyph, so a caption that mixes English, Chinese, hashtags and
 * emoji is one paragraph and not three.
 */
(function () {
  var ORG = window.ADSPACE_ORG || {};
  var CFG = window.ADSPACE_CONFIG || {};

  // ---- Page geometry ----------------------------------------------------------
  /* Every measurement below is the ADspace Rate Card & Packages template's
     own (v2.0.5, read off the file the user sent on 2026-09-23): a 54pt
     margin, the Optima wordmark and a small capitals label on one line at the
     head, PRIVATE & CONFIDENTIAL over an italic reference line and the page
     count at the foot, the page title in Slate Regular 18pt, all text in the
     one ink #404040. The report is an ADspace document, so it wears the same
     paper as the rate card and the packages. */
  /* 2026-09-25, second revision: the user found the 54pt margin left too
     much white paper, and asked for the margins, the type, the line heights
     and the tables to follow the golden ratio. So every size and every space
     on the page is one step of one scale: 10pt (the body) multiplied by
     √φ, step by step, so that two steps apart is exactly φ.

       S(-2) 6.18  S(-1) 7.86  S(0) 10  S(1) 12.72  S(2) 16.18
       S(3) 20.58  S(4) 26.18  S(5) 33.30  S(6) 42.36

     The margin is S(5), 33.3pt (11.7mm), which widens the text column from
     487pt to 529pt. The head, the foot and the ink stay the rate card's. */
  var W = 595.28, H = 841.89;
  var PHI = 1.6180339887;
  var S = function (k) { return 10 * Math.pow(PHI, k / 2); };
  var M = S(5);                 // 33.3pt on every side
  var R = W - M, CW = R - M;    // the text column: 528.7pt
  var HEAD_Y = H - M - 11.6;    // the wordmark's baseline: its cap height under the top margin
  var TOP = HEAD_Y - S(5);      // the page title's baseline, one margin under the head
  var FOOT_Y = M;               // PRIVATE & CONFIDENTIAL and the page count, on the margin
  var FLOOR = M + S(1) + S(4);  // nothing draws below this; the foot is under it
  // The type roles, each a step of the scale.
  var TY = {
    cover: S(5), coverSub: S(3), coverMeta: S(1),
    title: S(3), block: S(1), lead: S(1), body: S(0), cell: S(0), small: S(-1),
    figure: S(3)
  };
  // The spaces between things, each a step of the scale.
  var SP = { tight: S(-2), line: S(-1), under: S(2), block: S(4) };


  // ---- Chinese -----------------------------------------------------------------
  /* A report whose language is Chinese (`report.lang` 'zh', 2026-10-01)
     prints every heading, label, note and date in professional, client-
     facing Simplified Chinese, written as Chinese and never word for word.
     The team's own words (commentary, captions, ad names) are printed as
     typed. `tr()` answers a fixed English string with its Chinese, at the
     drawing primitives, so the layout code reads the same in both. */
  var ZH = false;
  var ZH_WORDS = {
    'social media accounts report': '社交媒体账号报告',
    'social media advertising report': '社交媒体广告报告',
    'social media report': '社交媒体报告',
    'executive summary': '执行摘要',
    'insights and recommendations': '洞察与建议',
    'insights': '洞察',
    'highlights': '成效亮点',
    'areas to improve': '优化方向',
    'recommendations': '建议',
    'summary': '概要',
    'summary line': '概要',
    'across all platforms': '跨平台总览',
    'key findings': '主要发现',
    'improvements': '优化方向',
    'next steps': '下一步计划',
    'opportunities': '发展机会',
    'performance drivers': '成效驱动因素',
    'what worked': '成效亮点',
    'recommended focus for the following month': '下月工作重点',
    'ad performance': '广告成效',
    'creative performance': '创意成效',
    'results by objective': '各广告目标成效',
    'results by age': '各年龄段成效',
    'audience retention': '观众留存率',
    'hook rate': '吸睛率',
    'hold rate': '持续观看率',
    'average play time': '平均播放时长',
    'amount spent': '广告花费',
    'amount spent *': '广告花费 *',
    'results': '成效',
    'result': '成效',
    'cost per result': '单次成效费用',
    'per 1,000 reached': '千人覆盖费用',
    'cost per 1,000 reached': '千人覆盖费用',
    'reach': '覆盖人数',
    'impressions': '展示次数',
    'frequency': '频次',
    'ctr': '点击率',
    'share of spend': '花费占比',
    'objective': '广告目标',
    'ad': '广告',
    'period': '投放期间',
    'platform': '平台',
    'post': '帖文',
    'posts': '帖文数',
    'posts published': '已发布帖文',
    'rank': '排名',
    'details': '详情',
    'date': '日期',
    'format': '形式',
    'change': '变化',
    'previous period': '上一期',
    'this period': '本期',
    'start of period': '期初',
    'end of period': '期末',
    'growth': '增长',
    'followers': '粉丝数',
    'follower growth': '粉丝增长',
    'account': '账号',
    'engagement rate': '互动率',
    'engagements': '互动次数',
    'interactions': '互动',
    'views': '观看次数',
    'likes': '点赞数',
    'comments': '评论数',
    'shares': '分享数',
    'saves': '收藏数',
    'by platform': '各平台表现',
    'remarks': '点评',
    'how to read this': '阅读说明',
    'how to read the video figures': '视频数据说明',
    'no data.': '暂无数据。',
    'no image': '暂无图片',
    'not available': '暂无数据',
    'other': '其他',
    'total': '总计',
    'private & confidential': '机密文件',
    'leads': '潜在客户',
    'messaging': '私信互动',
    'sales': '销售',
    'traffic': '流量',
    'engagement': '互动',
    'awareness': '品牌认知',
    'app promotion': '应用推广',
    'reel': 'Reels', 'video': '视频', 'photo': '图片', 'carousel': '轮播帖', 'story': '限时动态',
    'live': '直播', 'short': '短视频', 'article': '文章', 'rednote': '小红书',
    'the headline figures for the period, before the detail.': '本期核心数据一览。',
    'what the period’s figures mean, and what happens next.': '本期数据解读与后续计划。',
    'each objective ranked by what a result cost, then each creative with its results across objectives.':
      '各广告目标按单次成效费用排序，随后呈现每个创意在各目标下的成效。',
    'cost per result is what it cost to get one lead, click or action. compare it only between ads with the same objective, which is why each objective is ranked on its own.':
      '单次成效费用指获得一次潜在客户、点击或行动所需的费用。此数据只宜在同一广告目标的广告之间比较，因此每个目标均单独排名。',
    'each ad is priced only against the result its objective was set to get. a leads ad that also started a few chats is judged by its cost per lead; the chats came alongside, and the budget was not spent on them.':
      '每则广告只按其投放目标所设定的成效计算费用。例如潜在客户广告即使同时带来少量对话，仍以单次潜在客户费用评估；这些对话属附带成效，预算并非为其投放。',
    'reach is how many people saw an ad; impressions is how many times it was shown. frequency is impressions divided by reach.':
      '覆盖人数指看过广告的人数；展示次数指广告获得展示的总次数。频次即展示次数除以覆盖人数。',
    'a creative that ran under two objectives shows one line for each. compare the lines to see which goal it served best.':
      '同一创意若在两个广告目标下投放，将各列一行，便于比较该创意最能达成哪一个目标。',
    'hook rate is the share of people who kept watching once the ad appeared. the first seconds decide whether somebody stops or scrolls past, so a strong hook rate means the opening is doing its job, and a low one shows where to sharpen the next creative.':
      '吸睛率指广告出现后继续观看的人数比例。开场几秒决定观众停留还是滑过；吸睛率高代表开场奏效，偏低则说明下一则创意的开场可再加强。',
    'hold rate is the share who kept watching after the opening had caught them: whether the message holds all the way through. a strong hold rate means the content is doing its job; a low one shows where people start to drop off.':
      '持续观看率指被开场吸引后继续观看的人数比例，反映内容能否从头到尾留住观众。持续观看率高代表内容奏效；偏低则显示观众开始流失的位置。',
    'every ad term is explained at go.adspace.me/fb-ad-terms.': '各项广告术语的说明，请参阅 go.adspace.me/fb-ad-terms。',
    'amount spent is the full amount spent on ads. it excludes the 10% wht and 8% sst, charged separately.':
      '广告花费为投放于广告的全部金额，不包括另行收取的10%预扣税（WHT）及8%销售与服务税（SST）。',
    'amount spent is the full amount spent on ads. it excludes the 5% dcc and 9% gst, charged separately.':
      '广告花费为投放于广告的全部金额，不包括另行收取的5%数字服务费（DCC）及9%消费税（GST）。',
    'amount spent is the full amount spent on ads. it excludes the 10% wht and 8% sst on a malaysian ad account, and the 5% dcc and 9% gst on a singapore one, charged separately.':
      '广告花费为投放于广告的全部金额。马来西亚广告账户不包括另行收取的10%预扣税（WHT）及8%销售与服务税（SST）；新加坡广告账户不包括另行收取的5%数字服务费（DCC）及9%消费税（GST）。'
  };
  /* A count reads as Chinese does: the figure, then its measure word. */
  var ZH_COUNT = {
    'leads': '个潜在客户', 'lead': '个潜在客户', 'messages': '次私信对话', 'message': '次私信对话',
    'engagements': '次互动', 'engagement': '次互动', 'interactions': '次交互', 'interaction': '次交互',
    'reactions': '次心情反应', 'reaction': '次心情反应', 'reached': '人覆盖', 'sales': '笔销售', 'sale': '笔销售',
    'conversions': '次转化', 'conversion': '次转化', 'clicks': '次点击', 'click': '次点击',
    'page views': '次页面浏览', 'page view': '次页面浏览', 'thruplays': '次完整播放', 'thruplay': '次完整播放',
    'video plays': '次视频播放', 'video play': '次视频播放', 'installs': '次安装', 'install': '次安装',
    'impressions': '次展示', 'impression': '次展示', 'recall lift': '人广告回想提升',
    'follows': '位新关注', 'follow': '位新关注', 'profile visits': '次主页访问', 'profile visit': '次主页访问',
    'saves': '次收藏', 'save': '次收藏', 'results': '次成效', 'result': '次成效'
  };
  function trWord(w) { var k = String(w).trim().toLowerCase(); return ZH_WORDS[k] || w; }
  var ZH_RULES = [
    [/^Page (\d+) of (\d+)$/, function (m) { return '第 ' + m[1] + ' 页，共 ' + m[2] + ' 页'; }],
    [/^\* ([\s\S]+)$/, function (m) { var t = tr(m[1]); return t !== m[1] ? '* ' + t : null; }],
    [/^([\d,]+(?:\.\d+)?) ([A-Za-z][A-Za-z ]*)$/, function (m) { var w = ZH_COUNT[m[2].toLowerCase()]; return w ? m[1] + ' ' + w : null; }],
    [/^Total (.+)$/, function (m) { var w = trWord(m[1]); return w !== m[1] ? '总' + w : null; }],
    [/^(.+) by week$/, function (m) { return '每周' + trWord(m[1]); }],
    [/^(.+) by post$/, function (m) { return '各帖文' + trWord(m[1]); }],
    [/^Top post by (.+)$/, function (m) { return trWord(m[1]) + '最高的帖文'; }],
    [/^Top (\d+) posts by (.+)$/, function (m) { return trWord(m[2]) + '最高的 ' + m[1] + ' 篇帖文'; }],
    [/^(.+) follower growth$/, function (m) { return trWord(m[1]) + ' 粉丝增长'; }],
    [/^Average (.+)$/, function (m) { return '平均 ' + m[1]; }],
    [/^Appendix: (.+)$/, function (m) { return '附录：' + trWord(m[1]); }],
    [/^Remarks: ([\s\S]+)$/, function (m) { return '点评：' + m[1]; }],
    [/^(.+) spent$/, function (m) { return '花费 ' + m[1]; }],
    [/^(.+) \(cont\.\)$/, function (m) { return tr(m[1]) + '（续）'; }],
    [/^Results by age  ·  (.+)$/, function (m) { return '各年龄段成效  ·  ' + trWord(m[1]); }],
    [/^(.+)  ·  (\d+) ads?  ·  (.+)$/, function (m) { return trWord(m[1]) + '  ·  ' + m[2] + ' 则广告  ·  ' + m[3]; }],
    [/^(.+) per 1,000$/, function (m) { return m[1] + ' / 千人'; }],
    [/^(.+) \/ 1,000$/, function (m) { return m[1] + ' / 千人'; }],
    [/^Previous (.+)$/, function (m) { return '上一期 ' + m[1]; }],
    [/^(.+) audience$/, function (m) { return m[1] + ' 受众'; }]
  ];
  function tr(s) {
    if (!ZH || s == null) return s;
    var str = String(s);
    var k = str.trim().toLowerCase();
    if (ZH_WORDS[k]) return ZH_WORDS[k];
    for (var i = 0; i < ZH_RULES.length; i++) {
      var m = ZH_RULES[i][0].exec(str);
      if (m) { var out = ZH_RULES[i][1](m); if (out != null) return out; }
    }
    return str;
  }
  function zhDay(d, year) { return (year ? d.getFullYear() + '年' : '') + (d.getMonth() + 1) + '月' + d.getDate() + '日'; }
  /* Two dates as one span in Chinese: the year once, the month once where
     it does not change. */
  function zhSpan(da, db) {
    if (da.getFullYear() !== db.getFullYear()) return zhDay(da, true) + '至' + zhDay(db, true);
    if (da.getMonth() !== db.getMonth()) return zhDay(da, true) + '至' + (db.getMonth() + 1) + '月' + db.getDate() + '日';
    return zhDay(da, true) + '至' + db.getDate() + '日';
  }

  // ---- Words ------------------------------------------------------------------
  var PLATFORM_WORD = {
    facebook: 'Facebook', instagram: 'Instagram', tiktok: 'TikTok', rednote: 'rednote', xhs: 'rednote',
    youtube: 'YouTube', linkedin: 'LinkedIn', x: 'X', threads: 'Threads', wechat: 'WeChat', other: 'Other'
  };
  var TYPE_WORD = {
    reel: 'Reel', video: 'Video', post: 'Post', photo: 'Photo', carousel: 'Carousel', story: 'Story',
    live: 'Live', short: 'Short', article: 'Article', other: ''
  };
  var METRIC_WORD = {
    views: 'Views', reach: 'Reach', impressions: 'Impressions', interactions: 'Interactions',
    engagements: 'Engagements', likes: 'Likes', comments: 'Comments', shares: 'Shares', saves: 'Saves'
  };
  var METRICS = ['views', 'reach', 'impressions', 'interactions', 'engagements', 'likes', 'comments', 'shares', 'saves'];
  var VOLUME = ['views', 'reach', 'impressions'];
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  var MON3 = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];

  function num(v) { return v === null || v === undefined || v === '' || isNaN(Number(v)) ? null : Number(v); }
  function fmt(v) {
    var n = num(v);
    if (n === null) return 'Not available';
    return n.toLocaleString('en-GB');
  }
  function signed(n) { n = num(n); if (n === null) return 'Not available'; return (n > 0 ? '+' : '') + n.toLocaleString('en-GB'); }
  function pct(v) { return v === null || v === undefined ? 'Not available' : (Math.round(v * 10000) / 100).toFixed(2) + '%'; }
  function dateOf(s) { var d = new Date(String(s || '').slice(0, 10) + 'T00:00:00'); return isNaN(d.getTime()) ? null : d; }
  function dayWord(s) { var d = dateOf(s); return d ? (ZH ? zhDay(d, true) : d.getDate() + ' ' + MON3[d.getMonth()] + ' ' + d.getFullYear()) : String(s || ''); }
  function longDate(s) { var d = dateOf(s); return d ? (ZH ? zhDay(d, true) : d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear()) : String(s || ''); }
  function stampWord(iso) { var d = iso ? new Date(iso) : null; return d && !isNaN(d.getTime()) ? (ZH ? zhDay(d, true) : d.getDate() + ' ' + MONTHS[d.getMonth()] + ' ' + d.getFullYear()) : ''; }
  /* "August 2026" for a calendar month, "1 to 15 August 2026" for part of one,
     "28 July to 3 August 2026" across two. */
  function periodWord(a, b) {
    var da = dateOf(a), db = dateOf(b);
    if (!da || !db) return '';
    var last = new Date(da.getFullYear(), da.getMonth() + 1, 0).getDate();
    if (ZH) {
      if (da.getMonth() === db.getMonth() && da.getFullYear() === db.getFullYear() && da.getDate() === 1 && db.getDate() === last) {
        return da.getFullYear() + '年' + (da.getMonth() + 1) + '月';
      }
      return zhSpan(da, db);
    }
    if (da.getMonth() === db.getMonth() && da.getFullYear() === db.getFullYear()) {
      if (da.getDate() === 1 && db.getDate() === last) return MONTHS[da.getMonth()] + ' ' + da.getFullYear();
      return da.getDate() + ' to ' + db.getDate() + ' ' + MONTHS[da.getMonth()] + ' ' + da.getFullYear();
    }
    return da.getDate() + ' ' + MONTHS[da.getMonth()] + (da.getFullYear() !== db.getFullYear() ? ' ' + da.getFullYear() : '') +
      ' to ' + db.getDate() + ' ' + MONTHS[db.getMonth()] + ' ' + db.getFullYear();
  }
  function hexRgb(PDF, hex, fallback) {
    var m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim());
    if (!m) return fallback;
    var v = parseInt(m[1], 16);
    return PDF.rgb(((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255);
  }
  function mix(PDF, c, white) {
    return PDF.rgb(c.red + (1 - c.red) * white, c.green + (1 - c.green) * white, c.blue + (1 - c.blue) * white);
  }
  function words(s) { return String(s == null ? '' : s).replace(/\r/g, ''); }
  /* Ads Manager's result indicator is a key (`actions:post_engagement`,
     `onsite_conversion.messaging_conversation_started_7d`); a report reads
     the word for it. A label somebody typed is left as typed, except Post
     engagements, which a client reads as Engagements (the user, 2026-10-01). */
  var RESULT_KEY = [
    [/post_engagement$/, 'Engagements'], [/page_engagement$/, 'Page engagements'], [/post_reaction$/, 'Post reactions'],
    [/(^|[:.])like$/, 'Page likes'], [/link_click$/, 'Link clicks'], [/landing_page_view$/, 'Landing page views'],
    [/messaging_conversation_started/, 'Messaging conversations started'], [/messaging_first_reply/, 'New messaging contacts'],
    [/lead/, 'Leads'], [/purchase/, 'Purchases'], [/add_to_cart/, 'Adds to cart'], [/complete_registration/, 'Registrations completed'],
    [/thruplay/, 'ThruPlays'], [/video_view/, '3-second video plays'], [/estimated_ad_recall/, 'Ad recall lift'],
    [/app_install/, 'App installs'], [/post_save/, 'Post saves'], [/profile_visit/, 'Profile visits'],
    [/(^|[:.])reach$/, 'Reach'], [/(^|[:.])impressions$/, 'Impressions']
  ];
  /* The team's code at the end of an ad's name (`_222`, the person who
     built it) is the team's: a report reads the name without it. */
  function adName(s) { return String(s == null ? '' : s).trim().replace(/[\s_-]+(\d)\1\1$/, ''); }
  function resultWord(s) {
    var t = String(s == null ? '' : s).trim();
    if (/^post engagements?$/i.test(t)) return 'Engagements';
    if (!t || /\s/.test(t) || !/[:._]/.test(t)) return t;
    var k = t.toLowerCase();
    for (var i = 0; i < RESULT_KEY.length; i++) if (RESULT_KEY[i][0].test(k)) return RESULT_KEY[i][1];
    var w = k.replace(/^actions:/, '').replace(/^(onsite_conversion|offsite_conversion)\./, '').replace(/^fb_pixel_/, '')
      .replace(/^omni_/, '').replace(/_\d+d$/, '').replace(/[._:]+/g, ' ').trim();
    return w ? w.charAt(0).toUpperCase() + w.slice(1) : t;
  }
  /* In a table a result reads as a count and one short word (the user,
     2026-10-01): 47 Leads, 15 Messages, 84,660 Reached; never Ads
     Manager's long name, which broke inside a word in a narrow column. */
  var SHORT_RESULT = [
    [/engag/i, 'Engagements'], [/interaction/i, 'Interactions'], [/reaction/i, 'Reactions'], [/reach/i, 'Reached'], [/lead/i, 'Leads'],
    [/messag|conversation|contact/i, 'Messages'], [/purchase|sale/i, 'Sales'],
    [/conversion|registration|to cart|checkout/i, 'Conversions'], [/landing page/i, 'Page views'],
    [/click/i, 'Clicks'], [/thruplay/i, 'ThruPlays'], [/video play|3-second/i, 'Video plays'],
    [/install/i, 'Installs'], [/impression/i, 'Impressions'], [/recall/i, 'Recall lift'],
    [/like|follow/i, 'Follows'], [/profile visit/i, 'Profile visits'], [/save/i, 'Saves']
  ];
  function shortResult(s) {
    var t = resultWord(s);
    for (var i = 0; i < SHORT_RESULT.length; i++) if (SHORT_RESULT[i][0].test(t)) return SHORT_RESULT[i][1];
    return t.replace(/\s*\([^)]*\)\s*$/, '') || 'Results';
  }
  /* One point a line: an insights field holds several, one per line, and a
     line that is only whitespace is not a point. Accidental repeated blank
     lines are collapsed; a single blank line still divides two points. */
  function points(s) {
    return words(s).split(/\n/).map(function (l) { return l.trim(); }).filter(Boolean);
  }
  /* A caption keeps its paragraphs exactly, collapsing only a run of three or
     more line breaks (two or more empty lines) to one paragraph break. */
  function paragraphsOf(s) {
    var t = words(s).replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n');
    return t.split('\n');
  }

  // ---- The model: what the numbers say ---------------------------------------
  function engOf(p) { var e = num(p.engagements); if (e !== null) return e; return num(p.interactions); }
  function growthOf(a) {
    var o = num(a.growth_override);
    if (o !== null) return o;
    var s = num(a.followers_start), e = num(a.followers_end);
    return s !== null && e !== null ? e - s : null;
  }
  function sumOf(rows, f) {
    var any = false, t = 0;
    rows.forEach(function (r) { var v = f(r); if (v !== null && v !== undefined) { any = true; t += v; } });
    return any ? t : null;
  }
  function metricsOf(acc, posts) {
    var m = (acc.metrics || []).filter(function (k) { return METRICS.indexOf(k) > -1; });
    if (m.length) return m;
    /* None stated: the metrics the posts actually carry, in the canonical order. */
    return METRICS.filter(function (k) { return posts.some(function (p) { return num(p[k]) !== null; }); });
  }
  function volumeMetric(metrics) {
    for (var i = 0; i < VOLUME.length; i++) if (metrics.indexOf(VOLUME[i]) > -1) return VOLUME[i];
    return null;
  }
  function engMetric(metrics) {
    if (metrics.indexOf('engagements') > -1) return 'engagements';
    if (metrics.indexOf('interactions') > -1) return 'interactions';
    return null;
  }
  function byPost(a, b) {
    var da = String(a.posted_on || ''), db = String(b.posted_on || '');
    if (da !== db) return da < db ? -1 : 1;
    return (Number(a.position) || 0) - (Number(b.position) || 0);
  }
  /* Accounts reported together (Facebook and Instagram, as Meta reports
     cross-posted content) are one group with both accounts' follower figures
     and one set of posts; an account on its own is a group of one. */
  function model(snap) {
    var rep = snap.report || {};
    var accs = (snap.platforms || []).slice().sort(function (a, b) { return (Number(a.position) || 0) - (Number(b.position) || 0); });
    var posts = (snap.posts || []).slice().sort(byPost);
    var groups = [], byKey = {};
    accs.forEach(function (a) {
      var key = a.group_key || ('acc:' + a.id);
      var g = byKey[key];
      if (!g) {
        g = { key: key, accounts: [], posts: [], label: a.group_label || PLATFORM_WORD[a.platform] || a.platform };
        byKey[key] = g; groups.push(g);
      }
      g.accounts.push(a);
    });
    posts.forEach(function (p) {
      var a = accs.filter(function (x) { return x.id === p.platform_id; })[0];
      var key = a ? (a.group_key || ('acc:' + a.id)) : null;
      var g = key && byKey[key];
      if (g) { p._group = g; g.posts.push(p); }
    });
    var rank = rep.rank_metric || 'views';
    groups.forEach(function (g) {
      var lead = g.accounts[0];
      g.metrics = metricsOf(lead, g.posts);
      g.volume = volumeMetric(g.metrics);
      g.engKey = engMetric(g.metrics);
      g.views = g.volume ? sumOf(g.posts, function (p) { return num(p[g.volume]); }) : null;
      g.eng = sumOf(g.posts, engOf);
      g.growth = sumOf(g.accounts, growthOf);
      g.basis = (g.accounts.filter(function (a) { return a.er_basis; })[0] || {}).er_basis || null;
      var denom = null;
      if (g.basis === 'followers') denom = sumOf(g.accounts, function (a) { return num(a.followers_end); });
      else if (g.basis) denom = sumOf(g.posts, function (p) { return num(p[g.basis]); });
      g.er = (g.basis && denom && g.eng !== null) ? g.eng / denom : null;
      g.rank = lead.rank_metric || rank;
      var withVol = g.posts.filter(function (p) { return g.volume && num(p[g.volume]) !== null; });
      g.mostViewed = withVol.slice().sort(function (a, b) { return num(b[g.volume]) - num(a[g.volume]); }).slice(0, 3);
      var withEng = g.posts.filter(function (p) { return engOf(p) !== null; });
      g.mostEngaged = withEng.slice().sort(function (a, b) { return engOf(b) - engOf(a); }).slice(0, 3);
      g.summary = (g.accounts.filter(function (a) { return words(a.summary).trim(); })[0] || {}).summary || '';
      g.worked = g.accounts.map(function (a) { return a.worked; }).filter(function (s) { return words(s).trim(); }).join('\n');
      g.improve = g.accounts.map(function (a) { return a.improve; }).filter(function (s) { return words(s).trim(); }).join('\n');
      g.actions = g.accounts.map(function (a) { return a.actions; }).filter(function (s) { return words(s).trim(); }).join('\n');
      g.notes = g.accounts.map(function (a) { return a.metric_notes; }).filter(function (s) { return words(s).trim(); }).join(' ');
    });
    var rankOf = function (p) { return rank === 'engagements' || rank === 'interactions' ? engOf(p) : num(p[rank]); };
    var ranked = posts.filter(function (p) { return p._group && rankOf(p) !== null; })
      .sort(function (a, b) { return rankOf(b) - rankOf(a); });
    var totals = {
      posts: posts.filter(function (p) { return p._group; }).length,
      growth: sumOf(groups, function (g) { return g.growth; }),
      views: sumOf(groups, function (g) { return g.views; }),
      eng: sumOf(groups, function (g) { return g.eng; }),
      volumeWords: uniq(groups.map(function (g) { return g.volume ? METRIC_WORD[g.volume] : null; }).filter(Boolean)),
      engWords: uniq(groups.map(function (g) { return g.engKey ? METRIC_WORD[g.engKey] : null; }).filter(Boolean)),
      er: null, basis: null
    };
    var bases = uniq(groups.map(function (g) { return g.basis; }).filter(Boolean));
    if (bases.length === 1 && groups.every(function (g) { return g.er !== null; })) {
      var e = 0, d = 0;
      groups.forEach(function (g) { e += g.eng; d += g.eng / g.er; });
      totals.er = d ? e / d : null; totals.basis = bases[0];
    }
    return { rep: rep, accounts: accs, posts: posts, groups: groups, totals: totals, rank: rank, rankOf: rankOf,
             ads: (snap.ads || []).slice(), adsm: adsModel(snap),
             best: ranked[0] || null, top: ranked.slice(0, 5),
             mostEngaged: posts.filter(function (p) { return engOf(p) !== null; }).sort(function (a, b) { return engOf(b) - engOf(a); })[0] || null };
  }
  function uniq(a) { var o = []; a.forEach(function (x) { if (o.indexOf(x) < 0) o.push(x); }); return o; }
  /* A platform's best posts, ranked on that platform alone by its own
     figure (its rank metric, else its volume): a post is never ranked
     against another platform's, whose reach works differently. The PDF and
     the Commentary step both ask this. */
  function topOf(g, n) {
    var key = g.rank === 'engagements' || g.rank === 'interactions' ? null : g.rank;
    var rankIn = function (p) {
      var v = key ? num(p[key]) : engOf(p);
      if (v === null && g.volume) v = num(p[g.volume]);
      return v;
    };
    return g.posts.filter(function (p) { return rankIn(p) !== null; })
      .sort(function (a, b) { return rankIn(b) - rankIn(a); }).slice(0, n || 3);
  }

  /* ---- The advertising report ------------------------------------------------
     One row an ad and objective. What a row cannot say is the account's own:
     reach counts a person once across every ad they saw, so the period's
     reach is typed and never added up; impressions and spend add up and are
     summed where nobody typed them. The objectives read in the order a
     client values them, results first and reach last. */
  var OBJECTIVES = {
    leads: { name: 'Leads', result: 'Leads', order: 1 },
    messaging: { name: 'Messaging', result: 'Conversations', order: 2 },
    sales: { name: 'Sales', result: 'Purchases', order: 3 },
    traffic: { name: 'Traffic', result: 'Link clicks', order: 4 },
    engagement: { name: 'Engagement', result: 'Engagements', order: 5 },
    awareness: { name: 'Awareness', result: 'Reach', order: 6 },
    app: { name: 'App promotion', result: 'Installs', order: 7 }
  };
  var AGE_BANDS = ['18-24', '25-34', '35-44', '45-54', '55-64', '65+'];
  var RETENTION = [['p25', '25%'], ['p50', '50%'], ['p75', '75%'], ['p95', '95%'], ['p100', '100%']];
  function adsModel(snap) {
    var rep = snap.report || {};
    var T0 = rep.ads_totals || {};
    var ads = (snap.ads || []).slice().sort(function (a, b) {
      var oa = (OBJECTIVES[a.objective] || { order: 9 }).order, ob = (OBJECTIVES[b.objective] || { order: 9 }).order;
      return oa - ob || (Number(a.position) || 0) - (Number(b.position) || 0);
    });
    ads.forEach(function (a) {
      var sp = num(a.spend), rs = num(a.results), rc = num(a.reach), im = num(a.impressions);
      /* The cost per result as Ads Manager prints it, where it was typed;
         worked out otherwise. A reach result is priced per 1,000 people, as
         Ads Manager prices it, or every awareness ad reads RM 0.00. */
      a._per1000 = a.cpr_basis === 'thousand' || (a.cpr_basis !== 'result' && /reach/i.test(words(a.result_label)));
      a._cpr = num(a.cpr) !== null ? num(a.cpr)
        : a._per1000 ? (sp !== null && (/reach/i.test(words(a.result_label)) ? rs : rc) ? sp / (/reach/i.test(words(a.result_label)) ? rs : rc) * 1000 : null)
        : (sp !== null && rs ? sp / rs : null);
      a._freq = rc && im !== null ? im / rc : null;
      a._label = resultWord(words(a.result_label)) || (OBJECTIVES[a.objective] || {}).result || 'Results';
      var ret = a.retention || {};
      a._video = [a.hook_rate, a.hold_rate, a.avg_play].some(function (v) { return num(v) !== null; }) ||
        RETENTION.some(function (r) { return num(ret[r[0]]) !== null; });
      var age = a.age || {};
      a._age = AGE_BANDS.some(function (b) { return num(age[b]) !== null; });
    });
    var spendAll = sumOf(ads, function (a) { return num(a.spend); });
    var groups = [];
    Object.keys(OBJECTIVES).sort(function (x, y) { return OBJECTIVES[x].order - OBJECTIVES[y].order; }).forEach(function (k) {
      var list = ads.filter(function (a) { return a.objective === k; });
      if (!list.length) return;
      var over = (T0.groups || {})[k] || {};
      var labels = uniq(list.map(function (a) { return a._label; }));
      var g = { key: k, name: OBJECTIVES[k].name, ads: list, adLabel: labels.length === 1 ? labels[0] : 'Results',
        label: words(over.label).trim() || (labels.length === 1 ? labels[0] : 'Results'),
        spend: sumOf(list, function (a) { return num(a.spend); }),
        results: num(over.results) !== null ? num(over.results) : sumOf(list, function (a) { return num(a.results); }) };
      g.per1000 = /reach/i.test(g.label);
      g.cpr = g.spend !== null && g.results ? g.spend / g.results * (g.per1000 ? 1000 : 1) : null;
      g.share = spendAll ? (g.spend || 0) / spendAll : null;
      var pg = (T0.prev_groups || {})[k];
      if (pg) {
        g.prevSpend = num(pg.spend); g.prevResults = num(pg.results);
        g.prevCpr = g.prevSpend !== null && g.prevResults ? g.prevSpend / g.prevResults * (g.per1000 ? 1000 : 1) : null;
      }
      groups.push(g);
    });
    var t = {
      reach: num(T0.reach),
      impressions: num(T0.impressions) !== null ? num(T0.impressions) : sumOf(ads, function (a) { return num(a.impressions); }),
      spend: num(T0.spend) !== null ? num(T0.spend) : spendAll,
      prevStart: T0.prev_start || null, prevEnd: T0.prev_end || null,
      prevReach: num(T0.prev_reach), prevImpressions: num(T0.prev_impressions), prevSpend: num(T0.prev_spend)
    };
    t.freq = t.reach && t.impressions !== null ? t.impressions / t.reach : null;
    t.prevFreq = t.prevReach && t.prevImpressions !== null ? t.prevImpressions / t.prevReach : null;
    t.hasPrev = !rep.first_month && [t.prevReach, t.prevImpressions, t.prevSpend].some(function (v) { return v !== null; });
    return { ads: ads, groups: groups, totals: t, first: !!rep.first_month };
  }
  /* A point a line; a line indented, or opening with a dash or a letter and
     a stop, belongs to the point above it, so the team's own lettered
     sub-points come out as sub-points. */
  function pointTree(s) {
    var out = [];
    words(s).split('\n').forEach(function (raw) {
      if (!raw.trim()) return;
      var sub = /^\s+\S/.test(raw) || /^\s*[-–•]\s+/.test(raw) || /^\s*[a-z][.)]\s+/.test(raw);
      var txt = raw.trim().replace(/^[-–•]\s+/, '').replace(/^[a-z][.)]\s+/, '').replace(/^\d+[.)]\s+/, '');
      if (sub && out.length) out[out.length - 1].sub.push(txt);
      else out.push({ t: txt, sub: [] });
    });
    return out;
  }
  function listWords(items) {
    if (!items.length) return '';
    if (items.length === 1) return items[0];
    var own = items.some(function (s) { return / and /.test(s); });
    return items.slice(0, -1).join(', ') + (own ? ', and ' : ' and ') + items[items.length - 1];
  }

  // ---- Assets -----------------------------------------------------------------
  var bytesCache = {};
  function fetchBytes(url) {
    if (!url) return Promise.reject(new Error('none'));
    if (bytesCache[url]) return bytesCache[url];
    bytesCache[url] = fetch(url, { mode: 'cors' }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.arrayBuffer();
    });
    bytesCache[url].catch(function () { delete bytesCache[url]; });
    return bytesCache[url];
  }
  function isJpeg(u8) { return u8.length > 3 && u8[0] === 0xff && u8[1] === 0xd8 && u8[2] === 0xff; }
  function isPng(u8) { return u8.length > 8 && u8[0] === 0x89 && u8[1] === 0x50 && u8[2] === 0x4e && u8[3] === 0x47; }
  /* Any image the browser can decode becomes a PNG at up to 1400px on its long
     side, which keeps print quality at the sizes this report draws while a
     phone photo of four thousand pixels does not make a forty megabyte file. A
     JPEG or PNG within that size is embedded as it is. */
  function embedImage(pdf, url, warn) {
    if (!url) return Promise.resolve(null);
    return fetchBytes(url).then(function (buf) {
      var u8 = new Uint8Array(buf);
      var big = u8.length > 2.5e6;
      if (isJpeg(u8) && !big) return pdf.embedJpg(u8).catch(function () { return viaCanvas(pdf, buf); });
      if (isPng(u8) && !big) return pdf.embedPng(u8).catch(function () { return viaCanvas(pdf, buf); });
      return viaCanvas(pdf, buf);
    }).catch(function (e) {
      if (warn) warn('An image could not be loaded: ' + url.split('?')[0].split('/').pop() + ' (' + ((e && e.message) || e) + ').');
      return null;
    });
  }
  function viaCanvas(pdf, buf) {
    if (typeof createImageBitmap !== 'function') return Promise.reject(new Error('unsupported image'));
    return createImageBitmap(new Blob([buf])).then(function (bmp) {
      var max = 1400, s = Math.min(1, max / Math.max(bmp.width, bmp.height));
      var c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(bmp.width * s)); c.height = Math.max(1, Math.round(bmp.height * s));
      c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
      return new Promise(function (ok, bad) {
        c.toBlob(function (b) { if (!b) { bad(new Error('encode')); return; } b.arrayBuffer().then(function (ab) { ok(pdf.embedPng(new Uint8Array(ab))); }, bad); }, 'image/png');
      });
    });
  }

  // ---- Text: three faces and an image -----------------------------------------
  function hasGlyph(pdfFont, cp) {
    if (!pdfFont) return false;
    var f = pdfFont.embedder && pdfFont.embedder.font;
    if (f && typeof f.hasGlyphForCodePoint === 'function') return f.hasGlyphForCodePoint(cp);
    return cp >= 0x20 && cp <= 0x7e;   // a standard font: ASCII only
  }
  function isEmojiCp(cp) {
    return (cp >= 0x1f000 && cp <= 0x1faff) || (cp >= 0x2600 && cp <= 0x27bf) || (cp >= 0x2b00 && cp <= 0x2bff) ||
      cp === 0x3030 || cp === 0x303d || cp === 0x3297 || cp === 0x3299 || cp === 0x00a9 || cp === 0x00ae ||
      cp === 0x2122 || cp === 0x2139 || (cp >= 0x2194 && cp <= 0x21aa) || cp === 0x231a || cp === 0x231b ||
      cp === 0x2328 || cp === 0x23cf || (cp >= 0x23e9 && cp <= 0x23fa) || cp === 0x24c2 || cp === 0x25aa ||
      cp === 0x25ab || cp === 0x25b6 || cp === 0x25c0 || (cp >= 0x25fb && cp <= 0x25fe);
  }
  function isEmojiJoiner(cp) {
    return cp === 0x200d || cp === 0xfe0f || cp === 0xfe0e || cp === 0x20e3 || (cp >= 0x1f3fb && cp <= 0x1f3ff) ||
      (cp >= 0xe0020 && cp <= 0xe007f);
  }
  function isRegional(cp) { return cp >= 0x1f1e6 && cp <= 0x1f1ff; }
  function isCjkCp(cp) {
    return (cp >= 0x2e80 && cp <= 0x9fff) || (cp >= 0xac00 && cp <= 0xd7af) || (cp >= 0xf900 && cp <= 0xfaff) ||
      (cp >= 0xff00 && cp <= 0xffef) || (cp >= 0x3000 && cp <= 0x303f) || (cp >= 0x20000 && cp <= 0x2fa1f);
  }
  /* A caption is walked code point by code point into atoms: a run of Latin
     that only breaks at a space or inside a long token, one Chinese character
     (Chinese breaks anywhere), one emoji cluster (a base, its skin tone, its
     joiners and what they join), or a space. Each atom knows which face
     draws it and how wide it is. */
  function Shaper(PDF, pdf, fonts, warn) {
    var emojiCache = {};
    var pending = [];
    function cps(s) {
      var out = [];
      for (var i = 0; i < s.length; i++) {
        var c = s.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
          var d = s.charCodeAt(i + 1);
          if (d >= 0xdc00 && d <= 0xdfff) { out.push(((c - 0xd800) << 10) + (d - 0xdc00) + 0x10000); i++; continue; }
        }
        out.push(c);
      }
      return out;
    }
    function ch(cp) { return String.fromCodePoint(cp); }
    /* Which face draws a code point: Slate where it has the glyph, the Chinese
       face where Slate does not, and an image where neither does. */
    function faceOf(cp, face) {
      if (cp === 0xfe0f || cp === 0xfe0e || cp === 0x200d) return null;   // invisible on their own
      if (hasGlyph(face, cp) && !(isEmojiCp(cp) && cp > 0x2000)) return face;
      if (fonts.cjk && hasGlyph(fonts.cjk, cp) && !isEmojiCp(cp)) return fonts.cjk;
      return 'emoji';
    }
    /* An emoji drawn by the browser at 96px and kept once per cluster. The
       canvas is measured for its ink so a wide flag and a narrow heart each
       take the room they need. */
    function emojiImage(text) {
      if (emojiCache[text]) return emojiCache[text];
      var entry = { img: null, ratio: 1, ok: false };
      emojiCache[text] = entry;
      try {
        var size = 96, pad = 12;
        var c = document.createElement('canvas');
        c.width = size * 2; c.height = size + pad * 2;
        var x = c.getContext('2d');
        x.font = (size - pad) + 'px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji","Twemoji Mozilla",sans-serif';
        x.textBaseline = 'top';
        x.fillText(text, pad, pad);
        var d = x.getImageData(0, 0, c.width, c.height).data;
        var minx = c.width, maxx = -1, miny = c.height, maxy = -1;
        for (var yy = 0; yy < c.height; yy++) for (var xx = 0; xx < c.width; xx++) {
          if (d[(yy * c.width + xx) * 4 + 3] > 8) { if (xx < minx) minx = xx; if (xx > maxx) maxx = xx; if (yy < miny) miny = yy; if (yy > maxy) maxy = yy; }
        }
        if (maxx < 0) return entry;
        var cw = maxx - minx + 1, chh = maxy - miny + 1;
        var o = document.createElement('canvas');
        o.width = cw; o.height = chh;
        o.getContext('2d').drawImage(c, minx, miny, cw, chh, 0, 0, cw, chh);
        entry.ratio = cw / chh;
        entry.ok = true;
        pending.push(new Promise(function (ok) {
          o.toBlob(function (b) {
            if (!b) { entry.ok = false; ok(); return; }
            b.arrayBuffer().then(function (ab) {
              return pdf.embedPng(new Uint8Array(ab)).then(function (img) { entry.img = img; ok(); });
            }).catch(function () { entry.ok = false; ok(); });
          }, 'image/png');
        }));
      } catch (e) { entry.ok = false; }
      return entry;
    }
    /* A run's width at a size: text through its face, an emoji by its ratio. */
    function runWidth(run, size) {
      if (run.f === 'emoji') return run.ok ? size * 1.06 * run.ratio + size * 0.12 : size * 1.1;
      return run.font.widthOfTextAtSize(run.s, size);
    }
    function atomsOf(text, face) {
      var list = cps(words(text).replace(/\t/g, ' '));
      var atoms = [];
      var cur = null;    // the Latin atom being built
      var flush = function () { if (cur) { atoms.push(cur); cur = null; } };
      var latinRun = function (font) {
        if (!cur) cur = { runs: [], space: false, brk: false };
        var last = cur.runs[cur.runs.length - 1];
        if (!last || last.font !== font) { last = { f: 'text', font: font, s: '' }; cur.runs.push(last); }
        return last;
      };
      for (var i = 0; i < list.length; i++) {
        var cp = list[i];
        if (cp === 0x20 || cp === 0xa0 || cp === 0x3000) { flush(); atoms.push({ runs: [{ f: 'text', font: face, s: ' ' }], space: true, brk: true }); continue; }
        if (cp < 0x20) continue;
        var f = faceOf(cp, face);
        if (f === null) continue;
        if (f === 'emoji' || (isRegional(cp))) {
          /* Gather the cluster: joiners, modifiers, a second regional indicator,
             and whatever a zero-width joiner joins. */
          var s = ch(cp), j = i + 1;
          if (isRegional(cp) && j < list.length && isRegional(list[j])) { s += ch(list[j]); j++; }
          while (j < list.length) {
            var n = list[j];
            if (isEmojiJoiner(n)) { s += ch(n); j++; if (n === 0x200d && j < list.length) { s += ch(list[j]); j++; } continue; }
            break;
          }
          i = j - 1;
          var e = emojiImage(s);
          flush();
          atoms.push({ runs: [{ f: 'emoji', s: s, entry: e, ok: e.ok, ratio: e.ratio }], space: false, brk: true });
          if (!e.ok && warn) warn('An emoji could not be drawn: ' + s);
          continue;
        }
        if (f === fonts.cjk && isCjkCp(cp)) {
          /* One character an atom; a closing punctuation mark stays with the
             character before it. */
          var punct = /[、。，．：；？！」』】〕）’”]/.test(ch(cp));
          if (punct && atoms.length && !cur && !atoms[atoms.length - 1].space) {
            atoms[atoms.length - 1].runs.push({ f: 'text', font: f, s: ch(cp) });
            continue;
          }
          flush();
          atoms.push({ runs: [{ f: 'text', font: f, s: ch(cp) }], space: false, brk: true });
          continue;
        }
        var r = latinRun(f);
        r.s += ch(cp);
        /* Inside a long token a break is allowed after a slash, a hyphen and
           the marks a web address is built from, so a link wraps at a
           sensible place rather than being cut mid word. */
        if (/[\/\-?&=.,;:!]/.test(ch(cp)) && i + 1 < list.length && list[i + 1] !== 0x20 &&
            !(/[.,]/.test(ch(cp)) && list[i + 1] >= 0x30 && list[i + 1] <= 0x39)) {   // never inside 4,381 or 0.62
          cur.brk = true; flush();
        }
      }
      flush();
      atoms.forEach(function (a) {
        a.w = function (size) { return a.runs.reduce(function (t, r) { return t + runWidth(r, size); }, 0); };
      });
      return atoms;
    }
    /* Greedy line filling, with an atom wider than the line cut by character. */
    function linesOf(text, max, size, face) {
      var atoms = atomsOf(text, face);
      var lines = [], line = [], lw = 0;
      var push = function () { while (line.length && line[line.length - 1].space) line.pop(); lines.push(line); line = []; lw = 0; };
      for (var i = 0; i < atoms.length; i++) {
        var a = atoms[i], w = a.w(size);
        if (a.space && !line.length) continue;
        if (lw + w <= max + 0.01 || !line.length && w <= max) { line.push(a); lw += w; continue; }
        if (w > max) {
          /* Cut the long token where it stops fitting, run by run. */
          var parts = splitAtom(a, max - (line.length ? lw : 0), max, size);
          if (parts.head) { line.push(parts.head); }
          push();
          parts.rest.forEach(function (p, k) { if (k < parts.rest.length - 1) { lines.push([p]); } else { line = [p]; lw = p.w(size); } });
          continue;
        }
        push();
        line.push(a); lw = w;
      }
      if (line.length) push();
      if (!lines.length) lines.push([]);
      return lines;
    }
    function splitAtom(a, first, max, size) {
      var out = { head: null, rest: [] };
      var chunks = [];
      a.runs.forEach(function (r) {
        if (r.f === 'emoji') { chunks.push({ runs: [r] }); return; }
        cps(r.s).forEach(function (cp) { chunks.push({ runs: [{ f: 'text', font: r.font, s: ch(cp) }] }); });
      });
      var mk = function (rs) { var x = { runs: rs, space: false, brk: true }; x.w = function (sz) { return rs.reduce(function (t, r) { return t + runWidth(r, sz); }, 0); }; return x; };
      var cur = [], curW = 0, limit = first > size ? first : 0, started = false;
      chunks.forEach(function (c) {
        var w = runWidth(c.runs[0], size);
        var cap = started ? max : (limit || max);
        if (curW + w > cap && cur.length) {
          if (!started && limit) { out.head = mk(cur); } else { out.rest.push(mk(cur)); }
          started = true; cur = []; curW = 0;
        }
        cur.push(c.runs[0]); curW += w;
      });
      if (cur.length) { if (!started && limit) out.head = mk(cur); else out.rest.push(mk(cur)); }
      if (!out.rest.length && out.head) { out.rest.push(out.head); out.head = null; }
      return out;
    }
    function lineWidth(line, size) { return line.reduce(function (t, a) { return t + a.w(size); }, 0); }
    function draw(page, line, x, y, size, color) {
      var cx = x;
      line.forEach(function (a) {
        a.runs.forEach(function (r) {
          var w = runWidth(r, size);
          if (r.f === 'emoji') {
            if (r.entry && r.entry.img) {
              var h = size * 1.06, ww = h * r.entry.ratio;
              page.drawImage(r.entry.img, { x: cx + size * 0.06, y: y - size * 0.22, width: ww, height: h });
            }
          } else if (r.s) {
            page.drawText(r.s, { x: cx, y: y, size: size, font: r.font, color: color });
          }
          cx += w;
        });
      });
    }
    return { linesOf: linesOf, lineWidth: lineWidth, draw: draw, ready: function () { return Promise.all(pending); } };
  }

  // ---- Rendering ---------------------------------------------------------------
  function render(snap, opts) {
    opts = opts || {};
    var PDF = window.PDFLib;
    var DOCS = window.ADspaceDocs;
    if (!PDF) return Promise.reject(new Error('PDF library not loaded'));
    if (!DOCS) return Promise.reject(new Error('The document engine (js/documents.js) is not loaded'));
    var warnings = [];
    var warn = function (s) { if (warnings.indexOf(s) < 0) warnings.push(s); };
    ZH = ((snap && snap.report) || {}).lang === 'zh';
    var mdl = model(snap);
    var rep = mdl.rep;
    var everyText = [rep.title, rep.intro, rep.headline, rep.client_name].concat(
      Object.keys(rep.insights || {}).map(function (k) { return rep.insights[k]; }),
      mdl.accounts.map(function (a) { return [a.account_name, a.summary, a.worked, a.improve, a.actions, a.metric_notes].join(' '); }),
      mdl.posts.map(function (p) { return [p.title, p.caption, p.observation, p.notable, p.theme].join(' '); }),
      mdl.ads.map(function (a) { return [adName(a.name), a.result_label, a.audience, a.remark].join(' '); })).join(' ');
    var needsCjk = ZH || /[⺀-鿿가-힯豈-﫿＀-￯]/.test(everyText);
    var pdf, fonts, logo, sh;
    return PDF.PDFDocument.create().then(function (p) {
      pdf = p;
      return Promise.all([DOCS.embedFonts(pdf, PDF, { cjk: needsCjk }), DOCS.embedLogo(pdf)]);
    }).then(function (got) {
      fonts = got[0]; logo = got[1];
      if (needsCjk && !fonts.cjk) {
        throw new Error('The Chinese font could not be loaded, so the Chinese text in this report cannot be drawn. Check fontCjk in js/config.js.');
      }
      sh = Shaper(PDF, pdf, fonts, warn);
      /* Every fixed English string reaches the page through here, so a
         Chinese report reads Chinese without the layout knowing. */
      if (ZH) { var lo = sh.linesOf; sh.linesOf = function (str, w, size, f) { return lo.call(sh, tr(str), w, size, f); }; }
      /* Every emoji the report holds is drawn and embedded before any page
         is laid out: the pages are drawn in one pass, and an emoji still on
         its way left a blank where it belonged (the user, 2026-10-01). */
      sh.linesOf(everyText, 1e6, 10, fonts.font);
      var thumbJobs = {};
      mdl.posts.concat(mdl.ads).forEach(function (p) {
        var u = p.thumb_url || p.thumb_signed_url || null;
        if (u) thumbJobs[p.id] = embedImage(pdf, u, warn);
      });
      var logoJob = rep.client_logo_url ? embedImage(pdf, rep.client_logo_url, null) : Promise.resolve(null);
      return Promise.all([Promise.all(Object.keys(thumbJobs).map(function (id) { return thumbJobs[id].then(function (img) { return [id, img]; }); })), logoJob, sh.ready()]);
    }).then(function (got) {
      var thumbs = {};
      got[0].forEach(function (pair) { thumbs[pair[0]] = pair[1]; });
      var clientLogo = got[1];
      return draw(PDF, pdf, fonts, logo, clientLogo, sh, mdl, thumbs, warn, opts).then(function (pages) {
        return sh.ready().then(function () {
          ZH = false;
          pdf.setTitle(String(rep.client_name || '') + ' ' + titleOf(rep) + ' ' + periodWord(rep.period_start, rep.period_end));
          pdf.setAuthor(CFG.agencyName || 'ADspace');
          pdf.setSubject(rep.kind === 'ads' ? 'Social Media Advertising Report' : 'Social Media Accounts Report');
          pdf.setCreator('ADspace Digital Portal');
          pdf.setProducer('ADspace Digital Portal');
          return pdf.save({ useObjectStreams: true }).then(function (bytes) {
            return { bytes: bytes, pages: pages, warnings: warnings };
          });
        });
      });
    }).then(function (out) { ZH = false; return out; }, function (e) { ZH = false; throw e; });
  }

  function draw(PDF, pdf, fonts, logo, clientLogo, sh, mdl, thumbs, warn, opts) {
    var rep = mdl.rep;
    var book = fonts.font, reg = fonts.bold, med = fonts.med || reg, mark = fonts.mark || med;
    /* Monochrome, on the rate card's own values: one ink for every word and
       every mark that carries a value, the rate card's two table greys for
       structure, and two lighter greys for the marks that are only context.
       Nothing on the page is coloured. */
    var g = function (v) { return PDF.rgb(v, v, v); };
    var INK = g(0.251);            // #404040, the rate card's one ink
    var SOFT = g(0.40);            // secondary text: captions, dates
    var MUTE = g(0.45);            // axis labels, notes
    var FILL = g(0.949);           // #f2f2f2: header row, label column, cell edges
    var FILL2 = g(0.851);          // #d9d9d9: a group heading cell
    var EDGE = g(0.949);           // the rate card draws its grid in the header grey
    var DATA2 = g(0.651);          // #a6a6a6: a second series, the ordinary bars
    var DATA3 = g(0.80);           // #cccccc: a third series
    var PAPER = g(1);
    var SERIES = [INK, DATA2, DATA3];
    var periodW = periodWord(rep.period_start, rep.period_end);

    var pages = [];
    var pg = null, y = 0;
    /* A label in Chinese is drawn through the shaper, which carries the
       Chinese face; Latin text keeps the direct path. */
    var CJK = /[\u2e80-\u9fff\uff00-\uffef\u3000-\u303f]/;
    var text = function (s, x, yy, size, f, color) {
      var str = tr(String(s == null ? '' : s));
      if (CJK.test(str)) { sh.draw(pg.page, sh.linesOf(str, 1e6, size || 10.5, f || book)[0] || [], x, yy, size || 10.5, color || INK); return; }
      pg.page.drawText(str, { x: x, y: yy, size: size || 10.5, font: f || book, color: color || INK });
    };
    var width = function (s, size, f) {
      var str = tr(String(s == null ? '' : s));
      if (CJK.test(str)) return sh.lineWidth(sh.linesOf(str, 1e6, size || 10.5, f || book)[0] || [], size || 10.5);
      return (f || book).widthOfTextAtSize(str, size || 10.5);
    };
    var right = function (s, xr, yy, size, f, color) { text(s, xr - width(s, size, f), yy, size, f, color); };
    var center = function (s, xc, yy, size, f, color) { text(s, xc - width(s, size, f) / 2, yy, size, f, color); };
    var rect = function (x, yy, w, h, color) { pg.page.drawRectangle({ x: x, y: yy, width: w, height: h, color: color, borderWidth: 0 }); };
    var frame = function (x, yy, w, h, color, thick) { pg.page.drawRectangle({ x: x, y: yy, width: w, height: h, borderColor: color || EDGE, borderWidth: thick || 0.48 }); };
    var hline = function (yy, x1, x2, color, thick, dash) {
      var o = { start: { x: x1, y: yy }, end: { x: x2, y: yy }, thickness: thick || 0.48, color: color || EDGE };
      if (dash) o.dashArray = dash;
      pg.page.drawLine(o);
    };
    var tline = function (s, x, yy, size, f, color, maxW) {
      var line = sh.linesOf(String(s == null ? '' : s), maxW || 1e6, size, f || book)[0] || [];
      sh.draw(pg.page, line, x, yy, size, color || INK);
      return sh.lineWidth(line, size);
    };
    var clip = function (s, maxW, size, f) {
      var str = String(s == null ? '' : s);
      var line = sh.linesOf(str, 1e6, size, f || book)[0] || [];
      if (sh.lineWidth(line, size) <= maxW) return str;
      var lo = 0, hi = str.length;
      while (lo < hi) {
        var mid = Math.ceil((lo + hi) / 2);
        var l2 = sh.linesOf(str.slice(0, mid).trim() + '…', 1e6, size, f || book)[0] || [];
        if (sh.lineWidth(l2, size) <= maxW) lo = mid; else hi = mid - 1;
      }
      return str.slice(0, lo).trim() + '…';
    };
    var newPage = function (section) {
      pg = { page: pdf.addPage([W, H]), section: section || '' };
      pages.push(pg);
      y = TOP;
    };
    var room = function () { return y - FLOOR; };
    var need = function (h) { if (y - h < FLOOR) { newPage(pg.section); return true; } return false; };
    var para = function (s, x, w, size, lh, f, color) {
      sh.linesOf(s, w, size, f || book).forEach(function (ln) { need(lh); sh.draw(pg.page, ln, x, y, size, color || INK); y -= lh; });
    };
    /* The page title in Slate Regular at S(3), the first block S(2) under
       it. Every section starts a page of its own, so a report with little in
       it is shorter by whole sections and never squeezed onto half a page. */
    /* The template stays English in a Chinese report (the user, 2026-10-01):
       the cover, each page's title and the head and foot; what sits under
       a title (table titles, column heads, notes, dates) reads Chinese. */
    var pageTitle = function (s) { var z = ZH; ZH = false; tline(s, M, y, TY.title, reg, INK, CW); ZH = z; y -= TY.title * 0.25 + SP.under; };
    /* A block's title in Slate Regular at S(1), the block S(-1) under it.
       `y` is always the top edge of what comes next, so the space between
       two blocks is exactly S(4) whatever they are, and under a title S(2).
       `keep` is the height of what must follow it on the same page. */
    var blockTitle = function (s, keep) {
      need(TY.block + SP.line + (keep || 40));
      y -= TY.block * 0.72;
      tline(s, M, y, TY.block, reg, INK, CW); y -= TY.block * 0.28 + SP.line;
    };
    var gap = function (h) { y -= h; };
    var BLOCK = SP.block;
    /* Lines of prose from the top edge `y`: the first baseline its cap height
       down, each next one a φ line (S(2)) under it, and the block after it
       S(4) under the last line's descent. */
    var proseBlock = function (lines) {
      var last = null;
      lines.forEach(function (l) {
        if (l.gap) { if (last !== null) y -= l.gap; return; }
        if (last === null) y -= l.size * 0.72; else y -= S(2);
        need(S(2)); sh.draw(pg.page, l.ln, M, y, l.size, INK); last = l;
      });
      if (last) y -= last.size * 0.28 + BLOCK;
    };

    var groupWord = function (p) { return p._group ? p._group.label : ''; };
    var typeWord = function (p) { return TYPE_WORD[p.content_type] || (p.content_type ? String(p.content_type) : ''); };
    var shortDay = function (s) { var d = dateOf(s); return d ? (ZH ? zhDay(d) : d.getDate() + ' ' + MON3[d.getMonth()]) : ''; };
    /* A post without a title is named by what it is and when it went out, so
       a ranking reads as a list of posts and not as "Untitled post" five
       times. Two on one day are numbered in posting order. */
    var sameDay = {};
    mdl.posts.forEach(function (p) { var k = (p._group ? p._group.key : '') + '|' + p.posted_on; (sameDay[k] = sameDay[k] || []).push(p); });
    var postName = function (p) {
      if (words(p.title).trim()) return words(p.title).trim();
      var k = (p._group ? p._group.key : '') + '|' + p.posted_on;
      var list = sameDay[k] || [p];
      var base = ZH ? tr(typeWord(p) || 'Post') + '，' + shortDay(p.posted_on) : (typeWord(p) || 'Post') + ', ' + shortDay(p.posted_on);
      return list.length > 1 ? base + ' (' + (list.indexOf(p) + 1) + ')' : base;
    };
    var volOf = function (p) { var gg = p._group; return gg && gg.volume ? num(p[gg.volume]) : null; };
    var erOf = function (p) {
      var gg = p._group, e = engOf(p);
      if (!gg || !gg.basis || e === null) return null;
      if (gg.basis === 'followers') {
        var f = sumOf(gg.accounts, function (a) { return num(a.followers_end); });
        return f ? e / f : null;
      }
      var d = num(p[gg.basis]);
      return d ? e / d : null;
    };
    var volWord = function (gg) { return gg && gg.volume ? METRIC_WORD[gg.volume] : 'Views'; };
    var engWord = function (gg) { return gg && gg.engKey ? METRIC_WORD[gg.engKey] : 'Engagements'; };

    // ---------------------------------------------------------------- Tables
    /* The rate card's table, the one structure this document draws its data
       in: a header row in #f2f2f2, white rows, every cell edged 0.48pt in the
       same grey, the text vertically centred with 5pt at either side, and a
       label column in #f2f2f2 where a table reads by row. A row that no
       longer fits starts a new page with the header drawn again; a row of
       plain text taller than a page is split between pages. */
    /* The cell: 10pt text on a √φ line (12.72), S(-2) at either side, and a
       row of S(3) at least, so the text sits in the row with the same space
       above and below it. */
    var T = { size: TY.cell, lh: S(1), padX: S(-2), padY: (S(3) - S(1)) / 2, minH: S(3) };
    /* A result in a table: its count and short word, 0 Leads where an ad
       spent and had none, 1 Lead for one (the user, 2026-10-01). Where the pair is wider than its column (`frac` of the
       page's width) the word goes under the count, so neither breaks. */
    function countWord(n, label, frac, f) {
      var v = num(n) || 0, w = shortResult(label);
      if (v === 1 && /s$/.test(w)) w = w.replace(/s$/, '');
      var t = fmt(v) + ' ' + w;
      if (frac && width(t, T.size, f) > CW * frac - T.padX * 2) t = t.replace(' ', '\n');
      return t;
    }
    function cellLines(c, w) {
      if (c == null) return [];
      if (typeof c === 'string' || typeof c === 'number') c = { t: String(c) };
      if (c.fn) return null;
      var f = c.f || book, size = c.size || T.size;
      var out = [];
      String(c.t == null ? '' : c.t).split('\n').forEach(function (part, i) {
        if (c.items) return;
        sh.linesOf(part, w - T.padX * 2, size, f).forEach(function (ln) { out.push({ ln: ln, f: f, size: size }); });
      });
      if (c.items) {
        /* A numbered list inside a cell: the number in Slate Medium, the item
           hanging S(1) in, the row's own padding between items. */
        c.items.forEach(function (it, i) {
          var t0 = typeof it === 'string' ? it : it.t;
          /* Each point and sub-point is one unit (`unit` on its first line
             counts its lines): a page break falls between points, never
             inside one (the user, 2026-10-01). */
          var ls = sh.linesOf(t0, w - T.padX * 2 - S(1), size, f);
          ls.forEach(function (ln, k) { out.push({ ln: ln, f: f, size: size, num: k === 0 ? String(i + 1) : null, indent: S(1), unit: k === 0 ? ls.length : 0 }); });
          ((typeof it === 'object' && it && it.sub) || []).forEach(function (sb, j) {
            out.push({ gap: T.padY / 2 });
            var sl = sh.linesOf(sb, w - T.padX * 2 - S(1) * 2, size, f);
            sl.forEach(function (ln, k) {
              out.push({ ln: ln, f: f, size: size, num: k === 0 ? String.fromCharCode(97 + j) : null, numIndent: S(1), indent: S(1) * 2, unit: k === 0 ? sl.length : 0 });
            });
          });
          if (i < c.items.length - 1) out.push({ gap: T.padY });
        });
      }
      return out;
    }
    function linesH(ls) { return ls.reduce(function (t, l) { return t + (l.gap ? l.gap : T.lh); }, 0); }
    function drawLines(ls, x, top, w, h, c) {
      var total = linesH(ls);
      /* Lists read from the top of their cell, so two columns of points start
         on one line; everything else is centred, as the rate card sets it. */
      var off = c && c.top ? T.padY : (h - total) / 2;
      var yy = top - off - (T.lh - T.size) / 2 - T.size * 0.8;
      var align = (c && c.align) || 'left';
      ls.forEach(function (l) {
        if (l.gap) { yy -= l.gap; return; }
        var lw = sh.lineWidth(l.ln, l.size);
        var lx = x + T.padX + (l.indent || 0);
        if (align === 'center') lx = x + (w - lw) / 2;
        else if (align === 'right') lx = x + w - T.padX - lw;
        if (l.num) text(l.num, x + T.padX + (l.numIndent || 0), yy, l.size, med, INK);
        sh.draw(pg.page, l.ln, lx, yy, l.size, (c && c.color) || INK);
        yy -= T.lh;
      });
    }
    function norm(c) { return (typeof c === 'string' || typeof c === 'number') ? { t: String(c) } : (c || { t: '' }); }
    /* cols: [{ w, align }] (widths are fractions of the column when they add
       to 1 or less, else points); head: labels or null; rows: [{ cells,
       fill, minH }]. A cell is text, { t, f, size, align, color, fill },
       { items: [...] } or { fn(x, top, w, h), h }. */
    function table(cols, head, rows, o) {
      o = o || {};
      var tw = o.width || CW, x0 = o.x == null ? M : o.x;
      var tot = cols.reduce(function (t, c) { return t + c.w; }, 0);
      var ws = cols.map(function (c) { return c.w * (tw / tot); });
      var xs = []; ws.reduce(function (acc, w, i) { xs[i] = acc; return acc + w; }, x0);
      var headH = 0;
      var drawHead = function () {
        if (!head) return;
        var hl = head.map(function (hc, i) { return cellLines({ t: norm(hc).t, f: reg }, ws[i]); });
        headH = Math.max(T.minH, Math.max.apply(null, hl.map(linesH)) + T.padY * 2);
        head.forEach(function (hc, i) {
          rect(xs[i], y - headH, ws[i], headH, norm(hc).fill || FILL);
          frame(xs[i], y - headH, ws[i], headH);
          drawLines(hl[i], xs[i], y, ws[i], headH, { align: norm(hc).align || cols[i].align || 'center' });
        });
        y -= headH;
      };
      var headNeed = function () {
        if (!head) return 0;
        var hl = head.map(function (hc, i) { return cellLines({ t: norm(hc).t, f: reg }, ws[i]); });
        return Math.max(T.minH, Math.max.apply(null, hl.map(linesH)) + T.padY * 2);
      };
      var first = true;
      rows.forEach(function (row, ri) {
        var cells = row.cells.map(norm);
        var ls = cells.map(function (c, i) { return c.fn ? null : cellLines(c, ws[i]); });
        var contentH = Math.max.apply(null, cells.map(function (c, i) { return c.fn ? (c.h || 0) : linesH(ls[i]) + T.padY * 2; }));
        var h = Math.max(row.minH || T.minH, contentH);
        var pageSpace = TOP - FLOOR - headNeed();
        if (first) { need(headNeed() + (row.split ? Math.min(h, T.lh * 3 + T.padY * 2) : Math.min(h, pageSpace))); drawHead(); first = false; }
        else if (y - h < FLOOR && h <= pageSpace) { newPage(pg.section); drawHead(); }
        if (h > pageSpace || (y - h < FLOOR && row.split)) {
          /* Too tall for any page, or allowed to break: the text cells are
             split line by line, and a label column repeats with (cont.). */
          var cur = ls.map(function () { return 0; });
          var part0 = true;
          var remaining = function () { return ls.some(function (l, i) { return l && cur[i] < l.length; }); };
          while (remaining()) {
            var avail = y - FLOOR - T.padY * 2, fullH = pageSpace - T.padY * 2;
            if (avail < T.lh * 2) { newPage(pg.section); drawHead(); continue; }
            var part = ls.map(function (l, i) {
              if (!l) return [];
              if (o.labelCol && i === 0) {
                var lab = part0 ? l : cellLines({ t: cells[0].t + ' (cont.)', f: cells[0].f }, ws[0]);
                cur[0] = l.length;
                return lab;
              }
              var out = [], used = 0;
              while (cur[i] < l.length) {
                var L = l[cur[i]], take = L.unit && L.unit * T.lh <= fullH ? L.unit : 1;
                var need0 = L.gap || take * T.lh;
                if (used + need0 > avail) break;
                for (var k = 0; k < take; k++) { out.push(l[cur[i]]); cur[i]++; }
                used += need0;
              }
              while (out.length && out[0].gap) out.shift();
              while (out.length && out[out.length - 1].gap) out.pop();
              return out;
            });
            /* Nothing but a repeated label fits above the next whole point:
               the row goes on the next page instead of an empty slice. */
            if (!part.some(function (pt, i) { return pt.length && !(o.labelCol && i === 0); })) {
              if (part0) { cur = ls.map(function () { return 0; }); }
              newPage(pg.section); drawHead(); continue;
            }
            var ph = Math.max(T.minH, Math.max.apply(null, part.map(linesH)) + T.padY * 2);
            cells.forEach(function (c, i) {
              rect(xs[i], y - ph, ws[i], ph, c.fill || row.fill || (o.labelCol && i === 0 ? FILL : PAPER));
              frame(xs[i], y - ph, ws[i], ph);
              drawLines(part[i], xs[i], y, ws[i], ph, { align: c.align || cols[i].align || 'center', color: c.color, top: !!c.items });
            });
            y -= ph;
            part0 = false;
            if (remaining()) { newPage(pg.section); drawHead(); }
          }
          return;
        }
        cells.forEach(function (c, i) {
          rect(xs[i], y - h, ws[i], h, c.fill || row.fill || (o.labelCol && i === 0 ? FILL : PAPER));
          frame(xs[i], y - h, ws[i], h);
          if (c.fn) c.fn(xs[i], y, ws[i], h);
          else drawLines(ls[i], xs[i], y, ws[i], h, { align: c.align || cols[i].align || 'center', color: c.color, top: !!c.items });
        });
        y -= h;
      });
      if (first && head) { need(headNeed()); drawHead(); }
    }

    /* A thumbnail in a fixed frame, so a column of them is one column: the
       frame is the header grey and the image fits inside it whole. */
    function thumbIn(p, x, top, w, h) {
      rect(x, top - h, w, h, FILL);
      var img = thumbs[p.id];
      if (!img) return;
      var s = Math.min(w / img.width, h / img.height);
      var dw = img.width * s, dh = img.height * s;
      pg.page.drawImage(img, { x: x + (w - dw) / 2, y: top - h + (h - dh) / 2, width: dw, height: dh });
    }

    /* The figures that head a page: the rate card's table, a label row over a
       value row, the value in Slate Medium. */
    function figures(cells) {
      var cols = cells.map(function () { return { w: 1 / cells.length, align: 'center' }; });
      table(cols, cells.map(function (c) { return c.label; }), [{
        minH: S(5),
        cells: cells.map(function (c) {
          var na = c.value === 'Not available';
          return { fn: function (x, top, w, h) {
            var size = na ? TY.body : (String(c.value).length > 8 ? S(2) : TY.figure);
            center(c.value, x + w / 2, top - h / 2 - size * 0.34, size, na ? book : med, na ? MUTE : INK);
          }, h: S(5) };
        })
      }]);
    }

    function niceStep(raw) {
      var p = Math.pow(10, Math.floor(Math.log10(raw || 1)));
      var m = raw / p;
      var s = m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10;
      return s * p;
    }
    /* The value axis every chart shares: three or four round gridlines in the
       edge grey, labels in the mute ink at their left. */
    function axis(plotX, plotW, base, plotH, maxV) {
      var step = niceStep(maxV / 3);
      var scaleMax = step * Math.ceil(maxV / step);
      for (var v = 0; v <= scaleMax + step * 0.001; v += step) {
        var yy = base + plotH * (v / scaleMax);
        hline(yy, plotX, plotX + plotW, v === 0 ? FILL2 : FILL, v === 0 ? 0.6 : 0.48);
        right(v.toLocaleString('en-GB'), plotX - S(-2), yy - 2.7, TY.small, book, MUTE);
      }
      return scaleMax;
    }
    function legend(items, x, yy) {
      var lx = x;
      items.forEach(function (it) {
        rect(lx, yy - 1, S(-1), S(-1), it.color);
        text(it.label, lx + S(1), yy, TY.small, book, INK);
        lx += S(1) + width(it.label, TY.small, book) + S(2);
      });
    }

    /* Views by week: the period in seven-day weeks, one column a week, the
       platforms stacked in the fixed order the report lists them, a 1pt paper
       gap between segments, and the week's total over its column. The job is
       change over time and share of it, so the weeks are the axis and not the
       posts: thirty bars of one post each read as noise. */
    function weeklyChart(groups, h) {
      var start = dateOf(rep.period_start), end = dateOf(rep.period_end);
      var posts = mdl.posts.filter(function (p) { return p._group && dateOf(p.posted_on) && volOf(p) !== null; });
      if (!posts.length) { text('No data.', M, y - 12, TY.body, book, MUTE); y -= 20; return; }
      if (!start || !end) { start = dateOf(posts[0].posted_on); end = dateOf(posts[posts.length - 1].posted_on); }
      var days = Math.round((end - start) / 864e5) + 1;
      var weeks = [];
      for (var d0 = 0; d0 < days; d0 += 7) {
        var a = new Date(start.getTime() + d0 * 864e5), b = new Date(start.getTime() + Math.min(days - 1, d0 + 6) * 864e5);
        weeks.push({ a: a, b: b, by: {}, total: 0,
          label: ZH ? zhDay(a) + '至' + (a.getMonth() !== b.getMonth() ? zhDay(b) : b.getDate() + '日') :
            a.getDate() + (a.getMonth() !== b.getMonth() ? ' ' + MON3[a.getMonth()] : '') + ' to ' + b.getDate() + ' ' + MON3[b.getMonth()] });
      }
      posts.forEach(function (p) {
        var k = Math.floor((dateOf(p.posted_on) - start) / 864e5 / 7);
        var wk = weeks[Math.max(0, Math.min(weeks.length - 1, k))];
        wk.by[p._group.key] = (wk.by[p._group.key] || 0) + volOf(p);
        wk.total += volOf(p);
      });
      var maxV = weeks.reduce(function (m, w) { return Math.max(m, w.total); }, 0) || 1;
      need(h + 30);
      var top = y;
      if (groups.length > 1) { legend(groups.map(function (gg, i) { return { label: gg.label, color: SERIES[i] || DATA3 }; }), M, top - 6); }
      var axisW = S(6), plotX = M + axisW, plotW = CW - axisW;
      var base = top - h + 14, plotH = h - 14 - (groups.length > 1 ? 34 : 22);
      var scaleMax = axis(plotX, plotW, base, plotH, maxV);
      var slot = plotW / weeks.length, bw = Math.min(56, slot * 0.46);
      weeks.forEach(function (wk, i) {
        var cx = plotX + slot * i + slot / 2, yy = base;
        groups.forEach(function (gg, gi) {
          var v = wk.by[gg.key] || 0; if (!v) return;
          var bh = plotH * (v / scaleMax);
          rect(cx - bw / 2, yy, bw, Math.max(0.8, bh - (gi < groups.length - 1 ? 1 : 0)), SERIES[gi] || DATA3);
          yy += bh;
        });
        center(fmt(wk.total), cx, base + plotH * (wk.total / scaleMax) + 5, TY.small, med, INK);
        center(wk.label, cx, base - 11, TY.small, book, MUTE);
      });
      y = top - h - 4;
    }

    /* Views by post, in posting order: one column a post, the ordinary ones
       in the second grey and the month's best in ink with its value over it,
       and the average as a dashed ink line, so the page answers which posts
       beat the month's own mean without a sentence saying so. */
    function postsChart(gg, h) {
      var posts = gg.posts.filter(function (p) { return volOf(p) !== null; });
      if (!posts.length) return;
      var maxV = posts.reduce(function (m, p) { return Math.max(m, volOf(p)); }, 0) || 1;
      var avg = posts.reduce(function (t, p) { return t + volOf(p); }, 0) / posts.length;
      need(h + 10);
      var top = y;
      var axisW = S(6), plotX = M + axisW, plotW = CW - axisW;
      var base = top - h + 14, plotH = h - 14 - 16;
      var scaleMax = axis(plotX, plotW, base, plotH, maxV);
      var slot = plotW / posts.length, bw = Math.max(2, Math.min(22, slot - 3));
      var best = posts.reduce(function (b, p) { return volOf(p) > volOf(b) ? p : b; }, posts[0]);
      var lastDay = null, lastX = -1e9;
      posts.forEach(function (p, i) {
        var cx = plotX + slot * i + slot / 2;
        var bh = Math.max(0.8, plotH * (volOf(p) / scaleMax));
        rect(cx - bw / 2, base, bw, bh, p === best ? INK : DATA2);
        if (p === best) center(fmt(volOf(p)), cx, base + bh + 4, TY.small, med, INK);
        var day = shortDay(p.posted_on);
        var lw = width(day, TY.small, book);
        if (day !== lastDay && cx - lw / 2 > lastX + 3) { center(day, cx, base - 11, TY.small, book, MUTE); lastX = cx + lw / 2; }
        lastDay = day;
      });
      var ay = base + plotH * (avg / scaleMax);
      hline(ay, plotX, plotX + plotW, INK, 0.6, [2.5, 2]);
      var al = 'Average ' + fmt(Math.round(avg));
      var alw = width(al, TY.small, reg);
      rect(plotX + plotW - alw - 6, ay + 2, alw + 6, TY.small + 3, PAPER);
      right(al, plotX + plotW - 2, ay + 4, TY.small, reg, INK);
      y = top - h - 2;
    }

    // ---------------------------------------------------------------- Cover
    (function cover() {
      /* The rate card's cover, on the scale: the title stands in from the
         margin by S(9), 87pt, so it starts 120pt from the page's edge where
         the rate card starts its title at 126pt, with its baseline on the
         golden section of the page's height. The client and the month sit
         under it on the same indent, each line a step of the scale below the
         last. The head's wordmark stays on the margin, so the title reads as
         set in from the page and not as another line of the running head. */
      /* The cover stays in English in a Chinese report too, as the file's
         name does (the user, 2026-10-01): the report is known by one name. */
      var zhWas = ZH; ZH = false;
      newPage('cover');
      var cx = M + S(9), cw = R - cx;
      var cy = H / PHI;
      var tlines = sh.linesOf(titleOf(rep), cw, TY.cover, med);
      cy += (tlines.length - 1) * S(6);
      tlines.forEach(function (ln, i) { sh.draw(pg.page, ln, cx, cy, TY.cover, INK); if (i < tlines.length - 1) cy -= S(6); });
      cy -= S(6);
      sh.linesOf(String(rep.client_name || ''), cw, TY.coverSub, reg).forEach(function (ln) { sh.draw(pg.page, ln, cx, cy, TY.coverSub, INK); cy -= S(4); });
      tline(periodWord(rep.period_start, rep.period_end), cx, cy, TY.coverMeta, book, INK, cw);
      ZH = zhWas;
    })();

    var ins = rep.insights || {};
    if (rep.kind === 'ads') adsReport(); else socialReport();

    function socialReport() {

    // ------------------------------------------------------- Executive summary
    /* Each section below starts a page of its own and never shrinks to fit
       another onto it: a client with little to report gets fewer pages, not
       pages cut off halfway. A chart keeps one height wherever it is. */
    var CHART_WEEK = CW / (PHI * PHI);         // 201.9pt: the column over φ²
    var CHART_POSTS = CW / Math.pow(PHI, 2.5); // 158.8pt: half a step shorter
    (function summary() {
      newPage('Executive Summary');
      pageTitle('Executive Summary');
      var t = mdl.totals;
      var head = words(rep.headline).trim();
      var prose = [];
      if (head) sh.linesOf(head, CW, TY.lead, med).slice(0, 3).forEach(function (ln) { prose.push({ ln: ln, size: TY.lead, f: med }); });
      [rep.intro, ins.executive_summary].forEach(function (blk) {
        paragraphsOf(blk).filter(function (s) { return s.trim(); }).forEach(function (s) {
          if (prose.length) prose.push({ gap: SP.tight });
          sh.linesOf(s, CW, TY.body, book).forEach(function (ln) { prose.push({ ln: ln, size: TY.body }); });
        });
      });
      proseBlock(prose);
      figures([
        { label: 'Posts published', value: String(t.posts) },
        { label: 'Follower growth', value: signed(t.growth) },
        { label: t.volumeWords.length === 1 ? 'Total ' + t.volumeWords[0].toLowerCase() : 'Total views', value: fmt(t.views) },
        { label: t.engWords.length === 1 ? 'Total ' + t.engWords[0].toLowerCase() : 'Total engagements', value: fmt(t.eng) },
        { label: 'Engagement rate', value: pct(t.er) }
      ]);
      gap(BLOCK);
      // The split by platform, one row a platform: the table the figures total.
      if (mdl.groups.length > 1) {
        blockTitle('By platform', T.minH * (mdl.groups.length + 1));
        table([{ w: 0.26, align: 'left' }, { w: 0.1 }, { w: 0.16 }, { w: 0.14 }, { w: 0.16 }, { w: 0.18 }],
          [{ t: 'Platform', align: 'left' }, 'Posts', 'Follower growth', 'Views', 'Engagements', 'Engagement rate'],
          mdl.groups.map(function (gg) {
            return { cells: [gg.label, String(gg.posts.length), signed(gg.growth), fmt(gg.views), fmt(gg.eng), pct(gg.er)] };
          }), { labelCol: true });
        gap(BLOCK);
      }
      blockTitle((t.volumeWords.length === 1 ? t.volumeWords[0] : 'Views') + ' by week', CHART_WEEK);
      weeklyChart(mdl.groups, CHART_WEEK);
    })();

    // ------------------------------------------------ Insights and recommendations
    /* One block a platform (the user, 2026-10-01: each platform's algorithm
       works differently, so its findings are read on their own): the
       platform's line, then its highlights, what to improve and what we
       recommend next, from the account's own remarks. Remarks written for
       the report as a whole (older reports) follow under Across all
       platforms. */
    (function insights() {
      var rowsOf = function (list) {
        return list.filter(function (r) { return words(r[1]).trim(); });
      };
      /* Each part under its own shaded head with its points numbered beneath,
         as the advertising report reads (the user, 2026-10-01), not a label
         column beside them. */
      var parts = function (rows) {
        rows.forEach(function (r, i) {
          if (i) gap(SP.under);
          table([{ w: 1, align: 'left' }], [{ t: r[0], align: 'left' }], [{ cells: [{ items: pointTree(r[1]) }], split: true }]);
        });
      };
      var blocks = mdl.groups.map(function (gg) {
        return { gg: gg, lead: words(gg.summary).trim(),
          rows: rowsOf([['Highlights', gg.worked], ['Areas to Improve', gg.improve], ['Recommendations', gg.actions]]) };
      }).filter(function (b) { return b.lead || b.rows.length; });
      var across = rowsOf([['Key Findings', ins.performed_well], ['Performance Drivers', ins.why_well],
        ['Areas to Improve', ins.underperformed], ['Opportunities', ins.opportunities],
        ['Improvements', ins.improvements], ['Next Steps', ins.next_actions]]);
      if (!blocks.length && !across.length) return;
      newPage('Insights and Recommendations');
      pageTitle('Insights and Recommendations');
      blocks.forEach(function (b, i) {
        if (i) gap(BLOCK);
        blockTitle(b.gg.label, T.minH * 2);
        if (b.lead) proseBlock(sh.linesOf(b.lead, CW, TY.body, book).map(function (ln) { return { ln: ln, size: TY.body }; }));
        parts(b.rows);
      });
      if (across.length) {
        if (blocks.length) gap(BLOCK);
        blockTitle(blocks.length ? 'Across All Platforms' : 'Insights', T.minH * 2);
        parts(across);
      }
    })();

    /* A caption as it was written: its own lines and blank lines kept, each
       line wrapped to the column, at most `max` lines with the rest cut. A
       blank line is a half step. */
    var captionLines = function (p, w, max) {
      var out = [];
      paragraphsOf(p.caption).forEach(function (s) {
        if (!s.trim()) { if (out.length && out[out.length - 1] !== null) out.push(null); return; }
        sh.linesOf(s, w, TY.small, book).forEach(function (ln) { out.push(ln); });
      });
      while (out.length && out[out.length - 1] === null) out.pop();
      if (out.length > max) { out = out.slice(0, max); while (out.length && out[out.length - 1] === null) out.pop(); out.cut = true; }
      return out;
    };
    var captionH = function (lines) { return lines.reduce(function (t, l) { return t + (l === null ? S(-2) : S(0)); }, 0); };

    /* A platform's best posts, ranked on that platform alone by its own
       figure: the image, the figures, the caption and why it stood out. */
    var postCards = function (gg, list) {
      var IMG_W = S(8), IMG_H = IMG_W * 1.25;   // 4:5, the portrait post
      var dw = CW / PHI - T.padX * 2;           // the details column: the golden major
      table([{ w: 0.1 }, { w: 1 - 1 / PHI - 0.1 }, { w: 1 / PHI, align: 'left' }],
        ['Rank', 'Post', { t: 'Details', align: 'left' }],
        list.map(function (p, i) {
          var cap = words(p.caption).trim() ? captionLines(p, dw, 10) : [];
          var notable = words(p.notable).trim() ? sh.linesOf(p.notable, dw, TY.body, book) : [];
          var metrics = [];
          if (gg.volume) metrics.push([METRIC_WORD[gg.volume], fmt(p[gg.volume])]);
          metrics.push([engWord(gg), fmt(engOf(p))]);
          metrics.push(['Engagement rate', pct(erOf(p))]);
          /* The meta line says only what the name does not: a post with no
             title is named by its type and day already, so it adds nothing
             but the platform where the page holds more than one (the user,
             2026-10-01: "Video, 1 Sept" over "1 Sept 2026 · Video"). */
          var own = words(p.title).trim();
          var acc = gg.accounts.length > 1 ? gg.accounts.filter(function (a) { return a.id === p.platform_id; })[0] : null;
          var meta = [acc ? PLATFORM_WORD[acc.platform] || acc.platform : '', own ? dayWord(p.posted_on) : '', own ? typeWord(p) : ''].filter(Boolean).join('  ·  ');
          var NAME = S(2), META = NAME + S(2), BOX = (meta ? META : NAME) + S(-1), LABH = S(2), VALH = S(3);
          var AFTER = BOX + LABH + VALH + S(2);
          var textH = AFTER + (cap.length ? captionH(cap) + (cap.cut ? S(0) : 0) + S(-2) : 0) + (notable.length ? S(0) + notable.length * S(1) : 0) + S(-2);
          var h = Math.max(IMG_H + S(-2) * 2, textH);
          return { minH: h, cells: [
            { t: String(i + 1), f: med, size: S(2), align: 'center' },
            { fn: function (x, top, w, hh) { thumbIn(p, x + (w - IMG_W) / 2, top - (hh - IMG_H) / 2, IMG_W, IMG_H); }, h: h },
            { fn: function (x, top, w, hh) {
              var tx = x + T.padX;
              tline(clip(postName(p), dw, TY.lead, med), tx, top - NAME, TY.lead, med, INK);
              if (meta) tline(meta, tx, top - META, TY.small, book, SOFT, dw);
              // The figures run the details column's whole width.
              var mw = dw / metrics.length;
              var by = top - BOX;
              metrics.forEach(function (m, k) {
                var mx = tx + k * mw;
                rect(mx, by - LABH, mw, LABH, FILL); frame(mx, by - LABH, mw, LABH);
                center(m[0], mx + mw / 2, by - LABH / 2 - TY.small * 0.34, TY.small, reg, INK);
                frame(mx, by - LABH - VALH, mw, VALH);
                center(m[1], mx + mw / 2, by - LABH - VALH / 2 - TY.body * 0.34, TY.body, med, INK);
              });
              var ty = top - AFTER;
              cap.forEach(function (ln) { if (ln === null) { ty -= S(-2); return; } sh.draw(pg.page, ln, tx, ty, TY.small, SOFT); ty -= S(0); });
              if (cap.cut) { tline('…', tx, ty, TY.small, book, SOFT); ty -= S(0); }
              if (cap.length) ty -= S(-2);
              if (notable.length) {
                tline('Remarks', tx, ty, TY.small, reg, INK); ty -= S(1);
                notable.forEach(function (ln) { sh.draw(pg.page, ln, tx, ty, TY.body, INK); ty -= S(1); });
              }
            }, h: h }
          ] };
        }));
    };

    // ------------------------------------------------------- Platform pages
    mdl.groups.forEach(function (gg) {
      newPage(gg.label);
      pageTitle(gg.label);
      var cells = [{ label: 'Posts', value: String(gg.posts.length) }];
      gg.accounts.forEach(function (a) {
        cells.push({ label: (gg.accounts.length > 1 ? (PLATFORM_WORD[a.platform] || a.platform) + ' follower growth' : 'Follower growth'), value: signed(growthOf(a)) });
      });
      if (gg.volume) cells.push({ label: 'Total ' + METRIC_WORD[gg.volume].toLowerCase(), value: fmt(gg.views) });
      if (gg.engKey) cells.push({ label: 'Total ' + METRIC_WORD[gg.engKey].toLowerCase(), value: fmt(gg.eng) });
      cells.push({ label: 'Engagement rate', value: pct(gg.er) });
      figures(cells.slice(0, 6));
      gap(BLOCK);
      var movers = gg.accounts.filter(function (a) { return num(a.followers_start) !== null && num(a.followers_end) !== null; });
      if (movers.length) {
        blockTitle('Followers', T.minH * (movers.length + 1));
        table([{ w: 1 / (PHI * PHI) }, { w: 0.2 }, { w: 0.2 }, { w: 1 - 1 / (PHI * PHI) - 0.4 }].map(function (c, i) { if (!i) c.align = 'left'; return c; }),
          [{ t: 'Account', align: 'left' }, 'Start of period', 'End of period', 'Growth'],
          movers.map(function (a) { return { cells: [PLATFORM_WORD[a.platform] || a.platform, fmt(a.followers_start), fmt(a.followers_end), signed(growthOf(a))] }; }),
          { labelCol: true });
        gap(BLOCK);
      }
      if (gg.volume && gg.posts.some(function (p) { return volOf(p) !== null; })) {
        blockTitle(METRIC_WORD[gg.volume] + ' by post', CHART_POSTS);
        postsChart(gg, CHART_POSTS);
        gap(BLOCK);
      }
      var ranked = topOf(gg, 3);
      if (ranked.length) {
        blockTitle('Top ' + (ranked.length === 1 ? 'post' : ranked.length + ' posts') + ' by ' + (METRIC_WORD[gg.rank] || METRIC_WORD[gg.volume] || 'views').toLowerCase(), S(8) * 1.25 + T.minH + S(-2) * 2);
        postCards(gg, ranked);
      }
    });

    // ------------------------------------------------------- Appendix
    /* All posts, one platform a page, so a platform's list always opens at
       the top of a page and closes on its own total. */
    (function appendix() {
      mdl.groups.forEach(function (gg) {
        if (!gg.posts.length) return;
        var name = 'Appendix: ' + gg.label;
        newPage(name);
        pageTitle(name);
        var hasType = gg.posts.some(function (p) { return typeWord(p); });
        var cols = [{ w: hasType ? 0.34 : 0.42, align: 'left' }, { w: 0.1 }];
        var head = [{ t: 'Post', align: 'left' }, 'Date'];
        if (hasType) { cols.push({ w: 0.1 }); head.push('Format'); }
        cols.push({ w: 0.12 }, { w: 0.16 }, { w: 0.18 });
        head.push(volWord(gg), engWord(gg), 'Engagement rate');
        var ROWH = S(7);
        var TH = ROWH - S(-2) * 2, TW = TH * 0.8;
        var rows = gg.posts.map(function (p) {
          var remark = words(p.observation).trim();
          var cells = [{ fn: function (x, top, w, h) {
            thumbIn(p, x + T.padX, top - S(-2), TW, TH);
            var tx = x + T.padX + TW + S(-2), tw = w - T.padX * 2 - TW - S(-2);
            var lines = [];
            lines.push({ s: clip(postName(p), tw, TY.body, med), f: med, size: TY.body, c: INK });
            if (words(p.caption).trim()) captionLines(p, tw, remark ? 1 : 2).forEach(function (ln) { if (ln) lines.push({ ln: ln, size: TY.small, c: SOFT }); });
            if (remark) lines.push({ s: clip('Remarks: ' + remark, tw, TY.small, book), f: book, size: TY.small, c: INK });
            var bh = TY.body + (lines.length - 1) * S(0);
            var ly = top - (h - bh) / 2 - TY.body * 0.8;
            lines.forEach(function (l, k) {
              if (l.ln) sh.draw(pg.page, l.ln, tx, ly, l.size, l.c); else tline(l.s, tx, ly, l.size, l.f, l.c);
              ly -= k === 0 ? S(1) : S(0);
            });
          }, h: ROWH }, shortDay(p.posted_on)];
          if (hasType) cells.push(typeWord(p) || '');
          cells.push(fmt(volOf(p)), fmt(engOf(p)), pct(erOf(p)));
          return { minH: ROWH, cells: cells };
        });
        var totalCells = [{ t: 'Total', f: reg }, ''];
        if (hasType) totalCells.push('');
        totalCells.push({ t: fmt(gg.views), f: med }, { t: fmt(gg.eng), f: med }, { t: pct(gg.er), f: med });
        rows.push({ fill: FILL, cells: totalCells });
        table(cols, head, rows);
      });
    })();
    }

    // ======================================================= Advertising report
    /* The team's advertising template, first month and later months, drawn
       on the same scale, grid and furniture as the social report. What the
       template left to the reader is done on the page: the ads are grouped
       by objective, so a cost per result is only ever beside another of the
       same goal; each group opens on a table that ranks its ads; the age
       split is a chart and not twelve cells; and a later month states the
       change against the month before in the same table as the figure. The
       reading guidance is the first month's, where a client meets these
       terms for the first time. */
    function adsReport() {
      var am = mdl.adsm, at = am.totals, first = am.first;
      var mk = String(rep.market || '').toUpperCase();
      var CUR = mk === 'SG' ? 'S$' : 'RM';
      var money = function (v) {
        v = num(v);
        return v === null ? 'Not available' : CUR + ' ' + v.toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      };
      /* A result bought for under ten sen (a post engagement) reads to three
         decimals, so RM 0.004 never prints as a free RM 0.00. */
      var cost = function (v) {
        v = num(v);
        return v !== null && v > 0 && v < 0.1 ? CUR + ' ' + v.toFixed(3) : money(v);
      };
      var pctv = function (v) { v = num(v); return v === null ? 'Not available' : (Math.round(v * 100) / 100).toFixed(2) + '%'; };
      var pctShort = function (v) { v = num(v); return v === null ? 'Not available' : String(Math.round(v * 100) / 100) + '%'; };
      var cprLabel = function (per1000) { return per1000 ? 'Cost per 1,000 reached' : 'Cost per result'; };
      var ratio = function (v) { return v === null || v === undefined || isNaN(v) ? 'Not available' : (Math.round(v * 100) / 100).toFixed(2); };
      var playW = function (v) {
        v = num(v); if (v === null) return 'Not available';
        var s = Math.round(v); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
      };
      var change = function (cur, prev) {
        cur = num(cur); prev = num(prev);
        if (cur === null || prev === null || !prev) return 'Not available';
        var d = (cur - prev) / prev * 100;
        return (d > 0.05 ? '+' : d < -0.05 ? '−' : '') + Math.abs(d).toFixed(1) + '%';
      };
      var shortD = function (s) { var d = dateOf(s); return d ? (ZH ? zhDay(d) : d.getDate() + ' ' + MON3[d.getMonth()]) : ''; };
      var range = function (a, b) {
        var da = dateOf(a), db2 = dateOf(b);
        if (!da && !db2) return '';
        if (!da || !db2) return dayWord(a || b);
        /* In a table cell the report's own year is understood: 7月5日至6日. */
        if (ZH) return da.getFullYear() === db2.getFullYear() && String(rep.period_start || '').slice(0, 4) === String(da.getFullYear())
          ? zhDay(da) + '至' + (da.getMonth() === db2.getMonth() ? db2.getDate() + '日' : zhDay(db2)) : zhSpan(da, db2);
        if (da.getFullYear() !== db2.getFullYear()) return dayWord(a) + ' to ' + dayWord(b);
        // One month says its name once: 1 to 30 Sept 2026.
        if (da.getMonth() === db2.getMonth()) return da.getDate() + ' to ' + dayWord(b);
        return shortD(a) + ' to ' + dayWord(b);
      };
      var TAX = mk === 'SG'
        ? 'Amount spent is the full amount spent on ads. It excludes the 5% DCC and 9% GST, charged separately.'
        : mk === 'MY'
          ? 'Amount spent is the full amount spent on ads. It excludes the 10% WHT and 8% SST, charged separately.'
          : 'Amount spent is the full amount spent on ads. It excludes the 10% WHT and 8% SST on a Malaysian ad account, and the 5% DCC and 9% GST on a Singapore one, charged separately.';

      /* A line under a page title, in the second ink: what the page is for,
         said once, in the first month only. */
      var leadLine = function (s) {
        var ls = sh.linesOf(s, CW, TY.body, book);
        ls.forEach(function (ln, i) { y -= i ? S(2) : TY.body * 0.72; sh.draw(pg.page, ln, M, y, TY.body, SOFT); });
        y -= TY.body * 0.28 + SP.under;
      };
      /* A reading note: a grey panel, its title in Slate Regular and its
         paragraphs in the body size, kept whole on one page. */
      var panel = function (title, paras) {
        var PADP = S(2), LH = S(1), GAPP = S(-1);
        var lines = paras.map(function (s) { return sh.linesOf(s, CW - PADP * 2, TY.body, book); });
        var h = PADP * 2 + TY.body + S(-1) + lines.reduce(function (t, ls) { return t + ls.length * LH; }, 0) + GAPP * (lines.length - 1);
        need(h);
        rect(M, y - h, CW, h, FILL);
        var yy = y - PADP - TY.body * 0.8;
        tline(title, M + PADP, yy, TY.body, reg, INK, CW - PADP * 2);
        yy -= TY.body * 0.2 + S(-1) + LH * 0.8;
        lines.forEach(function (ls, i) {
          if (i) yy -= GAPP;
          ls.forEach(function (ln) { sh.draw(pg.page, ln, M + PADP, yy, TY.body, INK); yy -= LH; });
        });
        y -= h + BLOCK;
      };
      var GLOSSARY = 'Every ad term is explained at go.adspace.me/fb-ad-terms.';

      // ------------------------------------------------ Executive summary
      (function summary() {
        newPage('Executive Summary');
        pageTitle('Executive Summary');
        if (first) leadLine('The headline figures for the period, before the detail.');
        var head = words(rep.headline).trim();
        if (head) proseBlock(sh.linesOf(head, CW, TY.lead, med).slice(0, 3).map(function (ln) { return { ln: ln, size: TY.lead }; }));
        if (at.hasPrev) {
          var thisW = 'This period\n' + range(rep.period_start, rep.period_end);
          var prevW = 'Previous period' + (at.prevStart ? '\n' + range(at.prevStart, at.prevEnd) : '');
          table([{ w: 0.3, align: 'left' }, { w: 0.25 }, { w: 0.25 }, { w: 0.2 }],
            [{ t: 'Account', align: 'left' }, thisW, prevW, 'Change'],
            [
              { cells: [{ t: 'Total reach', f: reg }, { t: fmt(at.reach), f: med }, fmt(at.prevReach), change(at.reach, at.prevReach)] },
              { cells: [{ t: 'Total impressions', f: reg }, { t: fmt(at.impressions), f: med }, fmt(at.prevImpressions), change(at.impressions, at.prevImpressions)] },
              { cells: [{ t: 'Frequency', f: reg }, { t: ratio(at.freq), f: med }, ratio(at.prevFreq), change(at.freq, at.prevFreq)] },
              { cells: [{ t: 'Amount spent *', f: reg }, { t: money(at.spend), f: med }, money(at.prevSpend), change(at.spend, at.prevSpend)] }
            ], { labelCol: true });
        } else {
          figures([
            { label: 'Total reach', value: fmt(at.reach) },
            { label: 'Total impressions', value: fmt(at.impressions) },
            { label: 'Frequency', value: ratio(at.freq) },
            { label: 'Amount spent *', value: money(at.spend) }
          ]);
        }
        gap(BLOCK);
        if (am.groups.length) {
          var withPrev = am.groups.some(function (g) { return g.prevCpr !== undefined && g.prevCpr !== null; }) && at.hasPrev;
          blockTitle('Results by objective', T.minH * (am.groups.length + 1));
          table([{ w: 0.19, align: 'left' }, { w: 0.23 }, { w: 0.17 }, { w: 0.18 }, { w: 0.23 }],
            [{ t: 'Objective', align: 'left' }, 'Result', 'Amount spent *', 'Cost per result', 'Share of spend'],
            am.groups.map(function (g) {
              return { minH: withPrev ? S(4) + S(1) : T.minH, cells: [
                { t: g.name, f: reg },
                { t: countWord(g.results, g.label, 0.23), f: med },
                money(g.spend),
                { t: cost(g.cpr) + (g.per1000 ? ' per 1,000' : '') + (withPrev && g.prevCpr !== null && g.prevCpr !== undefined ? '\nPrevious ' + cost(g.prevCpr) : '') },
                { fn: function (x, top, w, h) {
                  var tw = S(6), bx = x + T.padX, bw = w - T.padX * 2 - tw - S(-2);
                  rect(bx, top - h / 2 - 3, bw, S(-2), FILL);
                  if (g.share) rect(bx, top - h / 2 - 3, Math.max(0.8, bw * g.share), S(-2), INK);
                  right(g.share === null ? '' : (g.share * 100).toFixed(1) + '%', x + w - T.padX, top - h / 2 - 3.2, TY.body, book, INK);
                }, h: T.minH }
              ] };
            }), { labelCol: true });
        }
        // The note the asterisks point at, under the tables it qualifies.
        y -= TY.small * 0.72 + S(-1);
        sh.linesOf('* ' + TAX, CW, TY.small, book).forEach(function (ln, i) {
          if (i) y -= S(0);
          sh.draw(pg.page, ln, M, y, TY.small, MUTE);
        });
        y -= TY.small * 0.28 + BLOCK;
        var paras = paragraphsOf(rep.intro).filter(function (s) { return s.trim(); });
        if (paras.length) {
          blockTitle('Summary', S(1) * 3);
          var prose = [];
          paras.forEach(function (s, i) {
            if (i) prose.push({ gap: SP.tight });
            sh.linesOf(s, CW, TY.body, book).forEach(function (ln) { prose.push({ ln: ln, size: TY.body }); });
          });
          proseBlock(prose);
        }
      })();

      // ------------------------------------------------ Ad performance
      var PAD = S(-2), HEADH = S(4), CELLH = S(5) + S(-2);
      var LW = CW / (PHI * PHI * PHI);            // the image column: the column over φ³
      var TWd = LW - PAD * 2, THt = TWd * 1.25;   // 4:5, the portrait ad
      var RX = M + LW, RW = CW - LW;
      var AGEH = S(7) + S(1);
      var VIDH = CELLH, CURVEH = S(7) + S(2);
      var hasRet = function (a) { var r = a.retention || {}; return RETENTION.filter(function (k) { return num(r[k[0]]) !== null; }).length >= 2; };
      var cell = function (x, top, w, label, value, h) {
        var off = h ? (h - CELLH) / 2 : 0;
        tline(clip(label, w - PAD * 2, TY.small, book), x + PAD, top - off - PAD - TY.small * 0.8, TY.small, book, SOFT, w - PAD * 2);
        var na = value === 'Not available';
        var size = na ? TY.small : (String(value).length > 11 ? S(1) : S(2));
        tline(value, x + PAD, top - off - CELLH + PAD + 3, size, na ? book : med, na ? MUTE : INK, w - PAD * 2);
      };
      /* One creative, every objective it ran under (the user, 2026-10-01):
         the image once, then a line an objective and kind of result, each
         priced against its own result; the age split and the video figures
         from the line that spent the most. */
      var LH = S(4) + PAD;
      var LCOLS = [0.19, 0.16, 0.21, 0.2, 0.13, 0.11];
      var creativeH = function (c) {
        var lines = LH * (c.rows.length + 1);
        var body = Math.max(THt + PAD * 2, lines + (c.ageAd ? AGEH : 0));
        var vid = c.vidAd ? (hasRet(c.vidAd) ? Math.max(VIDH, CURVEH) : VIDH) : 0;
        var rl = c.remark ? sh.linesOf(c.remark, CW - PAD * 2 - S(6), TY.small, book) : [];
        return HEADH + body + vid + (rl.length ? PAD * 2 + rl.length * S(0) : 0);
      };
      function creativeCard(c) {
        var h = creativeH(c);
        need(h);
        var top = y;
        rect(M, top - HEADH, CW, HEADH, FILL);
        var meta = money(c.spend) + ' spent';
        var mw = width(meta, TY.small, book);
        tline(clip(c.name, CW - PAD * 3 - mw, TY.body, med), M + PAD, top - HEADH / 2 - TY.body * 0.34, TY.body, med, INK);
        right(meta, R - PAD, top - HEADH / 2 - TY.small * 0.34, TY.small, book, SOFT);
        var bodyTop = top - HEADH;
        var lines = LH * (c.rows.length + 1);
        var body = Math.max(THt + PAD * 2, lines + (c.ageAd ? AGEH : 0));
        thumbIn(c.img || c.rows[0], M + PAD, bodyTop - PAD, TWd, THt);
        if (!c.img) center('No image', M + PAD + TWd / 2, bodyTop - PAD - THt / 2 - 3, TY.small, book, MUTE);
        hline(bodyTop, M, R);
        pg.page.drawLine({ start: { x: RX, y: bodyTop }, end: { x: RX, y: bodyTop - body }, thickness: 0.48, color: EDGE });
        // A line an objective: what it was for, what it bought and at what price.
        var xs = [], acc = RX + PAD;
        LCOLS.forEach(function (f) { xs.push(acc); acc += (RW - PAD * 2) * f; });
        /* The head reads as every table's head in the report: a shaded band
           in Slate Regular over rows in Slate Book (the user, 2026-10-01:
           the labels and the figures were hard to tell apart). Each line
           carries what it spent, which its cost per result is read
           against. */
        var heads = ['Objective', 'Amount spent', 'Results', 'Cost per result', 'Reach', 'CTR'];
        rect(RX, bodyTop - LH, RW, LH, FILL);
        heads.forEach(function (t0, i) {
          var w0 = (RW - PAD * 2) * LCOLS[i];
          if (i) right(t0, xs[i] + w0, bodyTop - LH / 2 - TY.small * 0.34, TY.small, reg, INK);
          else tline(t0, xs[i], bodyTop - LH / 2 - TY.small * 0.34, TY.small, reg, INK);
        });
        c.rows.forEach(function (a, ri) {
          var ly = bodyTop - LH * (ri + 1);
          hline(ly, RX, R, FILL2, 0.6);
          var base = ly - LH / 2 - TY.small * 0.34;
          /* A figure not given reads as a dash: a line is a table row. */
          var got = function (v, f0) { return num(v) === null ? '\u2014' : f0(v); };
          var cells = [(OBJECTIVES[a.objective] || {}).name || 'Other', got(a.spend, money), countWord(a.results, a._label),
            a._cpr === null ? '\u2014' : cost(a._cpr) + (a._per1000 ? ' / 1,000' : ''), got(a.reach, fmt), got(a.ctr, pctv)];
          cells.forEach(function (t0, i) {
            var w0 = (RW - PAD * 2) * LCOLS[i];
            var f = i === 0 ? med : book;
            var tt = clip(String(t0), w0 - S(-1), TY.small, f);
            if (i) right(tt, xs[i] + w0, base, TY.small, f, INK);
            else tline(tt, xs[i], base, TY.small, f, INK);
          });
        });
        if (c.ageAd) {
          var a = c.ageAd, ay = bodyTop - lines;
          hline(ay, RX, R);
          tline('Results by age' + (c.rows.length > 1 ? '  ·  ' + ((OBJECTIVES[a.objective] || {}).name || '') : ''), RX + PAD, ay - PAD - TY.small * 0.8, TY.small, book, SOFT);
          var ages = AGE_BANDS.map(function (bd) { return num((a.age || {})[bd]); });
          var maxA = ages.reduce(function (m, v) { return Math.max(m, v || 0); }, 0) || 1;
          var slot = (RW - PAD * 2) / AGE_BANDS.length, bw = Math.min(S(4), slot * 0.46);
          var base2 = ay - AGEH + PAD + S(0), barH = AGEH - PAD * 2 - S(0) - S(1) - S(2);
          hline(base2, RX + PAD, R - PAD, FILL2, 0.6);
          AGE_BANDS.forEach(function (bd, i) {
            var v = ages[i], cx = RX + PAD + slot * i + slot / 2;
            var bh = v ? Math.max(0.8, barH * v / maxA) : 0;
            if (bh) rect(cx - bw / 2, base2, bw, bh, v === maxA ? INK : DATA2);
            center(v === null ? '' : v.toFixed(1) + '%', cx, base2 + bh + 3, TY.small, v === maxA ? med : book, INK);
            center(bd, cx, base2 - S(0) + 1, TY.small, book, MUTE);
          });
        }
        var yb = bodyTop - body;
        if (c.vidAd) {
          var va = c.vidAd, vh = hasRet(va) ? Math.max(VIDH, CURVEH) : VIDH;
          hline(yb, M, R);
          var vw = hasRet(va) ? CW / PHI : CW, v3 = vw / 3;
          [['Hook rate', pctShort(va.hook_rate)], ['Hold rate', pctShort(va.hold_rate)], ['Average play time', playW(va.avg_play)]].forEach(function (cc, i) {
            cell(M + v3 * i, yb, v3, cc[0], cc[1], vh);
            if (i) pg.page.drawLine({ start: { x: M + v3 * i, y: yb }, end: { x: M + v3 * i, y: yb - vh }, thickness: 0.48, color: EDGE });
          });
          if (hasRet(va)) {
            var cxs = M + vw;
            pg.page.drawLine({ start: { x: cxs, y: yb }, end: { x: cxs, y: yb - vh }, thickness: 0.48, color: EDGE });
            tline('Audience retention', cxs + PAD, yb - PAD - TY.small * 0.8, TY.small, book, SOFT);
            var ret = va.retention || {};
            var pts = RETENTION.map(function (k) { return { k: k, v: num(ret[k[0]]) }; }).filter(function (p0) { return p0.v !== null; });
            var px = cxs + PAD * 2, pw = R - PAD * 2 - px;
            var pb = yb - vh + PAD + S(0), ph = vh - PAD * 2 - S(0) - S(1) - S(1);
            var maxR = Math.max(100, pts.reduce(function (m, p0) { return Math.max(m, p0.v); }, 0));
            hline(pb, px, px + pw, FILL2, 0.6);
            var xy = pts.map(function (p0) {
              return { x: px + (RETENTION.map(function (r0) { return r0[0]; }).indexOf(p0.k[0])) * (pw / (RETENTION.length - 1)), y: pb + ph * p0.v / maxR, p: p0 };
            });
            xy.forEach(function (q, i) { if (i) pg.page.drawLine({ start: { x: xy[i - 1].x, y: xy[i - 1].y }, end: { x: q.x, y: q.y }, thickness: 1.2, color: INK }); });
            xy.forEach(function (q) {
              pg.page.drawCircle({ x: q.x, y: q.y, size: 1.8, color: INK });
              center(q.p.v.toFixed(0) + '%', q.x, q.y + 4, TY.small, book, INK);
              center(q.p.k[1], q.x, pb - S(0) + 1, TY.small, book, MUTE);
            });
          }
          yb -= vh;
        }
        var rl = c.remark ? sh.linesOf(c.remark, CW - PAD * 2 - S(6), TY.small, book) : [];
        if (rl.length) {
          hline(yb, M, R);
          var ry = yb - PAD - TY.small * 0.8;
          tline('Remarks', M + PAD, ry, TY.small, reg, INK);
          rl.forEach(function (ln) { sh.draw(pg.page, ln, M + PAD + S(6), ry, TY.small, INK); ry -= S(0); });
        }
        frame(M, top - h, CW, h);
        y = top - h - S(3);
      }
      /* The creatives, in the order of what they spent, each holding its
         objectives' lines in the report's objective order. */
      var creativesOf = function () {
        var by = {}, order = [];
        am.groups.forEach(function (g) {
          g.ads.forEach(function (a) {
            var k = adName(a.name);
            if (!by[k]) { by[k] = { name: k, rows: [], spend: 0 }; order.push(k); }
            by[k].rows.push(a); by[k].spend += num(a.spend) || 0;
          });
        });
        return order.map(function (k) {
          var c = by[k];
          var most = function (list) { return list.slice().sort(function (p, q) { return (num(q.spend) || 0) - (num(p.spend) || 0); })[0] || null; };
          c.img = c.rows.filter(function (a) { return thumbs[a.id]; })[0] || null;
          c.ageAd = most(c.rows.filter(function (a) { return a._age; }));
          c.vidAd = most(c.rows.filter(function (a) { return a._video; }));
          c.remark = uniq(c.rows.map(function (a) { return words(a.remark).trim(); }).filter(Boolean)).join('\n');
          return c;
        }).sort(function (p, q) { return q.spend - p.spend; });
      };

      (function performance() {
        if (!am.ads.length) return;
        newPage('Ad Performance');
        pageTitle('Ad Performance');
        if (first) {
          leadLine('Each objective ranked by what a result cost, then each creative with its results across objectives.');
          panel('How to read this', [
            'Cost per result is what it cost to get one lead, click or action. Compare it only between ads with the same objective, which is why each objective is ranked on its own.',
            'Each ad is priced only against the result its objective was set to get. A leads ad that also started a few chats is judged by its cost per lead; the chats came alongside, and the budget was not spent on them.',
            'Reach is how many people saw an ad; impressions is how many times it was shown. Frequency is impressions divided by reach.',
            'A creative that ran under two objectives shows one line for each. Compare the lines to see which goal it served best.'
          ]);
        } else {
          leadLine(GLOSSARY);
        }
        am.groups.forEach(function (g) {
          blockTitle(g.name + '  ·  ' + g.ads.length + ' ad' + (g.ads.length === 1 ? '' : 's') + '  ·  ' + money(g.spend), T.minH * (g.ads.length + 1));
          // The group ranked by what a result cost, the cheapest first and in weight.
          var ranked = g.ads.slice().sort(function (p, q) {
            if (p._cpr === null && q._cpr === null) return (num(q.spend) || 0) - (num(p.spend) || 0);
            if (p._cpr === null) return 1; if (q._cpr === null) return -1; return p._cpr - q._cpr;
          });
          /* The cheapest is marked only where the results are the same
             kind: a lead and an ad recall lift are not bought at one price. */
          var oneKind = uniq(g.ads.map(function (a) { return a._label + '|' + a._per1000; })).length === 1;
          var best = g.ads.length > 1 && oneKind && ranked[0] && ranked[0]._cpr !== null ? ranked[0] : null;
          var perK = g.ads.every(function (a) { return a._per1000; });
          /* Each result reads as its count and one short word, on one line
             where it fits and the word under the count where it does not;
             never broken inside a word. No result reads 0 Leads. */
          /* The ad's name takes the room the figures do not need, so a name
             reads whole on its line (the user, 2026-10-01: 2608W4_OldOwnorInves|t). */
          table([{ w: 0.27, align: 'left' }, { w: 0.17 }, { w: 0.15 }, { w: 0.15 }, { w: 0.16 }, { w: 0.1 }],
            [{ t: 'Ad', align: 'left' }, 'Period', 'Amount spent', 'Results', perK ? 'Per 1,000 reached' : 'Cost per result', 'CTR'],
            ranked.map(function (a) {
              var f = a === best ? med : book;
              return { cells: [{ t: adName(a.name) + (words(a.audience).trim() ? '\n' + words(a.audience).trim() + ' audience' : ''), f: f },
                { t: range(a.starts_on, a.ends_on), f: f }, { t: money(a.spend), f: f }, { t: countWord(a.results, a._label, 0.15, f), f: f },
                { t: a._cpr === null ? '\u2014' : cost(a._cpr) + (!perK && a._per1000 ? ' per 1,000' : ''), f: f },
                { t: num(a.ctr) === null ? '\u2014' : pctv(a.ctr), f: f }] };
            }), { labelCol: false });
          /* A full block step before the next objective, so each reads as
             its own table (the user, 2026-10-01). */
          y -= BLOCK;
        });
        var creatives = creativesOf();
        newPage('Creative Performance');
        pageTitle('Creative Performance');
        var videoRead = false;
        creatives.forEach(function (c) {
          creativeCard(c);
          if (first && c.vidAd && !videoRead) {
            videoRead = true;
            panel('How to read the video figures', [
              'Hook rate is the share of people who kept watching once the ad appeared. The first seconds decide whether somebody stops or scrolls past, so a strong hook rate means the opening is doing its job, and a low one shows where to sharpen the next creative.',
              'Hold rate is the share who kept watching after the opening had caught them: whether the message holds all the way through. A strong hold rate means the content is doing its job; a low one shows where people start to drop off.',
              GLOSSARY
            ]);
          }
        });
      })();

      // ------------------------------------------------ Insights and recommendations
      (function insights() {
        var blocks = [['What Worked', ins.worked], ['Areas to Improve', ins.fix], ['Recommended Focus for the Following Month', ins.focus]]
          .filter(function (b) { return words(b[1]).trim(); });
        if (!blocks.length) return;
        newPage('Insights and Recommendations');
        pageTitle('Insights and Recommendations');
        if (first) leadLine('What the period’s figures mean, and what happens next.');
        blocks.forEach(function (b, i) {
          if (i) gap(BLOCK);
          table([{ w: 1, align: 'left' }], [{ t: b[0], align: 'left' }], [{ cells: [{ items: pointTree(b[1]) }], split: true }]);
        });
      })();
    }

    // ------------------------------------------------------- Heads and feet
    /* The rate card's furniture on every page, the cover included, on the
       new margin: the Optima wordmark at S(2) top left and the client's name
       in small capitals on the right margin; PRIVATE & CONFIDENTIAL at the
       foot on the margin's line, the page count on the right. The line under
       it naming the draft or the version is gone (the user, 2026-10-01): it
       lifted the foot off the margin and the page read top heavy. */
    var n = pages.length;
    var label = String(rep.client_name || '').toUpperCase();
    var markW = width('ADspace', S(2), mark);
    var zhOn = ZH;
    pages.forEach(function (p, i) {
      pg = p;
      ZH = false;   // the head and foot are the template's, English throughout
      text('ADspace', M, HEAD_Y, S(2), mark, INK);
      if (label) {
        var lab = clip(label, CW - markW - S(4), TY.small, med);
        var lw = sh.lineWidth(sh.linesOf(lab, 1e6, TY.small, med)[0] || [], TY.small);
        tline(lab, R - lw, HEAD_Y + 0.9, TY.small, med, INK);
      }
      text('PRIVATE & CONFIDENTIAL', M, FOOT_Y, TY.small, med, INK);
      right('Page ' + (i + 1) + ' of ' + n, R, FOOT_Y, TY.small, book, INK);
    });
    ZH = zhOn;
    return Promise.resolve(n);
  }

  /* The report's name as the cover and the file print it. The first kind was
     stored as `Social Media Report` and is named Social Media Accounts Report
     since the builder took a second kind (2026-09-25), so the stored default
     reads as the new name; a title the team typed is kept. */
  function titleOf(rep) {
    var t = String((rep && rep.title) || '').trim();
    if (rep && rep.kind === 'ads') return t || 'Social Media Advertising Report';
    return !t || t === 'Social Media Report' ? 'Social Media Accounts Report' : t;
  }

  /* A file named the way the team would name it by hand: the client, the
     report and the period, and nothing a reader has to decode. The version
     and the draft mark are on the page itself. */
  function fileName(snap) {
    var rep = (snap && snap.report) || {};
    var name = [rep.client_name, titleOf(rep),
                periodWord(rep.period_start, rep.period_end)].filter(Boolean).join(' ');
    return name.replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ').trim() + '.pdf';
  }

  window.ADspaceSmReport = {
    render: render, model: model, topOf: topOf, fileName: fileName, periodWord: periodWord, titleOf: titleOf, resultWord: resultWord, shortResult: shortResult, adName: adName,
    engOf: engOf, growthOf: growthOf, fmt: fmt, PLATFORM_WORD: PLATFORM_WORD, TYPE_WORD: TYPE_WORD, METRIC_WORD: METRIC_WORD, METRICS: METRICS
  };
})();
