/*
 * The quotation website (/quote/, 2026-10-14): a prospect makes their own
 * quotation, as the canvas the user approved draws it (Website 1 to 6 and
 * the desk view).
 *
 *   1 What do you need?     social media, advertising, content production,
 *                           a KOC or KOL campaign, account verification
 *   2 Platforms and plan    the platforms, Without ads / With ads, the plan
 *                           (only where social media is asked for)
 *   3 Customise             extra contents, languages, the advertising
 *                           budget, the commitment, the one-off items
 *   4 Your details          name, work email, WhatsApp, brand, industry,
 *                           consent; Proceed quote makes the quotation
 *   5 Your quotation        priced by the database (`quote-request`, then
 *                           `quote_website_read` by its key, `?q=` in the
 *                           address), the rates at once; Download; beside
 *                           it Ready to proceed: when they would start and
 *                           whether they decide, then Proceed with this
 *                           quotation (`quote_proceed`, 2026-10-26), else
 *                           the colleague who took the lead. The link shows the latest revision the
 *                           team made of it. No billing is asked: the Letter
 *                           of Offer is the sales team's.
 *
 * No rate is shown before the quotation: the catalogue (`quote_catalogue`)
 * holds none. What the person picked is kept in this tab
 * (`adspace-quote`), so Back and a refresh keep it.
 */
(function () {
  'use strict';
  var API = window.ADspaceAPI, db = API && API.client;
  var cfg = window.ADSPACE_CONFIG || {};
  var KEEP = 'adspace-quote', LANG_KEY = 'adspace.quote.lang';
  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }

  var WORDS = {
    en: {
      lang: '中文', step: 'Step {n} of {m}', cont: 'Continue', back: 'Back',
      introT: 'Get your quotation',
      introP: 'Select the services your brand requires and receive your quotation instantly.',
      introH: 'What to expect',
      introSteps: ['Select the services you require.', 'Choose your plan and customise the contents, languages and commitment.',
        'Provide your contact details to receive the quotation immediately.', 'Proceed with the quotation when you are ready, and our team will contact you.'],
      introNote: 'This takes about three minutes.',
      start: 'Start',
      needT: 'What do you need?',
      need: {
        social: ['Social media management', 'Monthly content and account management'],
        ads: ['Advertising', 'Meta and TikTok campaigns, managed monthly'],
        content: ['Content production', 'Graphics and videos, charged per item'],
        koc: ['KOC or KOL campaign', 'Creators engaged for your brand'],
        verify: ['Account verification', 'Meta Verified and rednote Professional']
      },
      needNone: 'Select at least one service.',
      planT: 'Platforms and plan', platsH: 'Platforms', planH: 'Plan', noAds: 'Without ads', withAds: 'With ads',
      plan: 'Plan {p}', platOne: '1 platform', platUpTo: 'up to {n} platforms',
      contents: '{n} contents per month', mixOr: ' or ', mixAnd: ' and ',
      kindN: { graphic: ['{n} graphic', '{n} graphics'], reel: ['{n} reel of up to 60 seconds', '{n} reels of up to 60 seconds'] },
      budgetUpTo: 'Manages an advertising budget of up to RM\u00a0{b} per month',
      ratesLater: 'The rates will be shown on the final page.', budgetSep: 'The advertising budget is billed separately.',
      planNone: 'Select a platform and a plan.',
      customT: 'Customise', customPlan: 'Customise Plan {p}',
      extra: 'Additional contents per month', fewer: 'One fewer', more: 'One more',
      langs: 'Languages', langsNote: 'Your contents are shared across the languages selected, at no extra charge.',
      translate: 'Translate every content into each language selected', translateNote: 'Charged per content, per language',
      budget: 'Advertising budget per month', budgetIn: 'Up to RM {b} (managed within the plan)', budgetUp: 'Up to RM {b}',
      budgetAbove: 'Above RM {b}', budgetOver: 'Advertising budget above {c} {b}', budgetReq: 'Advertising budget', term: 'Commitment', months: '{n} months',
      once: 'Content production', onceNote: 'One-off, charged per item',
      koc: 'KOC creators', kocNone: 'None', kocN: '{n} creators', kocCustom: 'Custom list (quoted on request)',
      kol: 'KOL campaign (quoted on request)', verify: 'Account verification',
      detailsT: 'Your details', salutation: 'Salutation', name: 'Name', email: 'Work email', wa: 'WhatsApp number',
      waHint: 'Malaysia or Singapore number', brand: 'Brand', industry: 'Industry', optional: 'Optional',
      consent: 'I consent to ADspace keeping these details to prepare my quotation and to contact me about it.',
      freeMail: 'A work email address is recommended.',
      waBad: 'A valid Malaysia or Singapore registered WhatsApp number is required.',
      req: { name: 'Enter your name.', email: 'Enter a valid email address.', brand: 'Enter your brand.', consent: 'Tick the consent to continue.' },
      make: 'Proceed quote', making: 'Preparing…',
      quoteT: 'Your quotation', valid: 'Valid until {d}', expired: 'Expired on {d}', change: 'Change selection',
      line: 'Service', qty: 'Qty', rate: 'Rate ({c})', sub: 'Subtotal ({c})', onReq: 'Quoted on request',
      download: 'Download', chat: 'Chat on WhatsApp',
      billSep: 'The advertising budget is billed separately.',
      billManaged: 'The fees include the management of an advertising budget of up to {c}\u00a0{b} per month. The advertising budget is billed separately.',
      basis: 'Rates are based on the ADspace Rate Card v.{v}.',
      propT: 'Ready to proceed?', propP: 'Let us know when you would like to begin. Our team will contact you to finalise the details and prepare your onboarding plan.',
      startQ: 'When would you like to start?', starts: [['month', 'Within a month'], ['quarter', 'In 1 to 3 months']],
      decQ: 'Are you the decision maker?', decs: [['yes', 'Yes'], ['others', 'I will involve others']],
      propAsk: 'Proceed with this quotation', propAsking: 'Sending…', propNeed: 'Answer both questions to proceed.',
      propDone: 'Request received', propBy: 'Our team will contact you by {d} to finalise the details.',
      repT: 'Your representative', repP: '{n} will be pleased to go through the quotation and finalise the details with you.',
      repChat: 'Chat with {n} on WhatsApp', revised: 'Revised on {d}. It replaces {r}.', offer: 'Letter of Offer issued',
      monthSub: 'Monthly subtotal', commit: '{n}-month commitment ({p}%)', termAdj: '{n}-month term ({p}%)', monthExcl: 'Monthly excl. SST',
      sst: 'SST {p}%', sstNone: 'SST not applicable', onceSub: 'One-off subtotal', onceTag: 'One-off',
      monthlyNone: 'Monthly', firstNone: 'First month', oneOffNone: 'One-off total',
      monthly: 'Monthly incl. SST', firstExcl: 'First month excl. SST', first: 'First month incl. SST', oneOff: 'One-off incl. SST',
      newQuote: 'New quotation',
      err: {
        captcha: 'The security check did not complete. Please try again.', limit: 'This contact has made five quotations today. Please contact ADspace on WhatsApp.',
        'bad-whatsapp': 'A valid Malaysia or Singapore registered WhatsApp number is required.', 'bad-email': 'Enter a valid email address.',
        expired: 'This quotation has expired. Please make a new one.', 'not-proceeding': 'This quotation is closed. Please make a new one.',
        'not-found': 'This quotation could not be found.', 'bad-answer': 'Answer both questions to proceed.',
        empty: 'Select at least one service.', 'no-card': 'Quotations are unavailable at the moment. Please contact ADspace on WhatsApp.',
        any: 'Not sent. Please try again.'
      },
      lostT: 'Quotation not found', lostP: 'Please check the link, or make a new quotation.',
      offT: 'Unable to load', offP: 'Please refresh the page, or contact ADspace on WhatsApp.',
      plat: { meta: 'Meta', tiktok: 'TikTok', rednote: 'rednote', linkedin: 'LinkedIn' },
      lang3: { en: 'English', zh: '中文', ms: 'Malay' },
      ind: { Property: 'Property', 'F&B': 'Food and beverage', Retail: 'Retail', Wellness: 'Wellness', Lifestyle: 'Lifestyle',
        Automotive: 'Automotive', Tech: 'Technology', Education: 'Education', Other: 'Other' }
    },
    zh: {
      lang: 'EN', step: '第{n}步，共{m}步', cont: '继续', back: '返回',
      introT: '获取报价',
      introP: '选择品牌所需的服务，即可即时获得报价。',
      introH: '流程说明',
      introSteps: ['选择所需服务。', '选择方案，并设定内容、语言及合约期。', '填写联系资料，即可获得报价。', '准备好后确认报价，我们的团队将与您联系。'],
      introNote: '整个流程约需三分钟。',
      start: '开始',
      needT: '您需要什么服务？',
      need: {
        social: ['社交媒体管理', '每月内容制作与账号管理'],
        ads: ['广告投放', 'Meta 与 TikTok 广告，按月管理'],
        content: ['内容制作', '图文与视频，按件收费'],
        koc: ['KOC 或 KOL 合作', '为您的品牌邀约达人'],
        verify: ['账号认证', 'Meta 认证与小红书专业号']
      },
      needNone: '请至少选择一项服务。',
      planT: '平台与方案', platsH: '平台', planH: '方案', noAds: '不含广告', withAds: '含广告',
      plan: '方案 {p}', platOne: '1个平台', platUpTo: '最多{n}个平台',
      contents: '每月{n}条内容', mixOr: '，或 ', mixAnd: '、',
      kindN: { graphic: ['{n}条图文', '{n}条图文'], reel: ['{n}条短视频（60秒内）', '{n}条短视频（60秒内）'] },
      budgetUpTo: '代为管理每月最高 RM\u00a0{b} 的广告预算',
      ratesLater: '价格将在最后一页显示。', budgetSep: '广告预算另行收费。',
      planNone: '请选择平台与方案。',
      customT: '自定义', customPlan: '自定义方案 {p}',
      extra: '每月额外内容', fewer: '减少一条', more: '增加一条',
      langs: '语言', langsNote: '您的内容将以所选语言共用发布，不另收费。',
      translate: '将每条内容翻译为所选的每种语言', translateNote: '按每条内容、每种语言收费',
      budget: '每月广告预算', budgetIn: '最高 RM {b}（由方案代为管理）', budgetUp: '最高 RM {b}',
      budgetAbove: 'RM {b} 以上', budgetOver: '广告预算 {c} {b} 以上', budgetReq: '广告预算', term: '合约期', months: '{n}个月',
      once: '内容制作', onceNote: '一次性，按件收费',
      koc: 'KOC 达人', kocNone: '不需要', kocN: '{n}位达人', kocCustom: '自定名单（另行报价）',
      kol: 'KOL 合作（另行报价）', verify: '账号认证',
      detailsT: '您的资料', salutation: '称谓', name: '姓名', email: '工作邮箱', wa: 'WhatsApp 号码',
      waHint: '马来西亚或新加坡号码', brand: '品牌', industry: '行业', optional: '选填',
      consent: '本人同意 ADspace 保存以上资料，以便准备报价并就此与本人联系。',
      freeMail: '建议使用工作邮箱。',
      waBad: '请填写有效的马来西亚或新加坡 WhatsApp 号码。',
      req: { name: '请填写姓名。', email: '请填写有效的邮箱地址。', brand: '请填写品牌。', consent: '请勾选同意后继续。' },
      make: '查看报价', making: '准备中…',
      quoteT: '您的报价', valid: '有效期至 {d}', expired: '已于 {d} 过期', change: '修改选择',
      line: '服务', qty: '数量', rate: '单价 ({c})', sub: '小计 ({c})', onReq: '另行报价',
      download: '下载', chat: 'WhatsApp 咨询',
      billSep: '广告预算另行收费。',
      billManaged: '费用包括代为管理每月最高 {c}\u00a0{b} 的广告预算。广告预算另行收费。',
      basis: '价格依据 ADspace 价目表 v.{v}。',
      propT: '准备好开始了吗？', propP: '请告诉我们您希望何时开始。我们的团队将与您联系，确认细节并准备您的启动计划。',
      startQ: '您希望何时开始？', starts: [['month', '一个月内'], ['quarter', '一至三个月内']],
      decQ: '您是否为决策人？', decs: [['yes', '是'], ['others', '需与他人商议']],
      propAsk: '确认此报价', propAsking: '提交中…', propNeed: '请回答以上两个问题。',
      propDone: '已收到您的确认', propBy: '我们的团队将于 {d} 前与您联系，确认细节。',
      repT: '您的专属顾问', repP: '{n} 将与您详细说明报价并确认细节。',
      repChat: '通过 WhatsApp 联系 {n}', revised: '已于 {d} 修订，取代 {r}。', offer: '已发出服务确认函',
      monthSub: '每月小计', commit: '{n}个月合约优惠（{p}%）', termAdj: '{n}个月合约附加费（{p}%）', monthExcl: '每月（未含 SST）',
      sst: 'SST {p}%', sstNone: '不适用 SST', onceSub: '一次性小计', onceTag: '一次性',
      monthlyNone: '每月', firstNone: '首月', oneOffNone: '一次性合计',
      monthly: '每月（含 SST）', firstExcl: '首月（未含 SST）', first: '首月（含 SST）', oneOff: '一次性（含 SST）',
      newQuote: '重新报价',
      err: {
        captcha: '安全验证未完成，请重试。', limit: '此联系方式今日已获取五份报价，请通过 WhatsApp 联系 ADspace。',
        'bad-whatsapp': '请填写有效的马来西亚或新加坡 WhatsApp 号码。', 'bad-email': '请填写有效的邮箱地址。',
        expired: '本报价已过期，请重新报价。', 'not-proceeding': '本报价已结束，请重新报价。',
        'not-found': '找不到此报价。', 'bad-answer': '请回答以上两个问题。',
        empty: '请至少选择一项服务。', 'no-card': '报价暂不可用，请通过 WhatsApp 联系 ADspace。',
        any: '未能提交，请重试。'
      },
      lostT: '找不到报价', lostP: '请检查链接，或重新报价。',
      offT: '无法加载', offP: '请刷新页面，或通过 WhatsApp 联系 ADspace。',
      plat: { meta: 'Meta', tiktok: 'TikTok', rednote: '小红书', linkedin: 'LinkedIn' },
      lang3: { en: 'English', zh: '中文', ms: '马来文' },
      ind: { Property: '房地产', 'F&B': '餐饮', Retail: '零售', Wellness: '健康养生', Lifestyle: '生活方式',
        Automotive: '汽车', Tech: '科技', Education: '教育', Other: '其他' }
    }
  };
  // A graphic is named by its kind (the user, 2026-10-14: a plan's graphic is a static post, a carousel or a GIF).
  var EN_KIND = { graphic: 'Graphic (Static)', carousel: 'Graphic (Carousel)', gif: 'Graphic (GIF)' };
  var ZH_KIND = { graphic: '图文（静态）', carousel: '图文（轮播）', gif: '图文（GIF 动图）', reel30: '短视频（30秒内）',
    reel: '短视频（60秒内）', video120: '短视频（120秒内）' };
  // The graphics together, cheapest first, then the reels, then the longer video.
  var KIND_ORDER = ['graphic', 'gif', 'carousel', 'reel30', 'reel', 'video120'];
  var GRAPHICS = ['graphic', 'gif', 'carousel'];
  function byKind(a, b) {
    var x = KIND_ORDER.indexOf(a.kind), y = KIND_ORDER.indexOf(b.kind);
    return (x < 0 ? 99 : x) - (y < 0 ? 99 : y);
  }
  /* The contact sheet's salutations, which quote_website_create accepts. */
  var SALUTATIONS = ['Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', "Dato'", 'Datin', 'Datuk', "Dato' Sri", 'Datin Sri',
    'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik'];
  var SAL_ZH = { Mr: '先生', Ms: '女士', Mrs: '太太', Mdm: '夫人', Dr: '博士', Prof: '教授' };
  var INDUSTRIES = ['Property', 'F&B', 'Retail', 'Wellness', 'Lifestyle', 'Automotive', 'Tech', 'Education', 'Other'];
  var FREE = /@(gmail|googlemail|yahoo|ymail|hotmail|outlook|live|msn|icloud|me|aol|proton|protonmail|qq|163|126)\./i;
  var TERMS = window.ADspaceMoney.QUOTE_TERMS;

  var lang = 'en';
  try { if (localStorage.getItem(LANG_KEY) === 'zh') lang = 'zh'; } catch (e) {}
  function t() { return WORDS[lang]; }
  function f(s, o) { return String(s).replace(/\{(\w+)\}/g, function (m, k) { return o && o[k] != null ? o[k] : m; }); }
  /* Figures through the one money formatter (js/money.js), its sign left to the table head. */
  var MON = window.ADspaceMoney;
  function n0(v) { return MON.money(v, 'MY').replace(/^RM /, ''); }
  function n2(v) {
    var x = Number(v || 0), s = MON.money2(Math.abs(x), 'MY').replace(/^RM /, '');
    return x < 0 ? '(' + s + ')' : s;
  }
  function day(iso, long) {
    var C = window.ADspaceClock;
    if (!iso) return '';
    if (long && lang !== 'zh') {
      var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
      var M = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      return m ? Number(m[3]) + ' ' + M[Number(m[2]) - 1] + ' ' + m[1] : iso;
    }
    return C ? C.date(String(iso).slice(0, 10), { zh: lang === 'zh' }) : iso;
  }
  function waDigits(s) {
    var d = String(s || '').replace(/[^0-9]/g, '');
    /* As the database reads it (quote_website_number): a leading 0 is
       Malaysia, eight digits Singapore, nine or ten from 1 a Malaysian mobile. */
    if (/^0[1-9]/.test(d)) d = '6' + d;
    else if (/^[3689][0-9]{7}$/.test(d)) d = '65' + d;
    else if (/^1[0-9]{8,9}$/.test(d)) d = '60' + d;
    return d;
  }
  function waOk(d) { return /^(60(1[0-9]{8,9}|7[0-9]{7,8})|65[0-9]{8})$/.test(d); }
  function key8() {
    var a = '23456789abcdefghjkmnpqrstuvwxyz', out = '', buf = new Uint8Array(24);
    (window.crypto || window.msCrypto).getRandomValues(buf);
    for (var i = 0; i < buf.length && out.length < 20; i++) if (buf[i] < 248) out += a.charAt(buf[i] % 31);
    return out;
  }

  /* What the person picked, kept in this tab while they go through the
     steps (a refresh keeps their place); the opening page starts afresh,
     nothing chosen or typed carried over (the user, 2026-10-14). */
  function blank() {
    return { need: { social: true, ads: false, content: false, koc: false, verify: false }, platforms: ['meta'], withAds: false,
      plan: null, extra: {}, langs: ['en'], translate: false, budget: null, term: 12, once: {}, koc: '', kol: false, verify: [],
      contact: { salutation: '', name: '', email: '', whatsapp: '', brand: '', industry: '', consent: false }, step: 'intro', idem: null };
  }
  var S = blank();
  try { var kept = JSON.parse(sessionStorage.getItem(KEEP) || 'null'); if (kept && kept.need) S = Object.assign(S, kept); } catch (e) {}
  function keep() { try { sessionStorage.setItem(KEEP, JSON.stringify(S)); } catch (e) {} }

  var CAT = null, Q = null;
  /* Held in this page alone, never kept in the tab: the contact for Change
     selection, once the quotation is made (the user, 2026-10-14: "dont
     cache my record"). */
  var madeBy = null;
  var root = function () { return $('qsRoot'); };

  function planOf() { return CAT && S.plan ? CAT.plans.filter(function (p) { return p.slug === S.plan; })[0] || null : null; }
  function steps() {
    var a = ['need'];
    if (S.need.social) a.push('plan');
    a.push('custom', 'details');
    return a;
  }
  function monthly() { return Boolean((S.need.social && planOf()) || S.need.ads); }
  function adsAsked() { var p = S.need.social ? planOf() : null; return Boolean(S.need.ads || (p && p.ads)); }

  /* The contents a plan takes more of each month. A plan's graphic is any of
     the three, so each is offered where the plan holds graphics. */
  function extrasOf(p) {
    var kinds = (p.mix || []).reduce(function (a, m) { return a.concat(Object.keys(m)); }, []);
    return CAT.contents.filter(function (c) {
      return kinds.indexOf(c.kind) >= 0 || (GRAPHICS.indexOf(c.kind) >= 0 && kinds.indexOf('graphic') >= 0);
    }).sort(byKind);
  }
  /* One-off contents: with a plan, only those its additional contents do not
     already offer, so a format is never asked twice (the user, 2026-10-14). */
  function onceList() {
    var p = S.need.social ? planOf() : null;
    var monthlyOnes = p ? extrasOf(p).map(function (c) { return c.slug; }) : [];
    return CAT.contents.filter(function (c) { return monthlyOnes.indexOf(c.slug) < 0; }).sort(byKind);
  }

  function selection() {
    var p = S.need.social ? planOf() : null, once = [];
    var sel = { term: monthly() ? S.term : 1 };
    if (p) {
      sel.plan = p.slug;
      sel.platforms = S.platforms.slice();
      var ex = {};
      Object.keys(S.extra).forEach(function (k) { if (S.extra[k] > 0) ex[k] = S.extra[k]; });
      sel.extra = ex;
      sel.langs = S.langs.slice();
      sel.translate = S.translate && S.langs.length > 1;
    }
    if (adsAsked()) sel.budget = S.budget == null ? (p && p.ad_budget ? 0 : (CAT.budgets[0] || 0)) : S.budget;
    if (S.need.content) onceList().forEach(function (c) { if (S.once[c.slug] > 0) once.push({ slug: c.slug, qty: S.once[c.slug] }); });
    if (S.need.koc && S.koc) once.push({ slug: S.koc, qty: 1 });
    if (S.need.koc && S.kol && CAT.kol) once.push({ slug: CAT.kol, qty: 1 });
    if (S.need.verify) S.verify.forEach(function (k) { once.push({ slug: k, qty: 1 }); });
    if (once.length) sel.once = once;
    return sel;
  }

  // ---- Drawing ----------------------------------------------------------------
  function frame(body, foot) {
    var a = steps(), i = a.indexOf(S.step) + 1;
    return '<div class="qs-step" data-shown><div class="qs-progress"><span>' + esc(f(t().step, { n: i, m: a.length + 1 })) + '</span>' +
      '<div class="qs-track"><i style="width:' + Math.round(i / (a.length + 1) * 100) + '%"></i></div></div>' + body +
      '<p class="msg" id="qsMsg" role="status"></p></div>' +
      '<div class="qs-foot">' + foot + '</div>';
  }
  function navFoot(first) {
    return (first ? '' : '<button class="btn qs-back" type="button" data-a="back">' + esc(t().back) + '</button>') +
      '<button class="btn btn-primary" type="button" data-a="next">' + esc(S.step === 'details' ? t().make : t().cont) + '</button>';
  }
  // The choice's mark at the card's right edge: an empty ring, the ink disc with its tick once chosen.
  var MARK = '<span class="qs-mark" aria-hidden="true"><svg viewBox="0 0 16 16" width="12" height="12"><path d="M3.5 8.4l2.9 2.9 6.1-6.6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>';
  function pick(type, name, value, on, title, sub) {
    return '<label class="qs-pick' + (on ? ' is-on' : '') + '"><input type="' + type + '" name="' + esc(name) + '" value="' + esc(value) + '"' +
      (on ? ' checked' : '') + '><span class="qs-text"><b>' + esc(title) + '</b>' + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span>' + MARK + '</label>';
  }
  function chip(name, value, on, label) {
    return '<label class="qs-chip' + (on ? ' is-on' : '') + '"><input type="checkbox" name="' + esc(name) + '" value="' + esc(value) + '"' +
      (on ? ' checked' : '') + '><span class="qs-text">' + esc(label) + '</span>' + MARK + '</label>';
  }
  function stepper(group, slug, label, n, sub) {
    return '<div class="qs-stepper"><span>' + esc(label) + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span><span class="qs-count">' +
      '<button class="btn qs-pm" type="button" data-step="-1" data-group="' + group + '" data-slug="' + esc(slug) + '" aria-label="' + esc(t().fewer + ': ' + label) + '"' + (n ? '' : ' disabled') + '>−</button>' +
      '<b aria-live="polite">' + n + '</b>' +
      '<button class="btn qs-pm" type="button" data-step="1" data-group="' + group + '" data-slug="' + esc(slug) + '" aria-label="' + esc(t().more + ': ' + label) + '">+</button></span></div>';
  }
  function seg(id, label, options, value, quiet) {
    return '<div class="field">' + (quiet ? '' : '<span class="field-label" id="' + id + 'L">' + esc(label) + '</span>') +
      '<select class="select" id="' + id + '" data-seg ' + (quiet ? 'aria-label="' + esc(label) + '"' : 'aria-labelledby="' + id + 'L"') + '>' +
      options.map(function (o) { return '<option value="' + esc(o[0]) + '"' + (String(o[0]) === String(value) ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') +
      '</select></div>';
  }
  // A category of choices: its heading over its items, set apart from the next by a hairline.
  function sec(head, body, forId) {
    return '<section class="qs-sec">' + (forId ? '<label class="qs-sec-h" for="' + forId + '">' : '<h2 class="qs-sec-h">') + esc(head) +
      (forId ? '</label>' : '</h2>') + body + '</section>';
  }
  function contentName(c) { return lang === 'zh' && ZH_KIND[c.kind] ? ZH_KIND[c.kind] : EN_KIND[c.kind] || c.name; }
  /* What a plan's contents are, so a visitor knows what the count covers
     (the user, 2026-10-14): "4 contents per month: 2 graphics and 2 reels". */
  function mixLine(p) {
    var K = t().kindN;
    return (p.mix || []).map(function (m) {
      return ['graphic', 'reel'].concat(Object.keys(m).filter(function (k) { return k !== 'graphic' && k !== 'reel'; }))
        .filter(function (k) { return m[k]; }).map(function (k) {
          var w = K[k] || ['{n} ' + k, '{n} ' + k];
          return f(w[m[k] === 1 ? 0 : 1], { n: m[k] });
        }).join(t().mixAnd);
    }).join(t().mixOr);
  }
  function planLine(p) {
    var mix = mixLine(p);
    var parts = [f(t().contents, { n: p.contents }) + (mix ? (lang === 'zh' ? '：' : ': ') + mix : '')];
    if (p.ad_budget) parts.push(f(t().budgetUpTo, { b: n0(p.ad_budget) }));
    return parts.join('\n');   // a line each: the contents, then the budget
  }

  // The opening page: what the quotation is for, what is asked and what follows (the user, 2026-10-14).
  function paintIntro() {
    return '<div class="qs-step qs-intro" data-shown><h1 class="qs-title">' + esc(t().introT) + '</h1><p class="qs-lead">' + esc(t().introP) + '</p>' +
      '<section class="qs-sec"><h2 class="qs-sec-h">' + esc(t().introH) + '</h2><ol class="qs-steps">' +
        t().introSteps.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ol></section>' +
      '<p class="qs-note">' + esc(t().introNote) + '</p></div>' +
      '<div class="qs-foot"><a class="btn" href="' + esc(waLink(null)) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(t().chat) + '</a>' +
      '<button class="btn btn-primary" type="button" data-a="start">' + esc(t().start) + '</button></div>';
  }

  function paintNeed() {
    var N = t().need;
    return frame('<h1 class="qs-title">' + esc(t().needT) + '</h1><div class="qs-list">' +
      ['social', 'ads', 'content', 'koc', 'verify'].filter(function (k) {
        return k !== 'koc' || (CAT.koc.length || CAT.kol);
      }).filter(function (k) { return k !== 'verify' || CAT.verify.length; }).map(function (k) {
        return pick('checkbox', 'need', k, S.need[k], N[k][0], N[k][1]);
      }).join('') + '</div>', navFoot());
  }

  function paintPlan() {
    var plans = CAT.plans.filter(function (p) { return Boolean(p.ads) === Boolean(S.withAds); });
    return frame('<h1 class="qs-title">' + esc(t().planT) + '</h1><div class="qs-secs">' +
      sec(t().platsH, '<div class="qs-chips qs-two">' + CAT.platforms.map(function (p) { return chip('plat', p, S.platforms.indexOf(p) >= 0, t().plat[p] || p); }).join('') + '</div>') +
      sec(t().planH, seg('qsAds', t().need.ads[0], [['no', t().noAds], ['ads', t().withAds]], S.withAds ? 'ads' : 'no', true) +
        '<div class="qs-list">' + plans.map(function (p) {
          return pick('radio', 'plan', p.slug, S.plan === p.slug,
            f(t().plan, { p: p.plan }) + ' · ' + (p.platforms === 1 ? t().platOne : f(t().platUpTo, { n: p.platforms })), planLine(p));
        }).join('') + '</div><p class="qs-note">' + esc((S.withAds ? t().budgetSep + ' ' : '') + t().ratesLater) + '</p>') +
      '<div id="qsExtraBox">' + extrasHtml() + '</div></div>', navFoot());
  }
  /* Additional contents sit under the plan they add to (the user,
     2026-10-14: on the next page they read as choosing the plan's own). */
  function extrasHtml() {
    var p = planOf();
    if (!p) return '';
    return sec(t().extra, extrasOf(p).map(function (c) { return stepper('extra', c.slug, contentName(c), S.extra[c.slug] || 0); }).join(''));
  }

  function budgetOptions() {
    var p = S.need.social ? planOf() : null, cover = p && p.ad_budget ? Number(p.ad_budget) : 0, out = [];
    if (cover) out.push([0, f(t().budgetIn, { b: n0(cover) })]);
    CAT.budgets.forEach(function (b) { if (b > cover) out.push([b, f(t().budgetUp, { b: n0(b) })]); });
    var top = CAT.budgets[CAT.budgets.length - 1];
    if (top) out.push([-1, f(t().budgetAbove, { b: n0(top) })]);
    return out;
  }

  function paintCustom() {
    var p = S.need.social ? planOf() : null, h = '';
    if (p) {
      h += sec(t().langs, '<div class="qs-chips qs-three">' +
        ['en', 'zh', 'ms'].map(function (l) { return chip('lang', l, S.langs.indexOf(l) >= 0, t().lang3[l]); }).join('') + '</div>' +
        '<p class="qs-note">' + esc(t().langsNote) + '</p>' +
        (CAT.translation && S.langs.length > 1 ? pick('checkbox', 'translate', '1', S.translate, t().translate, t().translateNote) : ''));
    }
    if (adsAsked()) {
      var opts = budgetOptions(), cur = S.budget == null ? opts[0][0] : S.budget;
      if (!opts.some(function (o) { return String(o[0]) === String(cur); })) cur = opts[0][0];
      S.budget = Number(cur);
      h += sec(t().budget, '<select class="select" id="qsBudget">' +
        opts.map(function (o) { return '<option value="' + o[0] + '"' + (String(o[0]) === String(cur) ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') + '</select>' +
        '<p class="qs-note">' + esc(t().budgetSep) + '</p>', 'qsBudget');
    }
    // Five terms: a select, as the budget is (a segment holds four at most).
    if (monthly()) h += sec(t().term, '<select class="select" id="qsTerm">' + TERMS.map(function (m) {
      return '<option value="' + m + '"' + (m === S.term ? ' selected' : '') + '>' + esc(f(t().months, { n: m })) + '</option>'; }).join('') + '</select>', 'qsTerm');
    if (S.need.content && onceList().length) {
      h += sec(t().once, '<p class="qs-note">' + esc(t().onceNote) + '</p>' +
        onceList().map(function (c) { return stepper('once', c.slug, contentName(c), S.once[c.slug] || 0); }).join(''));
    }
    if (S.need.koc) {
      var cr = '';
      if (CAT.koc.length) {
        cr += '<div class="field"><label class="field-label" for="qsKoc">' + esc(t().koc) + '</label><select class="select" id="qsKoc">' +
          [['', t().kocNone]].concat(CAT.koc.map(function (k) { return [k.slug, k.creators ? f(t().kocN, { n: k.creators }) : t().kocCustom]; }))
            .map(function (o) { return '<option value="' + esc(o[0]) + '"' + (o[0] === S.koc ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') +
          '</select></div>';
      }
      if (CAT.kol) cr += pick('checkbox', 'kol', '1', S.kol, t().kol, '');
      if (cr) h += sec(t().need.koc[0], cr);
    }
    if (S.need.verify) {
      h += sec(t().verify, '<div class="qs-list">' +
        CAT.verify.map(function (v) { return pick('checkbox', 'verify', v.slug, S.verify.indexOf(v.slug) >= 0, v.name, ''); }).join('') + '</div>');
    }
    return frame('<h1 class="qs-title">' + esc(p ? f(t().customPlan, { p: p.plan }) : t().customT) + '</h1><div class="qs-secs">' + h + '</div>', navFoot());
  }

  function field(id, label, req, html, hint) {
    return '<div class="field"><label class="field-label" for="' + id + '">' + esc(label) + '</label>' + html +
      (hint ? '<span class="qs-hint">' + esc(hint) + '</span>' : '') + '<span class="msg" id="' + id + 'Msg"></span></div>';
  }
  function paintDetails() {
    var c = S.contact;
    return frame('<h1 class="qs-title">' + esc(t().detailsT) + '</h1><form class="qs-form" id="qsDetails" novalidate>' +
      field('qsSal', t().salutation, false, '<select class="select" id="qsSal"><option value="">' + esc(t().optional) + '</option>' +
        SALUTATIONS.map(function (x) { return '<option value="' + esc(x) + '"' + (c.salutation === x ? ' selected' : '') + '>' + esc((lang === 'zh' && SAL_ZH[x]) || x) + '</option>'; }).join('') + '</select>') +
      field('qsName', t().name, true, '<input class="input" id="qsName" autocomplete="name" placeholder="John Doe" aria-required="true" value="' + esc(c.name) + '">') +
      field('qsEmail', t().email, true, '<input class="input" id="qsEmail" type="email" autocomplete="email" placeholder="email@adspace.me" aria-required="true" value="' + esc(c.email) + '">') +
      field('qsWa', t().wa, true, '<input class="input" id="qsWa" type="tel" inputmode="numeric" autocomplete="tel" placeholder="012-345 6789" aria-required="true" value="' + esc(c.whatsapp) + '">', t().waHint) +
      field('qsBrand', t().brand, true, '<input class="input" id="qsBrand" autocomplete="organization" placeholder="ADspace Advertising" aria-required="true" value="' + esc(c.brand) + '">') +
      field('qsInd', t().industry, false, '<select class="select" id="qsInd"><option value="">' + esc(t().optional) + '</option>' +
        INDUSTRIES.map(function (i) { return '<option value="' + esc(i) + '"' + (c.industry === i ? ' selected' : '') + '>' + esc(t().ind[i]) + '</option>'; }).join('') + '</select>') +
      '<label class="qs-consent"><input type="checkbox" id="qsConsent"' + (c.consent ? ' checked' : '') + '>' + MARK + '<span class="qs-text">' + esc(t().consent) + '</span></label>' +
      '<span class="msg" id="qsConsentMsg"></span><div class="qs-cf" data-cf></div></form>', navFoot());
  }

  /* A Singapore lead's quotation is in S$: its totals say so and carry the
     rate it was priced at, which turns the card's own RM budgets too
     (2026-10-15). */
  function qc() { return Q && Q.totals && Q.totals.currency === 'SGD' ? 'S$' : 'RM'; }
  function qb(n) { var fx = Q && Q.totals && Number(Q.totals.fx); return fx ? Math.round(Number(n) / fx) : Number(n); }
  /* A monthly line running months of its own makes the month's figures the
     first month's, named so (2026-10-18), as the Letter of Offer does. */
  function ownMonths(tt) {
    return ((Q && Q.lines) || []).some(function (l) { return l.basis === 'month' && l.months && Number(l.months) !== Number(tt.term); });
  }
  /* The first month holds the one-off items too (the user, 2026-10-18). */
  function sum2(a, b) { return Math.round((Number(a || 0) + Number(b || 0)) * 100) / 100; }
  function firstIncl(tt) { return sum2(tt.month.incl, tt.once && tt.once.incl); }
  /* SST said as the Letter of Offer says it (ADspaceMoney.sstApplies): where
     it does not apply, its row reads not applicable, no total names it and
     the row before it, the same figure, is left out. */
  function sstOn(tt) { return window.ADspaceMoney.sstApplies(tt.sst_pct); }
  function word(tt, key) { return sstOn(tt) ? t()[key] : t()[key + 'None']; }
  function totalsRows(tt) {
    /* The rows are ADspaceMoney.quoteRows', one copy (2026-10-22, QT-4). */
    var w = t(), on = sstOn(tt);
    var sst = on ? f(w.sst, { p: tt.sst_pct }) : w.sstNone;
    var WORD = { monthSub: w.monthSub, onceSub: w.onceSub, firstExcl: w.firstExcl, monthExcl: w.monthExcl, sst: sst,
      first: word(tt, 'first'), monthly: word(tt, 'monthly'), oneOff: word(tt, 'oneOff') };
    var r = window.ADspaceMoney.quoteRows(tt, Q && Q.lines, on).map(function (x) {
      var label = x[0] === 'term' ? f(tt.term_pct < 0 ? w.commit : w.termAdj, { n: tt.term, p: Math.abs(tt.term_pct) }) : WORD[x[0]];
      return x[2] ? [label, qc() + ' ' + n2(x[1]), 1] : [label, n2(x[1])];
    });
    return r;
  }
  function paintQuote() {
    var q = Q, tt = q.totals || {}, offer = q.status === 'offer', gone = !offer && q.valid_until < q.today;
    var status = offer ? '<span class="chip-state is-ok">' + esc(t().offer) + '</span>'
      : gone ? '<span class="chip-state is-off">' + esc(f(t().expired, { d: day(q.valid_until) })) + '</span>'
      : '<span class="chip-state is-ok">' + esc(f(t().valid, { d: day(q.valid_until) })) + '</span>';
    var lines = (q.lines || []).map(function (l) {
      var d = (l.detail || [])[0];
      return '<div class="qs-row"><span class="qs-what">' + esc(l.label).replace(/\b(RM|S\$) (?=\d)/g, '$1\u00a0') + (Number(l.qty) > 1 ? '<span class="qs-calc">' + esc(l.qty + ' × ' + n2(l.rate)) + '</span>' : '') +
        (d ? '<small>' + esc(d) + '</small>' : '') + (l.basis === 'once' ? '<small>' + esc(t().onceTag) + '</small>' : '') + '</span>' +
        '<span class="qs-num qs-q">' + esc(l.qty) + '</span><span class="qs-num qs-r">' + esc(n2(l.rate)) + '</span><span class="qs-num">' + esc(n2(l.amount)) + '</span></div>';
    }).join('') + (tt.on_request || []).map(function (x) {
      return '<div class="qs-row"><span class="qs-what">' + esc(x === 'budget' ? budgetOnRequest() : x) + '</span>' +
        '<span class="qs-num qs-mute qs-onreq">' + esc(t().onReq) + '</span></div>';
    }).join('');
    var notes = [], managed = managedBudget(q);
    if (managed) notes.push(f(t().billManaged, { c: qc(), b: n0(qb(managed)) }));
    else if (Number(tt.budget) > 0 || (q.lines || []).some(function (l) { return l.kind === 'ads' || l.kind === 'plan'; })) notes.push(t().billSep);
    /* The validity is the status line's on screen; the PDF states it in its
       remarks (2026-10-20, QTE-1). */
    notes.push(f(t().basis, { v: q.version }));
    var aside = gone ? '' : '<aside class="qs-side" id="qsSide">' + sideHtml(q) + '</aside>';
    return '<div class="qs-quote" data-shown><section class="qs-main">' +
      (gone || offer || q.revised ? '' : '<button class="btn btn-quiet qs-change" type="button" data-a="change"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M19 12H5"/><path d="m12 19-7-7 7-7"/></svg>' + esc(t().change) + '</button>') +
      '<div class="qs-head"><h1 class="qs-title">' + esc(t().quoteT) + '</h1><span class="qs-meta">' + esc(q.ref + ' · ' + q.brand) + '</span><span class="qs-status">' + status + '</span>' +
        (q.revised ? '<span class="qs-meta">' + esc(f(t().revised, { d: day(q.issued_at), r: q.first_ref })) + '</span>' : '') + '</div>' +
      '<div class="qs-table"><div class="qs-row qs-headrow"><span>' + esc(t().line) + '</span><span class="qs-num qs-q">' + esc(t().qty) + '</span>' +
      '<span class="qs-num qs-r">' + esc(f(t().rate, { c: qc() })) + '</span><span class="qs-num">' + esc(f(t().sub, { c: qc() })) + '</span></div>' + lines + '</div>' +
      '<dl class="qs-tot">' + totalsRows(tt).map(function (x) { return '<div' + (x[2] ? ' class="is-total"' : '') + '><dt>' + esc(x[0]) + '</dt><dd>' + esc(x[1]) + '</dd></div>'; }).join('') + '</dl>' +
      '<div class="qs-acts"><button class="btn" type="button" data-a="pdf">' + esc(t().download) + '</button></div>' +
      '<div class="qs-notes">' + notes.map(function (n) { return '<span>' + esc(n) + '</span>'; }).join('') + '</div>' +
      (gone ? '<button class="btn btn-primary" type="button" data-a="new">' + esc(t().newQuote) + '</button>' : '') +
      '</section>' + aside + '</div>';
  }
  /* The advertising budget the quotation's fees manage each month: the
     budget chosen past the plan's cover, else the plan's own cover as the
     card read beside this quotation states it (the same version alone).
     None where the budget is quoted on request. */
  function managedBudget(q) {
    var tt = q.totals || {};
    if ((tt.on_request || []).indexOf('budget') >= 0) return 0;
    if (Number(tt.budget) > 0) return Number(tt.budget);
    var slug = q.selection && q.selection.plan;
    if (!slug || !CAT || String(CAT.version) !== String(q.version)) return 0;
    var p = CAT.plans.filter(function (x) { return x.slug === slug; })[0];
    return p && p.ad_budget ? Number(p.ad_budget) : 0;
  }
  /* The budget past the card's largest, named from the card's own top
     figure, never typed. */
  function budgetOnRequest() {
    var top = CAT && CAT.budgets && CAT.budgets.length ? Number(CAT.budgets[CAT.budgets.length - 1]) : 0;
    return top ? f(t().budgetOver, { c: qc(), b: n0(qb(top)) }) : t().budgetReq;
  }
  function waLink(q) {
    var who = cfg.quoteWhatsApp || 'https://wa.me/adspace';
    return who + '?text=' + encodeURIComponent('Hi ADspace, I would like to ask about my quotation ' + (q ? q.ref : '') + '.');
  }
  /* Beside the quotation (under it on a phone): the colleague who took the
     lead, once one has, with their own WhatsApp where their namecard shows
     it; before that, Ready to proceed: when the prospect would start and
     whether they decide, recorded on the lead with Proceed with this
     quotation, which opens nothing (2026-10-26). A free proposal is never
     offered. */
  function sideHtml(q) {
    var w = t();
    if (q.rep) {
      var first = String(q.rep.name || '').split(' ')[0];
      var href = q.rep.whatsapp ? 'https://wa.me/' + encodeURIComponent(q.rep.whatsapp) + '?text=' +
        encodeURIComponent('Hi ' + first + ', I would like to discuss my quotation ' + q.ref + '.') : waLink(q);
      return '<h2>' + esc(w.repT) + '</h2><div class="qs-rep"><span class="qs-rep-mark" aria-hidden="true">' + esc(initials(q.rep.name)) + '</span>' +
        '<span class="qs-rep-who"><b>' + esc(q.rep.name) + '</b>' + (q.rep.title ? '<small>' + esc(q.rep.title) + '</small>' : '') + '</span></div>' +
        '<p>' + esc(f(w.repP, { n: first, b: q.brand })) + '</p>' +
        '<a class="btn" href="' + esc(href) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(f(w.repChat, { n: first })) + '</a>';
    }
    var head = '<h2>' + esc(w.propT) + '</h2>';
    if (q.proceed_at) {
      return '<div class="qs-asked"><span class="qs-asked-tick" aria-hidden="true"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 5 5 9-10"/></svg></span>' +
        '<span><b>' + esc(w.propDone) + '</b><span>' + esc(f(w.propBy, { d: day(q.proceed_due) })) + '</span></span></div>';
    }
    function ask(name, label, opts) {
      return '<fieldset class="qs-ask"><legend>' + esc(label) + '</legend>' +
        opts.map(function (o) { return pick('radio', name, o[0], false, o[1]); }).join('') + '</fieldset>';
    }
    return head + '<p>' + esc(w.propP) + '</p>' + ask('pStart', w.startQ, w.starts) + ask('pDecider', w.decQ, w.decs) +
      '<button class="btn btn-primary" id="qsPropose" type="button" data-a="propose">' + esc(w.propAsk) + '</button>' +
      '<p class="msg" id="qsSideMsg" role="status"></p>';
  }
  function initials(n) {
    var p = String(n || '').trim().split(/\s+/);
    return ((p[0] || '').charAt(0) + (p[1] || '').charAt(0)).toUpperCase();
  }
  function cover(title, text, start) {
    root().innerHTML = '<section class="cover" data-shown><div class="cover-inner"><div class="cover-panel"><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p>' +
      '<div class="cover-alt"><a class="btn" href="' + esc(waLink(null)) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(t().chat) + '</a>' +
      (start ? '<a class="btn btn-primary" href="/quote/">' + esc(t().newQuote) + '</a>' : '') + '</div></div></div></section>';
  }

  function paint() {
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    if (paint.lost) { cover(t().lostT, t().lostP, true); return; }
    if (!CAT && !Q) { if (paint.off) cover(t().offT, t().offP); return; }
    if (Q) { root().innerHTML = paintQuote(); decorate(); return; }
    if (S.step === 'intro') {
      S = blank();
      try { sessionStorage.removeItem(KEEP); } catch (e) {}
      root().innerHTML = paintIntro(); decorate(); return;
    }
    if (steps().indexOf(S.step) < 0) S.step = 'need';
    root().innerHTML = { need: paintNeed, plan: paintPlan, custom: paintCustom, details: paintDetails }[S.step]();
    decorate();
  }
  function decorate() {
    if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan(root());
    Array.prototype.forEach.call(root().querySelectorAll('[data-a="pdf"]'), function (b) { addGlyph(b, 'file'); });
    if (window.ADspaceGrow && window.ADspaceGrow.fit) Array.prototype.forEach.call(root().querySelectorAll('textarea'), window.ADspaceGrow.fit);
  }
  // The WhatsApp mark, as the front door draws it before the same words.
  var CHAT_MARK = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 12a8 8 0 0 1-11.8 7L4 20l1.1-4A8 8 0 1 1 20 12z"/></svg>';
  function addGlyph(b, k) {
    if (b.querySelector('svg')) return;
    var p = { file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M12 11v6"/><path d="m9 14 3 3 3-3"/>' }[k];
    b.insertAdjacentHTML('afterbegin', '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + p + '</svg>');
  }
  function say(id, text, tone) {
    var m = $(id); if (!m) return;
    m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }
  function go(step) { S.step = step; keep(); paint(); window.scrollTo(0, 0); }

  // ---- Moving through the steps -------------------------------------------------
  function next() {
    var a = steps(), i = a.indexOf(S.step);
    if (S.step === 'need') {
      if (!Object.keys(S.need).some(function (k) { return S.need[k]; })) { say('qsMsg', t().needNone); return; }
      if (S.need.ads && S.need.social && !S.plan) S.withAds = true;
    }
    if (S.step === 'plan' && (!planOf() || !S.platforms.length)) { say('qsMsg', t().planNone); return; }
    /* Only one-off items asked for (verification alone, say): one of them
       is picked before the details are asked. */
    if (S.step === 'custom') {
      var sel = selection();
      if (!sel.plan && !adsAsked() && !(sel.once || []).length) { say('qsMsg', t().needNone); return; }
    }
    if (S.step === 'details') { make(); return; }
    go(a[i + 1]);
  }
  function readDetails() {
    var c = S.contact;
    c.salutation = $('qsSal') ? $('qsSal').value : '';
    c.name = $('qsName').value.replace(/\s+/g, ' ').trim(); c.email = $('qsEmail').value.trim();
    c.whatsapp = $('qsWa').value.trim(); c.brand = $('qsBrand').value.replace(/\s+/g, ' ').trim();
    c.industry = $('qsInd').value; c.consent = $('qsConsent').checked;
    keep();
  }
  function checkDetails() {
    readDetails();
    var c = S.contact, first = null, bad = function (id, w) { say(id + 'Msg', w); var el = $(id); if (el) el.setAttribute('aria-invalid', 'true'); first = first || el; };
    ['qsName', 'qsEmail', 'qsWa', 'qsBrand', 'qsConsent'].forEach(function (id) { say(id + 'Msg', ''); if ($(id)) $(id).removeAttribute('aria-invalid'); });
    if (c.name.length < 2) bad('qsName', t().req.name);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(c.email)) bad('qsEmail', t().req.email);
    else if (FREE.test(c.email)) say('qsEmailMsg', t().freeMail, 'warn');
    if (!waOk(waDigits(c.whatsapp))) bad('qsWa', t().waBad);
    if (c.brand.length < 2) bad('qsBrand', t().req.brand);
    if (!c.consent) bad('qsConsent', t().req.consent);
    if (first) first.focus();
    return !first;
  }
  function make() {
    if (!checkDetails()) return;
    var btn = root().querySelector('[data-a="next"]');
    btn.disabled = true; btn.textContent = t().making;
    if (!S.idem) { S.idem = key8(); keep(); }
    var body = { sel: selection(), idem: S.idem,
      contact: { salutation: S.contact.salutation || '', name: S.contact.name, email: S.contact.email, whatsapp: waDigits(S.contact.whatsapp), brand: S.contact.brand,
        industry: S.contact.industry || null, consent: true, lang: lang } };
    var C = window.ADspaceCaptcha;
    var token = C && C.on ? C.token(root().querySelector('[data-cf]')) : Promise.resolve(null);
    token.then(function (tk) {
      body.token = tk || '';
      return db.functions.invoke('quote-request', { body: body });
    }).then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error || !d.key) {
        btn.disabled = false; btn.textContent = t().make;
        say('qsMsg', t().err[d.error] || t().err.any);
        return;
      }
      // Made: nothing chosen or typed stays in the tab (a refresh reads the quotation by its key).
      madeBy = S.contact;
      S = blank();
      try { sessionStorage.removeItem(KEEP); } catch (e) {}
      history.replaceState(null, '', '/quote/?q=' + encodeURIComponent(d.key));
      read(d.key);
    }).catch(function () { btn.disabled = false; btn.textContent = t().make; say('qsMsg', t().err.any); });
  }
  function read(k) {
    db.rpc('quote_website_read', { p_key: k }).then(function (r) {
      var d = r && r.data;
      if (r.error || !d) { paint.off = true; Q = null; CAT = null; paint(); return; }
      if (d.error) { paint.lost = true; paint(); return; }
      Q = d; paint(); window.scrollTo(0, 0);
    }).catch(function () { paint.off = true; paint(); });
  }
  function propose(btn) {
    var k = new URLSearchParams(location.search).get('q');
    var st = root().querySelector('input[name="pStart"]:checked'), dc = root().querySelector('input[name="pDecider"]:checked');
    if (!st || !dc) { say('qsSideMsg', t().propNeed); (root().querySelector('input[name="' + (st ? 'pDecider' : 'pStart') + '"]') || btn).focus(); return; }
    btn.disabled = true; btn.textContent = t().propAsking;
    db.rpc('quote_proceed', { p_key: k, p_start: st.value, p_decider: dc.value }).then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error) { btn.disabled = false; btn.textContent = t().propAsk; say('qsSideMsg', t().err[d.error] || t().err.any); return; }
      Q.proceed_at = d.at; Q.proceed_due = d.due;
      $('qsSide').innerHTML = sideHtml(Q);
    }).catch(function () { btn.disabled = false; btn.textContent = t().propAsk; say('qsSideMsg', t().err.any); });
  }
  function pdf(btn) {
    var tab = window.ADspaceDocs && window.ADspaceDocs.tabFor ? window.ADspaceDocs.tabFor() : null;
    btn.disabled = true;
    window.ADspaceQuotePdf.draw(Q, { attention: Q.attention || '', client: { market: Q.market } }).then(function (blob) {
      btn.disabled = false;
      window.ADspaceDocs.save(blob, window.ADspaceQuotePdf.fileName(Q), tab);
    }).catch(function () { btn.disabled = false; if (tab) try { tab.close(); } catch (e) {} });
  }

  // ---- Presses ------------------------------------------------------------------
  document.addEventListener('click', function (e) {
    var b = e.target.closest('#qsRoot [data-a], #qsRoot [data-step]');
    if (!b) return;
    var a = b.getAttribute('data-a');
    if (b.hasAttribute('data-step')) {
      var g = b.getAttribute('data-group'), slug = b.getAttribute('data-slug'), n = (S[g][slug] || 0) + Number(b.getAttribute('data-step'));
      S[g][slug] = Math.max(0, Math.min(30, n)); keep();
      var row = b.closest('.qs-stepper');
      row.querySelector('b').textContent = S[g][slug];
      row.querySelector('[data-step="-1"]').disabled = !S[g][slug];
      return;
    }
    if (a === 'next') next();
    else if (a === 'start') go('need');
    else if (a === 'back') { var s = steps(); go(S.step === 'need' ? 'intro' : s[Math.max(0, s.indexOf(S.step) - 1)]); }
    else if (a === 'propose') propose(b);
    else if (a === 'pdf') pdf(b);
    else if (a === 'change' || a === 'new') {
      if (madeBy) S.contact = madeBy;
      if (Q && Q.selection) adopt(Q.selection);
      Q = null;
      history.replaceState(null, '', '/quote/');
      load(function () { go(a === 'new' ? 'need' : 'custom'); });
    }
  });
  document.addEventListener('change', function (e) {
    var el = e.target;
    if (!el.closest || !el.closest('#qsRoot')) return;
    var nm = el.name, id = el.id;
    if (nm === 'need') {
      S.need[el.value] = el.checked;
      var a = steps(), sp = root().querySelector('.qs-progress span'), bar = root().querySelector('.qs-track i');
      if (sp) sp.textContent = f(t().step, { n: 1, m: a.length + 1 });
      if (bar) bar.style.width = Math.round(1 / (a.length + 1) * 100) + '%';
    }
    else if (nm === 'plat') {
      S.platforms = S.platforms.filter(function (p) { return p !== el.value; });
      if (el.checked) S.platforms.push(el.value);
    }
    else if (nm === 'plan') {
      S.plan = el.value;
      // Extras the new plan does not offer leave with the old one.
      var ok = extrasOf(planOf()).map(function (c) { return c.slug; });
      Object.keys(S.extra).forEach(function (k) { if (ok.indexOf(k) < 0) delete S.extra[k]; });
      var xb = document.getElementById('qsExtraBox');
      if (xb) xb.innerHTML = extrasHtml();
    }
    else if (nm === 'lang') {
      S.langs = S.langs.filter(function (l) { return l !== el.value; });
      if (el.checked) S.langs.push(el.value);
      if (!S.langs.length) { S.langs = [el.value]; el.checked = true; }
      keep(); paint(); return;
    }
    else if (nm === 'translate') { S.translate = el.checked; }
    else if (nm === 'kol') { S.kol = el.checked; }
    else if (nm === 'verify') {
      S.verify = S.verify.filter(function (v) { return v !== el.value; });
      if (el.checked) S.verify.push(el.value);
    }
    else if (id === 'qsAds') {
      S.withAds = el.value === 'ads';
      var cur = planOf();
      if (cur && Boolean(cur.ads) !== S.withAds) {
        var same = CAT.plans.filter(function (p) { return Boolean(p.ads) === S.withAds && p.platforms === cur.platforms; })[0];
        S.plan = same ? same.slug : null;
      }
      keep(); paint(); return;
    }
    else if (nm === 'pStart' || nm === 'pDecider') { say('qsSideMsg', ''); }
    else if (id === 'qsConsent') { el.removeAttribute('aria-invalid'); say('qsConsentMsg', ''); }
    else if (id === 'qsBudget') { S.budget = Number(el.value); }
    else if (id === 'qsTerm') { S.term = Number(el.value); }
    else if (id === 'qsKoc') { S.koc = el.value; }
    else return;
    var lab = el.closest('.qs-pick, .qs-chip');
    if (lab) {
      if (el.type === 'radio') Array.prototype.forEach.call(root().querySelectorAll('input[name="' + nm + '"]'), function (r) { r.closest('label').classList.toggle('is-on', r.checked); });
      else lab.classList.toggle('is-on', el.checked);
    }
    keep();
  });
  document.addEventListener('submit', function (e) {
    if (e.target.id === 'qsDetails') { e.preventDefault(); next(); }
  });
  document.addEventListener('input', function (e) {
    // A refusal leaves its field once the field is changed; the next press checks it again.
    var id = e.target.id;
    if (id && e.target.getAttribute('aria-invalid') === 'true') { e.target.removeAttribute('aria-invalid'); if (id !== 'qsEmail') say(id + 'Msg', ''); }
    if (id === 'qsEmail') {
      var v = e.target.value.trim();
      say('qsEmailMsg', /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v) && FREE.test(v) ? t().freeMail : '', 'warn');
    }
    if (e.target.closest && e.target.closest('#qsDetails')) readDetails();
  });

  /* A quotation's own selection, to change and make again. */
  function adopt(sel) {
    S.need = { social: Boolean(sel.plan), ads: sel.budget != null, content: false, koc: false, verify: false };
    S.plan = sel.plan || null; S.platforms = (sel.platforms || ['meta']).slice(); S.extra = sel.extra || {};
    S.langs = (sel.langs || ['en']).slice(); S.translate = Boolean(sel.translate); S.budget = sel.budget == null ? null : Number(sel.budget);
    S.term = TERMS.indexOf(Number(sel.term)) >= 0 ? Number(sel.term) : 12; S.once = {}; S.koc = ''; S.kol = false; S.verify = [];
    (sel.once || []).forEach(function (o) {
      var c = CAT && CAT.contents.some(function (x) { return x.slug === o.slug; });
      if (c) { S.need.content = true; S.once[o.slug] = o.qty; }
      else if (CAT && CAT.koc.some(function (x) { return x.slug === o.slug; })) { S.need.koc = true; S.koc = o.slug; }
      else if (CAT && o.slug === CAT.kol) { S.need.koc = true; S.kol = true; }
      else { S.need.verify = true; S.verify.push(o.slug); }
    });
    var p = planOf(); if (p) S.withAds = Boolean(p.ads);
    keep();
  }

  function load(done) {
    if (!db) { paint.off = true; paint(); return; }
    db.rpc('quote_catalogue').then(function (r) {
      var d = r && r.data;
      if (r.error || !d || d.error) { paint.off = true; CAT = null; paint(); return; }
      CAT = d;
      if (S.plan && !planOf()) S.plan = null;
      if (done) done(); else paint();
    }).catch(function () { paint.off = true; paint(); });
  }

  if ($('langToggle')) $('langToggle').addEventListener('click', function () {
    lang = lang === 'en' ? 'zh' : 'en';
    try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
    if (S.step === 'details' && !Q && $('qsName')) readDetails();
    paint();
  });

  var given = new URLSearchParams(location.search).get('q');
  if (given) { load(function () { read(given); }); }
  else load();
})();
