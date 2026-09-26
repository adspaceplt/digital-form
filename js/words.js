/*
 * The words every page shares.
 *
 * Each page used to carry its own dictionary, so "Link not recognised" was
 * written three times (a dictionary in creators.js, another in portal.js,
 * inline strings in review.js) and the status vocabulary four. Changing one
 * phrase meant finding every page that said it, and "one status vocabulary on
 * the console and the client page" held only as long as somebody remembered
 * it. Here it holds because there is one copy.
 *
 * What belongs here: anything a reader could meet on more than one page. The
 * covers, the status words, and the handful of actions every screen carries.
 * What does not: a phrase that exists on one screen only. A page keeps its own
 * dictionary for those and merges this underneath, so the shared line is the
 * default and a page can still say something particular where it must.
 *
 * A status word carries a colour, and the colour is not a language, so tones
 * live once in TONE rather than twice in en and zh. That is what makes the
 * console and the client page agree on both halves of a state.
 */
(function () {
  var W = {};

  W.en = {
    // Covers: what a page says when it has nothing to show.
    notFound: 'Link not recognised',
    notFoundText: 'Please contact your ADspace account manager.',
    passTitle: 'Access code',
    passText: 'Enter the access code provided.',
    passWrong: 'Incorrect access code.',
    noAccess: 'Access denied',
    noAccessText: 'Please contact your ADspace account manager.',
    failTitle: 'Unable to load',
    failText: 'Please refresh, or contact your ADspace account manager.',
    closed: 'Selection closed',
    closedText: 'Please contact your ADspace account manager for any changes.',
    nothing: 'No content pending review',
    nothingText: 'The next content set will appear here when it is ready for review.',
    loading: 'Loading…',

    // One status vocabulary, wherever a state is shown.
    step: {
      option: 'Offered', shortlisted: 'Shortlisted', backup: 'Backup',
      confirmed: 'Confirmed', pending_visit: 'Pending visit',
      pending_delivery: 'Pending delivery', pending_draft: 'Pending draft',
      submitted: 'Submitted', reviewing: 'Reviewing',
      changes: 'Changes requested', scheduled: 'Scheduled',
      posted: 'Posted', completed: 'Completed', withdrawn: 'Withdrawn'
    },
    svState: { enquired: 'Enquired', quoted: 'To quote', confirmed: 'Confirmed' },
    stage: {
      lead: 'Lead', contacted: 'Contacted', proposal: 'Proposal sent',
      active: 'Active', paused: 'Paused', past: 'Past'
    },
    rqState: {
      requested: 'Requested', reviewing: 'Reviewing', approved: 'Approved',
      declined: 'Declined', applied: 'Applied', withdrawn: 'Withdrawn'
    },
    rqKind: { upgrade: 'Upgrade', downgrade: 'Downgrade', cancel: 'Cancel', details: 'Change of details' },
    campState: { draft: 'Draft', open: 'Open for selection', production: 'In production', completed: 'Completed' },
    /* What a campaign is called on screen when its name would render as
       nothing. The record is never renamed behind anybody's back. */
    untitled: 'Untitled campaign',

    // The actions that appear on more than one screen.
    act: {
      save: 'Save', cancel: 'Cancel', back: 'Back', undo: 'Undo',
      signOut: 'Sign out', open: 'Open', download: 'Download', more: 'More actions'
    }
  };

  W.zh = {
    notFound: '链接无效',
    notFoundText: '请联系您的 ADspace 客户经理。',
    passTitle: '访问码',
    passText: '请输入访问码。',
    passWrong: '访问码不正确。',
    noAccess: '无访问权限',
    noAccessText: '请联系您的 ADspace 客户经理。',
    failTitle: '无法加载',
    failText: '请刷新页面，或联系您的 ADspace 客户经理。',
    closed: '选择已结束',
    closedText: '如需调整，请联系您的 ADspace 客户经理。',
    nothing: '暂无待审阅内容',
    nothingText: '下一批内容准备好后会显示在这里。',
    loading: '加载中…',

    step: {
      option: '候选', shortlisted: '已入围', backup: '备选',
      confirmed: '已确认', pending_visit: '待拍摄',
      pending_delivery: '待寄送', pending_draft: '待初稿',
      submitted: '已提交', reviewing: '审阅中',
      changes: '需修改', scheduled: '已排期',
      posted: '已发布', completed: '已完成', withdrawn: '已退出'
    },
    svState: { enquired: '已询价', quoted: '待报价', confirmed: '已确认' },
    stage: {
      lead: '潜在客户', contacted: '已联系', proposal: '已发提案',
      active: '合作中', paused: '暂停', past: '已结束'
    },
    rqState: {
      requested: '已提交', reviewing: '审核中', approved: '已批准',
      declined: '未批准', applied: '已生效', withdrawn: '已撤回'
    },
    rqKind: { upgrade: '升级', downgrade: '降级', cancel: '取消', details: '资料变更' },
    campState: { draft: '草稿', open: '待客户选择', production: '制作中', completed: '已完成' },
    untitled: '未命名项目',

    act: {
      save: '保存', cancel: '取消', back: '返回', undo: '撤销',
      signOut: '退出', open: '打开', download: '下载', more: '更多操作'
    }
  };

  /* The colour half of a state. One map, no language: a word and its tone
     travel together, so the console and the client page cannot show the same
     state in two colours. */
  W.TONE = {
    option: '', shortlisted: 'is-warn', backup: '',
    confirmed: 'is-ok', pending_visit: 'is-warn', pending_delivery: 'is-warn',
    pending_draft: 'is-warn', submitted: 'is-warn', reviewing: 'is-warn', changes: 'is-warn',
    scheduled: 'is-ok', posted: 'is-ok', completed: 'is-ok', withdrawn: 'is-danger',
    enquired: '', quoted: 'is-warn',
    lead: '', contacted: '', proposal: 'is-warn', active: 'is-ok', paused: 'is-warn', past: '',
    requested: 'is-warn', approved: 'is-ok', declined: '', applied: 'is-ok',
    draft: '', open: 'is-warn', production: 'is-warn'
  };
  W.tone = function (key) { return W.TONE[key] || ''; };

  /* A page's own words sit on top of these. One level deep is enough: every
     nested group here is a complete vocabulary, so a page that needed to
     change one word inside one would be breaking the rule the file exists to
     keep. */
  W.of = function (own) {
    var out = {};
    ['en', 'zh'].forEach(function (lang) {
      var merged = {};
      var base = W[lang], extra = (own && own[lang]) || {};
      Object.keys(base).forEach(function (k) { merged[k] = base[k]; });
      Object.keys(extra).forEach(function (k) { merged[k] = extra[k]; });
      out[lang] = merged;
    });
    return out;
  };

  window.ADspaceWords = W;
})();
