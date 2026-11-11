/*
 * Creator Portal — what a creator sees.
 *
 * The one party in this operation with no page of their own. Drafts arrived in
 * a Drive folder somebody had to find and paste a link to, and "when am I
 * shooting" was asked on WhatsApp.
 *
 * Signing in: not an account. We hold phone numbers rather than addresses, an
 * SMS code costs money on every message for a page opened four times a
 * campaign, and a freelancer has no password to remember. The key is a code
 * they keep, carried in the link so one tap is enough and stored by the
 * browser so it is typed at most once, on a new phone.
 *
 * What is shown is their own booking and nothing else. A creator never sees
 * the client's stage, the campaign's commercial state, what the client pays,
 * who else was offered the work, or the team's notes: a creator reading that
 * we are still waiting on a client is being handed our position in somebody
 * else's negotiation. The security definer function is what withholds it, not
 * this page.
 */
(function () {
  var API = window.ADspaceAPI;
  /* FIRST-VISIT GUIDE (js/guide.js, the user, 2026-10-07): offered once in
     this browser, the moment the page shows what it is for. */
  var GUIDE = { name: { en: 'Your bookings', zh: '您的合作' }, steps: [
    { at: '#workList .qrow', text: { en: 'Your bookings, the most urgent first. Open a booking for its brief and dates.', zh: '您的合作项目，需要您处理的排在最前。点开即可查看简介与日期。' } },
    { at: '#crTabs', text: { en: 'Your payments and your profile links are on their own tabs.', zh: '您的付款与主页链接各在一个分页。' } }] };
  var db  = API && API.client;
  var $   = function (id) { return document.getElementById(id); };
  var KEY = 'adspace-creator';
  /* The bar names the creator only once their code has opened the page;
     until then it reads nothing, never "Prepared for …" (CP-1). */
  (function () { var f = $('clientFor'); if (f) f.hidden = true; })();

  function esc(s) { return window.ADspaceWords.esc(s); }

  /* A stored address drawn as a link: http or https alone (js/words.js). */
  function absUrl(u) { return window.ADspaceWords.absUrl(u); }

  var T = window.ADspaceWords.of({
    en: {
      preparedFor: 'Signed in as',
      codeTitle: 'Access code',
      codeText: 'Enter the access code provided.',
      codeWrong: 'Incorrect access code. Please try again.',
      standDown: 'No bookings',
      standDownText: 'Please contact your ADspace account manager.',
      lang: '中文',
      work: 'Your bookings', openCode: 'Open', tabsLabel: 'Sections',
      /* The queue names the one that needs them, so nothing on it has to be
         opened to find out whether it does. */
      needsYou: 'Action required',
      none: 'No bookings',
      noneText: 'Confirmed bookings will appear here.',
      signOut: 'Forget this device',
      shootOn: 'Shoot', deliveryOn: 'Delivery', goLive: 'Post date',
      draftDue: 'Draft due', dueToday: 'Due today', overdue: 'Overdue by {n}', dueIn: 'Due in {n}',
      whereAt: 'Location', contact: 'Contact on the day', tracking: 'Tracking no.',
      platformsLabel: 'Posting on', tbc: 'To be confirmed',
      briefHead: 'Brief',
      deliverHead: 'Submission',
      changesHead: 'Revision notes',
      changesBare: 'Please revise and submit again.',
      addFiles: 'Files', captionLabel: 'Caption',
      nextUpWord: 'Next up', handIn: 'Submit your draft', handInAgain: 'Submit your revision',
      dropTitle: 'Add photos or videos', dropSub: 'Up to 1 GB each',
      directions: 'Directions', call: 'Call', whatsapp: 'WhatsApp',
      captionHint: 'Caption for this post.',
      submit: 'Submit draft', submitting: 'Submitting…', update: 'Update submission',
      needFiles: 'Attach at least one file.',
      uploading: 'Uploading', saving: 'Saving', remove: 'Remove',
      filesHead: 'Submitted files',
      uploaded: 'Uploaded.',
      sizeOne: '{file} is larger than {mb} MB. Please upload a smaller file.',
      sizeMany: '{n} files are larger than {mb} MB. Please upload smaller files.',
      failOne: '{file} could not be uploaded. Please try again.',
      failMany: '{n} files could not be uploaded. Please try again.',
      uploadMany: 'This booking has reached today\'s upload limit. Please try again tomorrow, or contact ADspace.',

      since: 'Creator since {d}',
      bookingsN: function (n) { return n + (n === 1 ? ' booking' : ' bookings'); },
      linksEdit: 'Edit links', linksAdd: 'Add links', linksTitle: 'Profile links',
      linksNone: 'No profile links.',
      save: 'Save', cancel: 'Cancel', close: 'Close', saved: 'Saved.', noChange: 'No change.',
      linkBad: '{url} is not a profile link. Please enter the link to your profile.',
      linkTaken: 'This profile is registered to another creator. Please contact your ADspace account manager.',
      linkNone: 'Keep at least one profile link.',
      linkFail: 'Not saved. Please try again.',
      payHead: 'Payment details',
      tabs: { bookings: 'Bookings', payments: 'Payments', profile: 'Profile' },
      profHead: 'Profile links', contactHead: 'Contact', contactWa: 'WhatsApp', contactEmail: 'Email',
      paysHead: 'Payments', paysNone: 'No payments.',
      paysWord: { pending: 'Pending payment', paid: 'Paid', due: 'Not due' }, paysPaid: 'Paid {d}',
      paysNote: 'Payments in MYR are made within {myr} working days of the post date, and payments in other currencies within {other} working days.',
      payGo: 'Submit details', payChange: 'Change details',
      payEinvHead: 'e-Invoice',
      payEinv: 'Every payment ADspace makes to you requires an e-Invoice to be submitted to the Inland Revenue Board of Malaysia (LHDN). The e-Invoice is issued with the details you provide here, so please ensure your name, identification number, Tax Identification Number (TIN) and billing address are accurate and match your official records.',
      payAddrNeeded: 'Billing address needed', payAddrGo: 'Add billing address', payAddrSent: 'Billing address saved.',
      payNone: 'Please submit your payment details before your first payment.',
      payPending: 'Under review', payApproved: 'Approved', payDeclined: 'Declined', payChangePending: 'Change under review',
      paySentOn: 'Submitted on {d}', payAgain: 'Please submit your details again.',
      payTo: 'Pay to', payMethod: 'Method', payAccount: 'Account', payEnding: 'Ending {n}',
      payBilling: 'Billing as', payName: 'Legal name', payEmail: 'Email',
      payHeads: { billing: 'Billing', payment: 'Payment', contact: 'Contact' },
      payKinds: { nric: 'Individual (NRIC)', passport: 'Individual (Passport)', brn: 'Company' },
      payIdLabel: { nric: 'NRIC Number', passport: 'Passport Number', brn: 'Business Registration Number (12 digits)' },
      payNameLabel: { nric: 'Full Name as per NRIC', passport: 'Full Name as per Passport', brn: 'Registered Company Name' },
      payTin: 'Tax Identification Number (TIN)', payOptional: 'Optional', payAddress: 'Billing address',
      payCurrency: 'Currency', payMethods: { bank: 'Bank transfer', duitnow: 'DuitNow', paynow: 'PayNow', tng: 'Touch \u2019n Go eWallet' },
      payBank: 'Bank', payChooseBank: 'Choose a bank',
      payAcctLabel: { bank: 'Account number', duitnow: 'DuitNow ID', paynow: 'PayNow ID (mobile number or UEN)', tng: 'Touch \u2019n Go eWallet mobile number' },
      payPayee: 'Account holder name', payWhatsapp: 'WhatsApp number',
      payKeep: 'Leave blank to keep the number ending {n}.',
      payKeepAs: 'Leave blank to keep {v}.',
      payConfirm: 'I confirm these details are correct and authorise ADSPACE PLT to make payments to this account.',
      paySent: 'Submitted. ADspace will review your details and inform you by email once they are approved.',
      payBad: { bill_kind: 'Choose how you are billed.', id_no: { nric: 'Enter a valid NRIC Number.', passport: 'Enter a valid Passport Number.', brn: 'Enter a valid 12-digit Business Registration Number.' },
        legal_name: { nric: 'Enter your Full Name as per NRIC.', passport: 'Enter your Full Name as per Passport.', brn: 'Enter the Registered Company Name.' },
        tin: 'Enter a valid TIN, or leave it blank.', address: 'Enter the billing address.', currency: 'Choose a currency.',
        method: 'Choose a payment method.', bank: 'Choose a bank.', account: 'Enter a valid account number.',
        payee: 'Enter the account holder name.', email: 'Enter a valid email address.', whatsapp: 'Enter a valid WhatsApp number.',
        confirm: 'Please tick to confirm.' },
      payTooMany: 'Too many submissions today. Please try again tomorrow.',
      payFail: 'Not submitted. Please try again.',
      postsHead: 'Post and results', postLink: 'Post link', postedOn: 'Posted on',
      countPeriod: 'Results period: {a} to {b}', periodWait: 'ADspace will set the results period shortly.',
      views: 'Views', engagements: 'Engagements', impressions: 'Impressions',
      linkWrong: 'This is not a {p} post link. Please paste the link to your {p} post.', numWrong: 'Enter whole numbers.',
      rateHead: 'Your experience', foldHead: 'Booking details',
      rateStar: function (n) { return n + ' out of 5'; },
      rateThanks: 'Thank you.',
      ended: 'This booking has ended.',
      nextUp: {
        confirmed: 'The shoot date will be confirmed with you.',
        pending_visit: 'Your shoot is booked.',
        pending_delivery: 'The product is on its way to you.',
        pending_draft: 'Your submission is due.',
        submitted: 'Your submission is under review.',
        reviewing: 'Your submission is under review.',
        changes: 'Please revise as noted below and submit again.',
        scheduled: 'Your submission has been approved and scheduled.',
        posted: 'Posted. Thank you.',
        completed: 'Completed. Thank you.'
      }
    },
    zh: {
      preparedFor: '登录身份',
      codeTitle: '访问码',
      codeText: '请输入您收到的访问码。',
      codeWrong: '访问码不正确，请重新输入。',
      standDown: '暂无合作',
      standDownText: '请联系您的 ADspace 客户经理。',
      lang: 'EN',
      work: '您的合作', openCode: '打开', tabsLabel: '页面分区',
      needsYou: '待您处理',
      none: '暂无合作',
      noneText: '合作确认后将显示在此处。',
      signOut: '不再记住此设备',
      shootOn: '拍摄', deliveryOn: '寄送', goLive: '发布日期',
      draftDue: '初稿截止', dueToday: '今天截止', overdue: '已逾期{n}', dueIn: '{n}后截止',
      whereAt: '地点', contact: '当天联系人', tracking: '快递单号',
      platformsLabel: '发布平台', tbc: '待确认',
      briefHead: '合作简介',
      deliverHead: '作品提交',
      changesHead: '修改说明',
      changesBare: '请修改后重新提交。',
      addFiles: '文件', captionLabel: '文案',
      nextUpWord: '下一步', handIn: '提交初稿', handInAgain: '提交修改稿',
      dropTitle: '添加照片或视频', dropSub: '每个文件不超过 1 GB',
      directions: '查看路线', call: '致电', whatsapp: 'WhatsApp',
      captionHint: '此作品的文案。',
      submit: '提交', submitting: '提交中…', update: '更新提交',
      needFiles: '请至少上传一个文件。',
      uploading: '上传中', saving: '保存中', remove: '移除',
      filesHead: '已提交文件',
      uploaded: '已上传。',
      sizeOne: '{file}超过{mb}MB上限，请上传较小的文件。',
      sizeMany: '{n}个文件超过{mb}MB上限，请上传较小的文件。',
      failOne: '{file} 上传失败，请重试。',
      failMany: '{n}个文件上传失败，请重试。',
      uploadMany: '此合作今日的上传数量已达上限，请明天再试或联系 ADspace。',

      since: '{d} 起合作',
      bookingsN: function (n) { return n + '个合作'; },
      linksEdit: '编辑链接', linksAdd: '添加链接', linksTitle: '主页链接',
      linksNone: '暂无主页链接。',
      save: '保存', cancel: '取消', close: '关闭', saved: '已保存。', noChange: '没有更改。',
      linkBad: '{url} 不是主页链接，请输入您的主页链接。',
      linkTaken: '此主页已登记在另一位创作者名下，请联系您的 ADspace 客户经理。',
      linkNone: '请至少保留一个主页链接。',
      linkFail: '未能保存，请重试。',
      postsHead: '发布链接与数据', postLink: '帖子链接', postedOn: '实际发布日期',
      countPeriod: '统计期间：{a} 至 {b}', periodWait: 'ADspace 将尽快设定数据统计期间。',
      views: '播放量', engagements: '互动量', impressions: '曝光量',
      linkWrong: '这不是{p}的帖子链接，请粘贴您在{p}发布的帖子链接。', numWrong: '请输入整数。',
      rateHead: '合作体验', foldHead: '合作详情',
      rateStar: function (n) { return n + '星（满分5星）'; },
      rateThanks: '感谢您的评分。',
      payHead: '付款资料',
      tabs: { bookings: '合作', payments: '付款', profile: '个人资料' },
      profHead: '主页链接', contactHead: '联络资料', contactWa: 'WhatsApp', contactEmail: '电邮',
      paysHead: '付款', paysNone: '暂无付款。',
      paysWord: { pending: '待付款', paid: '已付款', due: '未到期' }, paysPaid: '已于{d}付款',
      paysNote: '马币款项于发布日期后{myr}个工作日内支付，其他货币款项于{other}个工作日内支付。',
      payGo: '提交资料', payChange: '更改资料',
      payEinvHead: '电子发票（e-Invoice）',
      payEinv: 'ADspace 向您支付的每笔款项均须向马来西亚内陆税收局（LHDN）提交电子发票。电子发票将依据您在此提供的资料开具，请确保您的姓名、身份证明号码、税务识别号（TIN）及账单地址准确无误，并与您的官方记录一致。',
      payAddrNeeded: '需提供账单地址', payAddrGo: '添加账单地址', payAddrSent: '账单地址已保存。',
      payNone: '首次付款前，请提交您的付款资料。',
      payPending: '审核中', payApproved: '已核准', payDeclined: '已拒绝', payChangePending: '更改审核中',
      paySentOn: '提交于{d}', payAgain: '请重新提交您的资料。',
      payTo: '收款人', payMethod: '付款方式', payAccount: '账户', payEnding: '尾号{n}',
      payBilling: '开票身份', payName: '法定名称', payEmail: '电邮',
      payHeads: { billing: '开票资料', payment: '收款资料', contact: '联络资料' },
      payKinds: { nric: '个人（身份证）', passport: '个人（护照）', brn: '公司' },
      payIdLabel: { nric: '身份证号码', passport: '护照号码', brn: '公司注册号（12位数字）' },
      payNameLabel: { nric: '身份证上的全名', passport: '护照上的全名', brn: '公司注册名称' },
      payTin: '税务识别号（TIN）', payOptional: '选填', payAddress: '账单地址',
      payCurrency: '货币', payMethods: { bank: '银行转账', duitnow: 'DuitNow', paynow: 'PayNow', tng: 'Touch \u2019n Go 电子钱包' },
      payBank: '银行', payChooseBank: '请选择银行',
      payAcctLabel: { bank: '银行账号', duitnow: 'DuitNow ID', paynow: 'PayNow ID（手机号码或 UEN）', tng: 'Touch \u2019n Go 电子钱包手机号码' },
      payPayee: '账户持有人姓名', payWhatsapp: 'WhatsApp号码',
      payKeep: '留空即保留尾号为{n}的号码。',
      payKeepAs: '留空即保留{v}。',
      payConfirm: '本人确认以上资料正确无误，并授权 ADSPACE PLT 将款项付至此账户。',
      paySent: '已提交。ADspace 审核通过后将以电邮通知您。',
      payBad: { bill_kind: '请选择开票身份。', id_no: { nric: '请输入有效的身份证号码。', passport: '请输入有效的护照号码。', brn: '请输入有效的12位公司注册号。' },
        legal_name: { nric: '请输入身份证上的全名。', passport: '请输入护照上的全名。', brn: '请输入公司注册名称。' },
        tin: '请输入有效的TIN，或留空。', address: '请输入账单地址。', currency: '请选择货币。',
        method: '请选择付款方式。', bank: '请选择银行。', account: '请输入有效账号。',
        payee: '请输入账户持有人姓名。', email: '请输入有效的电邮地址。', whatsapp: '请输入有效的WhatsApp号码。',
        confirm: '请勾选确认。' },
      payTooMany: '今日提交次数过多，请明天再试。',
      payFail: '未能提交，请重试。',
      ended: '此合作已结束。',
      nextUp: {
        confirmed: 'ADspace 将与您确认拍摄日期。',
        pending_visit: '拍摄已安排。',
        pending_delivery: '产品正在寄送中。',
        pending_draft: '请提交您的作品。',
        submitted: '您的提交正在审阅中。',
        reviewing: '您的提交正在审阅中。',
        changes: '请按以下说明修改后重新提交。',
        scheduled: '已通过并排期。',
        posted: '已发布，感谢您的配合。',
        completed: '已完成，感谢您的配合。'
      }
    }
  });

  var W = window.ADspaceWords;
  var lang = 'en';
  var feed = null;
  var code = '';
  function t() { return T[lang]; }

  function fmtDate(d) {
    if (!d) return '';
    /* Days are Malaysia's (js/clock.js), whatever the device's clock. */
    return ADspaceClock.date(d, { zh: lang === 'zh' }) || d;
  }

  /* A shoot's time in the page's language (ux-audit CREATOR-7): 10:00 am,
     上午10:00; a time that reads as neither is shown as typed. */
  function timeWord(v) {
    var x = String(v || '').trim(), h, mi;
    var m = /^(\d{1,2}):(\d{2})/.exec(x) || /^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)$/i.exec(x);
    if (!m) return x;
    h = Number(m[1]); mi = m[2] || '00';
    if (m[3]) h = (h % 12) + (/pm/i.test(m[3]) ? 12 : 0);
    if (h > 23) return x;
    var h12 = (h % 12) || 12;
    /* 2:00pm, as every client page writes a time (2026-10-27, CRE-2). */
    return lang === 'zh' ? (h < 12 ? '上午' : '下午') + h12 + ':' + mi : h12 + ':' + mi + (h < 12 ? 'am' : 'pm');
  }
  function dayTime(d, tm) { return fmtDate(d) + (tm ? (lang === 'zh' ? ' ' : ', ') + timeWord(tm) : ''); }

  function dueWord(day) {
    if (!day) return '';
    var n = ADspaceClock.between(ADspaceClock.today(), String(day).slice(0, 10));
    if (n === null) return '';
    if (n === 0) return t().dueToday;
    var span = Math.abs(n) + (lang === 'zh' ? '天' : (Math.abs(n) === 1 ? ' day' : ' days'));
    return fill(n < 0 ? t().overdue : t().dueIn, { n: span });
  }

  // The console stores the placement by its printed name; older rows carry the key
  // or what was typed ("RedNote"), so the name is matched without case.
  var PLAT_KEY = { rednote: 'xhs', xhs: 'xhs', xiaohongshu: 'xhs', instagram: 'instagram', tiktok: 'tiktok', facebook: 'facebook' };
  var PLAT = { en: { xhs: 'rednote', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' },
               zh: { xhs: '小红书', instagram: 'Instagram', tiktok: 'TikTok', facebook: 'Facebook' } };
  function platsOf(s) {
    return String(s || '').split(',').map(function (x) { return x.trim(); })
      .filter(Boolean).map(function (p) { var k = PLAT_KEY[p.toLowerCase()] || p; return PLAT[lang][k] || p; });
  }

  // ---- Covers ---------------------------------------------------------------

  function cover(title, text, opts) {
    document.body.classList.add('is-plain');
    $('app').hidden = true;
    $('stateBox').hidden = false;
    $('stateTitle').textContent = title;
    $('stateText').textContent = text;
    $('codeRow').hidden = !(opts && opts.ask);
    // No session behind a cover, so nothing to sign out of, and no name on
    // the bar: a shared device never shows the creator before (CP-1).
    if ($('signOutBtn')) $('signOutBtn').hidden = true;
    if (window.ADspaceChrome) window.ADspaceChrome.preparedFor('', '');
    else if ($('clientFor')) $('clientFor').hidden = true;
    $('stateMsg').textContent = '';
    $('stateMsg').className = 'msg';
    if (opts && opts.ask) setTimeout(function () { $('codeInput').focus(); }, 60);
  }
  function askCode() { tried = ''; cover(t().codeTitle, t().codeText, { ask: true }); }
  /* A link carrying a code that opens nothing reads as the same code typed
     would: the code in the field and the invalid line under it (ux-audit
     CREATOR-5, 2026-10-14). */
  function linkWrong(c) {
    $('codeInput').value = c.length > 4 ? c.slice(0, 4) + '-' + c.slice(4) : c;
    $('stateMsg').textContent = t().codeWrong;
    $('stateMsg').className = 'msg err';
  }

  function tidy(s) { return String(s || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase(); }

  // ---- Load -----------------------------------------------------------------

  /* Answers a promise that settles once the page is drawn again, so what a
     press says is said after the repaint, never on a guessed delay
     (2026-10-14, ux-audit CREATOR-2). */
  function load(c, typed) {
    if (!db) { cover(t().failTitle, t().failText); return Promise.resolve(); }
    return db.rpc('get_creator', { p_code: c }).then(function (r) {
      var d = r.data;
      if (r.error || !d) { cover(t().failTitle, t().failText); return; }
      if (d.error === 'inactive') { forget(); cover(t().standDown, t().standDownText); return; }
      /* Wrong codes are counted against the caller: five within 15 minutes
         lock it out, the right code included (2026-10-27). The code is kept
         in the field and in this browser, so Open works once it ends. */
      if (d.error === 'locked') {
        if (!typed) { askCode(); $('codeInput').value = codeShape(c, false); }
        $('stateMsg').textContent = W.lockedLine(t(), d.minutes);
        $('stateMsg').className = 'msg err';
        return;
      }
      if (d.error) {
        // A typed code that is wrong is answered on the form they typed it in,
        // not by throwing the whole page away underneath them.
        if (typed) {
          $('stateMsg').textContent = t().codeWrong;
          $('stateMsg').className = 'msg err';
        } else { forget(); askCode(); if (c === fromLink) linkWrong(c); }
        return;
      }
      if (code !== c) { code = c; draftsLoad(); }
      try { localStorage.setItem(KEY, c); } catch (e) { /* private window */ }
      feed = d;
      // The code has proved itself: the media pass first, then the files.
      var M = window.ADspaceMedia;
      return Promise.all([M && M.pass ? M.pass({ creator: c }) : Promise.resolve(), loadPay()]).then(function () {
        paint();
        follow();
      });
    }).catch(function () { cover(t().failTitle, t().failText); });
  }

  /* Forgetting the device stops its notifications too: whoever uses it next
     is not told about this creator's bookings. */
  function forget() {
    if (following && window.ADspacePush) window.ADspacePush.off(true);
    following = false;
    var b = $('pushBtn'); if (b) b.hidden = true;
    if (window.ADspacePush) window.ADspacePush.shut();
    try { localStorage.removeItem(KEY); sessionStorage.removeItem(DRAFTS + code); } catch (e) {} drafts = {}; code = ''; feed = null; pay = null;
  }

  /* Notifications on this device for this creator (js/push.js), offered once
     the code has proved who they are. */
  var following = false;
  function follow() {
    var P = window.ADspacePush;
    if (!P || following) return;
    following = true;
    P.setup({ audience: 'creator', ref: function () { return code; }, lang: function () { return lang; },
              sw: '/creator/sw.js', scope: '/creator/' });
    P.control(function () { return t().push; });
  }

  // ---- Paint ----------------------------------------------------------------

  function paint() {
    document.body.classList.remove('is-plain');
    $('stateBox').hidden = true;
    $('app').hidden = false;
    if (window.ADspaceGuide) window.ADspaceGuide.offer('creator', GUIDE);
    var cr = feed.creator || {};
    $('whoName').textContent = cr.name || '';
    paintHead();
    if (window.ADspaceChrome) window.ADspaceChrome.preparedFor(t().preparedFor, cr.name || '');
    $('signOutBtn').querySelector('span').textContent = t().signOut;
    $('signOutBtn').setAttribute('aria-label', t().signOut);
    $('signOutBtn').hidden = false;

    var rows = feed.bookings || [];
    $('workHead').hidden = !rows.length;
    $('workHead').textContent = t().work;
    $('noWork').hidden = !!rows.length;
    $('noWorkTitle').textContent = t().none;
    $('noWorkText').textContent = t().noneText;

    paintPay();
    paintQueue(rows);
    paintTabs();
  }

  /* ---- Bookings, Payments and Profile (2026-11-10) ----------------------
     One pane at a time, in `?tab=` (Bookings left out); Bookings carries the
     red count of what waits on the creator. Payments is drawn once payment
     details are asked or a booking has a payment to show. */
  var PANES = ['bookings', 'payments', 'profile'];
  var crPane = 'bookings';
  function crTab(name) { return document.querySelector('#crTabs .tab[data-pane="' + name + '"]'); }
  function crPaneOf() { var p = new URLSearchParams(location.search).get('tab'); return PANES.indexOf(p) >= 0 ? p : 'bookings'; }
  function showCrPane(name, push) {
    var tab = crTab(name);
    if (!tab || tab.hidden) { name = 'bookings'; tab = crTab(name); }
    crPane = name;
    Array.prototype.forEach.call(document.querySelectorAll('#crTabs .tab'), function (b) {
      var on = b === tab;
      b.classList.toggle('is-on', on);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
    });
    Array.prototype.forEach.call(document.querySelectorAll('.cr-pane'), function (x) { x.hidden = x.getAttribute('data-pane') !== name; });
    var url = new URL(location.href);
    if (name === 'bookings') url.searchParams.delete('tab'); else url.searchParams.set('tab', name);
    if (url.href === location.href) return;
    if (push) history.pushState(history.state, '', url.href); else history.replaceState(history.state, '', url.href);
  }
  function paintTabs() {
    var T0 = t();
    $('crTabBookingsWord').textContent = T0.tabs.bookings;
    $('crTabPaymentsWord').textContent = T0.tabs.payments;
    $('crTabProfileWord').textContent = T0.tabs.profile;
    var owed = ((feed && feed.bookings) || []).filter(needsCreator).length;
    $('crTabOwed').hidden = !owed;
    $('crTabOwed').textContent = owed ? String(owed) : '';
    $('crTabPayments').hidden = !(pay && (pay.due || pay.address_needed || (pay.payments || []).length));
    /* Details brought in with no billing address (AP01, 2026-11-10) open
       the page on Payments once, where the address is asked for. */
    if (pay && pay.address_needed && !addrShown && !new URLSearchParams(location.search).get('tab')) { addrShown = true; crPane = 'payments'; }
    paintContact();
    showCrPane(crTab(crPane) && !crTab(crPane).hidden ? crPane : crPaneOf(), false);
  }
  Array.prototype.forEach.call(document.querySelectorAll('#crTabs .tab'), function (b) {
    b.addEventListener('click', function () { showCrPane(b.getAttribute('data-pane'), true); });
  });
  $('crTabs').addEventListener('keydown', function (e) {
    var tabs = Array.prototype.filter.call(this.querySelectorAll('.tab'), function (b) { return !b.hidden; });
    var i = tabs.indexOf(document.activeElement);
    if (i < 0) return;
    var to = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
    if (to === null) return;
    e.preventDefault();
    to = (to + tabs.length) % tabs.length;
    tabs[to].focus();
    tabs[to].click();
  });
  window.addEventListener('popstate', function () { if (feed) showCrPane(crPaneOf(), false); });
  crPane = crPaneOf();

  /* The contact the team reaches them on: the WhatsApp the team holds and
     the email of their payment details. */
  function paintContact() {
    var T0 = t(), cr = (feed && feed.creator) || {};
    var held = pay && (pay.paid || pay.last);
    var wa = (pay && pay.whatsapp) || cr.whatsapp || (held && held.whatsapp) || '';
    var mail = held && held.email;
    $('profTitle').textContent = T0.profHead;
    $('contactTitle').textContent = T0.contactHead;
    var rows = [[T0.contactWa, wa], [T0.contactEmail, mail]].filter(function (r) { return r[1]; });
    $('contactBox').hidden = !rows.length;
    $('contactFacts').innerHTML = rows.map(function (r) { return '<div><dt>' + esc(r[0]) + '</dt><dd>' + esc(r[1]) + '</dd></div>'; }).join('');
  }

  /* Each booking's payment as Bukku holds it (`creator_pay_form`
     `payments`), one line: the campaign and its Job reference, then Paid
     and Bukku's payment day, Pending payment once posted or billed, Not due
     before. Never an amount: anyone holding the link reads this
     (the user, 2026-11-12). */
  function paintPays() {
    var T0 = t(), list = (pay && pay.payments) || [];
    $('crPaysTitle').textContent = T0.paysHead;
    var day = function (d) { return d ? ADspaceClock.date(d, { zh: lang === 'zh', year: false }) : ''; };
    $('crPaysList').innerHTML = !list.length ? '<p class="crlinks-none">' + esc(T0.paysNone) + '</p>' : list.map(function (x) {
      var b = x.bill;
      var st = b && b.status === 'paid' ? 'paid' : (b || x.posted_on || x.state === 'posted' || x.state === 'completed') ? 'pending' : 'due';
      var tone = st === 'paid' ? 'is-ok' : st === 'pending' ? 'is-warn' : 'is-off';
      var word = st === 'paid' && b.paid_on ? fill(T0.paysPaid, { d: day(b.paid_on) }) : T0.paysWord[st];
      return '<div class="crpay-row">' +
        '<span class="crpay-what"><span class="crpay-name">' + esc(x.campaign || '') + '</span>' +
          (x.job ? '<small class="crpay-job">' + esc(x.job) + '</small>' : '') + '</span>' +
        '<span class="crpay-st"><span class="chip-state ' + tone + '">' + esc(word) + '</span></span>' +
      '</div>';
    }).join('');
    var dd = (pay && pay.days) || {};
    $('crPaysNote').hidden = !(dd.myr != null && dd.other != null);
    $('crPaysNote').textContent = dd.myr != null && dd.other != null ? fill(T0.paysNote, { myr: dd.myr, other: dd.other }) : '';
  }

  /* ---- Who they are, and their profile links ----------------------------
     The head reads like the console's record of them: the name, since when
     and how many bookings, then the profile links a client opens on the
     selection page. The creator keeps those up to date here, straight into
     the one table the team edits too; the database reads every link and
     files every change, so there is no approval round and nothing to drift.
     Never the fee: the rate on a booking is the client's price. */
  var PLAT_ORDER = ['xhs', 'instagram', 'tiktok', 'facebook'];
  var PLACEHOLDER = {
    xhs: 'https://www.xiaohongshu.com/user/profile/…',
    instagram: 'https://www.instagram.com/adspace.advertising',
    tiktok: 'https://www.tiktok.com/@adspace.advertising',
    facebook: 'https://www.facebook.com/adspace.advertising'
  };
  /* The one leaving mark (js/icons.js), never a drawing of its own (CR-7). */
  function OUTMARK() { return window.ADspaceIcons ? window.ADspaceIcons.svg('out') : ''; }

  function monthYear(ts) {
    return ts ? ADspaceClock.month(ts, { zh: lang === 'zh' }) : '';
  }
  function profiles() {
    var list = ((feed && feed.creator) || {}).profiles || [];
    return list.slice().sort(function (a, b) {
      return PLAT_ORDER.indexOf(a.platform) - PLAT_ORDER.indexOf(b.platform);
    });
  }
  /* A handle is shown where it reads as a name; rednote keeps a profile id in
     that field, which says nothing to anybody. */
  function linkWord(p) {
    var name = PLAT[lang][p.platform] || p.platform;
    var h = p.handle && p.handle.length <= 18 && p.platform !== 'xhs' ? (p.platform === 'tiktok' ? '@' : '') + p.handle : '';
    return name + (h ? ' ' + h : '');
  }

  function paintHead() {
    var cr = (feed && feed.creator) || {};
    var live = (feed.bookings || []).filter(liveBooking).length;
    var meta = [];
    if (cr.since) meta.push(fill(t().since, { d: monthYear(cr.since) }));
    if (live) meta.push(t().bookingsN(live));
    $('whoLine').textContent = meta.join(' · ');
    $('whoLine').hidden = !meta.length;
    var list = profiles();
    $('crLinks').innerHTML = list.length
      ? list.map(function (p) {
          return '<a class="plink" href="' + esc(absUrl(p.url)) + '" target="_blank" rel="noopener">' + esc(linkWord(p)) + OUTMARK() + '</a>';
        }).join('')
      : '<p class="crlinks-none">' + esc(t().linksNone) + '</p>';
    $('linksEditWord').textContent = list.length ? t().linksEdit : t().linksAdd;
  }

  function linksFields() {
    var list = profiles();
    var html = PLAT_ORDER.map(function (pl) {
      var mine = list.filter(function (p) { return p.platform === pl; });
      if (!mine.length) mine = [{ url: '' }];
      return mine.map(function (p, i) {
        var id = 'lk_' + pl + '_' + i;
        return '<div class="row"><div><label class="field-label" for="' + id + '">' + esc(PLAT[lang][pl]) + '</label>' +
          '<textarea class="input" id="' + id + '" data-plat="' + pl + '" rows="1" data-oneline inputmode="url" autocapitalize="off" ' +
          'autocomplete="off" spellcheck="false" maxlength="300" placeholder="' + esc(PLACEHOLDER[pl]) + '">' + esc(p.url || '') + '</textarea></div></div>';
      }).join('');
    }).join('');
    $('linksFields').innerHTML = html;
  }

  function linksMsg(text, tone) {
    $('linksMsg').textContent = text || '';
    $('linksMsg').className = 'msg' + (tone ? ' ' + tone : '');
  }

  function openLinks() {
    $('linksTitle').textContent = t().linksTitle;
    $('linksSave').textContent = t().save;
    $('linksCancel').textContent = t().cancel;
    $('linksClose').setAttribute('aria-label', t().close);
    linksFields();
    linksMsg('');
    $('crLinksMsg').textContent = '';
    $('crLinksMsg').className = 'msg';
    window.ADspaceSheet.show($('linksSheet'), { opener: $('linksEdit') });
  }

  function saveLinks() {
    var inputs = Array.prototype.slice.call($('linksFields').querySelectorAll('input, textarea'));
    inputs.forEach(function (i) { i.removeAttribute('aria-invalid'); });
    var urls = inputs.map(function (i) { return i.value.trim(); }).filter(Boolean);
    if (!urls.length) { linksMsg(t().linkNone, 'err'); return; }
    var btn = $('linksSave');
    btn.disabled = true;
    db.rpc('creator_set_profiles', { p_code: code, p_profiles: urls }).then(function (r) {
      btn.disabled = false;
      var d = r.data || {};
      if (r.error || !d || (d.error && d.error !== 'unrecognised' && d.error !== 'taken' && d.error !== 'none')) {
        linksMsg(t().linkFail, 'err');
        return;
      }
      if (d.error) {
        var bad = d.url && inputs.filter(function (i) { return i.value.trim() === d.url; })[0];
        if (d.error === 'unrecognised') linksMsg(fill(t().linkBad, { url: d.url || '' }), 'err');
        else if (d.error === 'taken') linksMsg(t().linkTaken, 'err');
        else linksMsg(t().linkNone, 'err');
        if (bad) { bad.setAttribute('aria-invalid', 'true'); bad.focus(); }
        return;
      }
      feed.creator.profiles = d.profiles || [];
      window.ADspaceSheet.clean();
      window.ADspaceSheet.close();
      paintHead();
      $('crLinksMsg').textContent = d.changed === false ? t().noChange : t().saved;
      $('crLinksMsg').className = 'msg ok';
    }).catch(function () { btn.disabled = false; linksMsg(t().linkFail, 'err'); });
  }

  /* ---- The work queue ---------------------------------------------------
     Four bookings used to be four full cards stacked down the page, each with
     its own upload box, and the one that needed them today was wherever it
     happened to fall. The queue is what they have; the card under it is the
     one they are working on, and the booking that is waiting on them is the
     one that opens by itself. */
  var picked = null;

  function needsCreator(b) {
    return b.state === 'pending_draft' || b.state === 'changes';
  }
  function liveBooking(b) {
    return b.state !== 'withdrawn' && b.state !== 'replaced';
  }
  /* Over: ended, or finished and thanked (2026-10-14: a new booking leads). */
  function overBooking(b) { return !liveBooking(b) || b.state === 'completed'; }
  /* Ordered by what has to be done, not by when it was created: what is
     waiting on them, then what is running, then what is over. */
  function queueOrder(a, b) {
    var rank = function (x) {
      if (needsCreator(x)) return 0;
      if (overBooking(x)) return 2;
      return 1;
    };
    var d = rank(a) - rank(b);
    if (d) return d;
    return String(a.visit_date || '9999').localeCompare(String(b.visit_date || '9999'));
  }

  function pickFrom(rows) {
    var fromHash = (location.hash || '').replace(/^#b=/, '');
    var byHash = rows.filter(function (b) { return b.id === fromHash; })[0];
    if (byHash) return byHash.id;
    var mine = rows.filter(needsCreator)[0];
    if (mine) return mine.id;
    var live = rows.filter(function (b) { return !overBooking(b); })[0];
    return (live || rows[0] || {}).id || null;
  }

  function paintQueue(rows) {
    var q = $('workQueue');
    var box = $('workList');
    q.innerHTML = '';
    box.innerHTML = '';
    if (!rows.length) { q.hidden = true; return; }

    var order = rows.slice().sort(queueOrder);
    if (!picked || !rows.some(function (b) { return b.id === picked; })) picked = pickFrom(order);

    /* One booking is not a queue: the card is the page. */
    q.hidden = order.length < 2;
    if (!q.hidden) {
      order.forEach(function (b) {
        var title = (lang === 'zh' && b.campaign_zh) ? b.campaign_zh : b.campaign;
        var when = b.visit_date ? fmtDate(b.visit_date) : (b.planned_publish ? fmtDate(b.planned_publish) : '');
        var el = document.createElement('button');
        el.type = 'button';
        /* The one waiting on them carries the warn edge this portal gives any
           row that needs somebody, so a booking further down the queue still
           reads as needing them without being opened. */
        el.className = 'qrow' + (b.id === picked ? ' is-on' : '') +
          (needsCreator(b) ? ' is-waiting' : '') + (overBooking(b) ? ' is-off' : '');
        el.setAttribute('aria-current', b.id === picked ? 'true' : 'false');
        el.innerHTML =
          '<span class="qrow-name">' + esc(title || '') + '</span>' +
          (needsCreator(b) ? '<span class="tone is-warn qrow-flag">' + esc(t().needsYou) + '</span>' : '') +
          '<span class="qrow-meta">' + esc([b.brand || '', when].filter(Boolean).join(' · ')) + '</span>';
        el.addEventListener('click', function () {
          if (picked === b.id) return;
          picked = b.id;
          try { location.hash = 'b=' + b.id; } catch (e) {}
          paintQueue(rows);
        });
        q.appendChild(el);
      });
    }

    var one = order.filter(function (b) { return b.id === picked; })[0] || order[0];
    box.appendChild(bookingCard(one));
  }

  /* Back and Forward move between bookings, because the booking is in the
     address and the address is what the browser remembers. */
  window.addEventListener('hashchange', function () {
    if (!feed || $('app').hidden) return;
    var rows = feed.bookings || [];
    if (!rows.length) return;
    var want = (location.hash || '').replace(/^#b=/, '');
    /* An empty address is not "stay where you are": it is the address the
       page opened on, so Back off the first pick puts that pick back. */
    if (!want) want = pickFrom(rows.slice().sort(queueOrder));
    if (!want || want === picked) return;
    if (!rows.some(function (b) { return b.id === want; })) return;
    picked = want;
    paintQueue(rows);
  });

  function chip(state) {
    return '<span class="tone ' + esc(W.tone(state)) + '">' +
      esc(t().step[state] || state) + '</span>';
  }

  /* "As noted below" only where a note is below (2026-09-27). */
  function nextLine(b) {
    if (b.state === 'changes' && !b.change_note) return t().changesBare;
    return t().nextUp[b.state];
  }

  /* The client pages refresh (2026-10-07). The booking as a journey: done
     steps ticked, the one in hand ringed, what follows waiting. Worked out
     from the state on every paint. */
  var AT = { confirmed: 1, pending_visit: 1, pending_draft: 2, changes: 2, submitted: 3, reviewing: 3,
             scheduled: 4, posted: 5, completed: 6 };
  function journeyHtml(b) {
    var at = AT[b.state];
    if (at == null || !window.ADspaceIcons) return '';
    var words = t().journey.slice();
    if (b.push_format === 'seeding') words[1] = t().journeyDelivery;
    return window.ADspaceIcons.journey(words, at);
  }
  /* A number to reach on the day: WhatsApp and a call, read as every wa.me
     link reads one (`ADspaceAPI.waNumber`). */
  function reachHtml(phone) {
    if (String(phone || '').replace(/\D/g, '').length < 8) return '';
    var d = window.ADspaceAPI.waNumber(phone);
    var I = window.ADspaceIcons;
    return '<div class="cx-chips">' +
      '<a class="plink" href="https://wa.me/' + d + '" target="_blank" rel="noopener">' + (I ? I.svg('chat') : '') + esc(t().whatsapp) + '</a>' +
      '<a class="plink" href="tel:+' + d + '">' + (I ? I.svg('phone') : '') + esc(t().call) + '</a></div>';
  }
  function placeHtml(where) {
    return '<div class="cx-chips"><a class="plink" href="https://www.google.com/maps/search/?api=1&query=' +
      encodeURIComponent(where) + '" target="_blank" rel="noopener">' + esc(t().directions) +
      OUTMARK() + '</a></div>';
  }

  function bookingCard(b) {
    var card = document.createElement('section');
    var dead = b.state === 'withdrawn' || b.state === 'replaced';
    card.className = 'booking' + (dead ? ' is-off' : '');
    card.setAttribute('data-id', b.id);

    var seeding = b.push_format === 'seeding';
    var facts = [];
    if (!dead) {
      facts.push([seeding ? t().deliveryOn : t().shootOn,
        b.visit_date ? dayTime(b.visit_date, b.visit_time) : t().tbc, seeding ? 'box' : 'camera']);
      if (b.visit_location) facts.push([t().whereAt, b.visit_location, 'pin', seeding ? '' : placeHtml(b.visit_location)]);
      if (b.visit_pic) facts.push([t().contact, b.visit_pic + (b.visit_pic_phone ? ' · ' + b.visit_pic_phone : ''), 'phone',
        b.visit_pic_phone ? reachHtml(b.visit_pic_phone) : '']);
      if (b.tracking_no) facts.push([t().tracking, b.tracking_no, 'box']);
      var plats = platsOf(b.platforms);
      if (plats.length) facts.push([t().platformsLabel, plats.join(' · '), 'megaphone']);
      if (b.planned_publish) facts.push([t().goLive, fmtDate(b.planned_publish), 'calendar']);
      if (b.submission_due) facts.push([t().draftDue, fmtDate(b.submission_due), 'clock']);
    }
    /* A fact with its chips (the place, the contact) takes its own row, so
       the plain facts come first and pair up (2026-10-20, CRE-1). */
    facts = facts.filter(function (f) { return !f[3]; }).concat(facts.filter(function (f) { return f[3]; }));
    var icon = function (n) { return window.ADspaceIcons ? window.ADspaceIcons.svg(n) : ''; };
    /* What is owed leads the card: the hand-in, its countdown and the
       request it answers, above the facts and the brief. */
    var owed = !dead && needsCreator(b) && b.can_deliver;
    var late = b.submission_due && b.submission_due < ADspaceClock.today();
    var countdown = b.submission_due && ['pending_draft', 'changes'].indexOf(b.state) > -1
      ? '<p class="due-countdown' + (late ? ' is-late' : '') + '">' + icon('clock') + esc(dueWord(b.submission_due)) + '</p>' : '';
    var changeNote = b.state === 'changes' && b.change_note
      ? '<div class="booking-brief is-warn"><div class="kstep-title">' + esc(t().changesHead) +
        '</div><p>' + esc(b.change_note) + '</p></div>' : '';

    var title = (lang === 'zh' && b.campaign_zh) ? b.campaign_zh : b.campaign;
    var brief = (lang === 'zh' && b.brief_zh) ? b.brief_zh : b.brief;

    /* A finished booking folds to its name and state (the user, 2026-10-14:
       "so subsequent new bookings could be the main focus"): no steps, the
       rest under Booking details, shut; the rating stays out until given. */
    var done = b.state === 'completed';
    var unrated = done && !Number(b.rating || 0);
    /* Once approved, the post, its results and the payment form are what is
       owed: they stand where the hand-in stood, above the facts (the rule of
       2026-10-08 for every step; ux-audit CREATOR-1, 2026-10-14). A finished
       booking keeps them, read only, in its fold. */
    var owedPost = !dead && (b.state === 'scheduled' || b.state === 'posted');
    /* Payment details are the page's own card (2026-11-08), asked once,
       never again on each booking. */
    var postBlocks = postsDue(b.state) ? postsHtml(b) : '';
    var rest = dead ? '' :
        (done ? '' : journeyHtml(b)) +
        (owed ? '<div class="cx-nextup"><p class="cx-eyebrow cx-quietlabel">' + esc(t().nextUpWord) + '</p>' +
          '<p class="cx-nextup-title">' + esc(b.state === 'changes' ? t().handInAgain : t().handIn) + '</p>' +
          countdown + changeNote + filesHtml(b) + deliverHtml(b) + '</div>'
          /* Where the booking stands sits where the hand-in stood, above the
             facts: after Submit the creator reads it without scrolling (the
             client pages audit, CR-1, 2026-10-08). */
          : (nextLine(b) ? '<p class="booking-next cx-status">' + esc(nextLine(b)) + '</p>' : '') + countdown) +
        (owedPost ? postBlocks : '') +
        (facts.length ? '<dl class="booking-facts cx-facts">' + facts.map(function (f) {
          return '<div><dt>' + icon(f[2]) + esc(f[0]) + '</dt><dd>' + esc(f[1]) + (f[3] || '') + '</dd></div>';
        }).join('') + '</dl>' : '') +
        (brief ? '<div class="booking-brief"><div class="kstep-title">' + esc(t().briefHead) +
          '</div><p>' + esc(brief).replace(/\n/g, '<br>') + '</p></div>' : '') +
        (owed ? '' : changeNote + filesHtml(b)) +
        (b.caption && !b.can_deliver ? '<div class="booking-caption"><div class="kstep-title">' +
          esc(t().captionLabel) + '</div><p>' + esc(b.caption).replace(/\n/g, '<br>') + '</p></div>' : '') +
        (b.can_deliver && !owed ? deliverHtml(b) : '') +
        (owedPost ? '' : postBlocks) +
        (done && !unrated ? rateHtml(b) : '');
    card.className += done ? ' is-done' : '';
    card.innerHTML =
      '<div class="booking-head"><b>' + esc(title) + '</b>' + (dead ? '' : chip(b.state)) + '</div>' +
      '<p class="booking-brand">' + esc(b.brand || '') + '</p>' +
      (dead ? '<p class="hint">' + esc(t().ended) + '</p>' :
        done ? (unrated ? rateHtml(b) : '') +
          '<details class="booking-fold"><summary>' + esc(t().foldHead) + '</summary><div class="booking-fold-body">' + rest + '</div></details>'
        : rest);

    if (b.can_deliver) wireDeliver(card, b);
    if (postsDue(b.state)) wirePosts(card, b);
    if (b.state === 'completed') wireRate(card, b);
    return card;
  }

  /* ---- Post and results ----------------------------------------------------
     Once the draft is approved the creator fills in each placement's link and,
     over the period the team sets, the platform's numbers: no more sending
     them on WhatsApp for somebody to type in again (the user, 2026-09-27).
     The first link moves the booking to Posted. The period is the team's;
     until it is set, the numbers wait. Numbers only, no screenshots. */
  function postsDue(s) { return ['scheduled', 'posted', 'completed'].indexOf(s) > -1; }
  var HOSTS = { xhs: ['xiaohongshu.com', 'xhslink.com'], instagram: ['instagram.com'],
                tiktok: ['tiktok.com'], facebook: ['facebook.com', 'fb.watch', 'fb.com'] };
  function platKeyOf(p) {
    var k = { rednote: 'xhs', xiaohongshu: 'xhs', xhs: 'xhs', instagram: 'instagram', tiktok: 'tiktok', facebook: 'facebook' };
    return k[String(p || '').trim().toLowerCase()] || String(p || '').trim().toLowerCase();
  }
  function postLinkOk(plat, url) {
    var m = /^https:\/\/([^\/?#]+)/i.exec(url || '');
    if (!m || /\s/.test(url) || /[@:]/.test(m[1])) return false;
    var host = m[1].toLowerCase().replace(/^(www|m|vm|vt)\./, '');
    var ok = HOSTS[platKeyOf(plat)];
    return !ok || ok.indexOf(host) > -1;
  }
  function placementsOf(b) {
    return String(b.platforms || '').split(',').map(function (x) { return x.trim(); }).filter(Boolean);
  }
  function postOf(b, plat) {
    return (b.posts || []).filter(function (p) { return platKeyOf(p.platform) === platKeyOf(plat); })[0] || {};
  }
  /* A count reads with its separators, written and read back alike
     (2026-10-20, CRE-4); the save takes the digits. */
  function numVal(v) {
    if (v == null || v === '') return '';
    var d = String(v).replace(/[,\s]/g, '');
    return /^\d+$/.test(d) ? Number(d).toLocaleString('en-GB') : String(v);
  }
  function postsHtml(b) {
    var open = b.state !== 'completed';
    var rows = placementsOf(b).map(function (plat) {
      var p = postOf(b, plat);
      var word = platsOf(plat)[0] || plat;
      var id = esc(b.id) + '-' + esc(platKeyOf(plat));
      var period = p.measure_from && p.measure_to;
      var nums = [['views', p.views], ['engagements', p.engagements], ['impressions', p.impressions]];
      if (!open) {
        return '<div class="post-entry"><div class="post-entry-head"><b>' + esc(word) + '</b></div>' +
          /* The post as a way out, never the raw address (CREATOR-9), worded
             as the selection page words it. */
          (absUrl(p.post_url) ? '<p class="post-entry-link"><a class="plink" href="' + esc(absUrl(p.post_url)) + '" target="_blank" rel="noopener">' +
            esc(lang === 'zh' ? (platKeyOf(plat) === 'xhs' ? '查看小红书笔记' : '查看' + word + '帖子') : 'View post on ' + word) +
            OUTMARK() + '</a></p>' : '') +
          (period ? '<p class="post-entry-period">' + esc(fill(t().countPeriod, { a: fmtDate(p.measure_from), b: fmtDate(p.measure_to) })) + '</p>' : '') +
          '<dl class="post-nums">' + nums.map(function (n) {
            return '<div><dt>' + esc(t()[n[0]]) + '</dt><dd>' + esc(n[1] == null ? '—' : Number(n[1]).toLocaleString('en-US')) + '</dd></div>';
          }).join('') + '</dl></div>';
      }
      return '<div class="post-entry" data-plat="' + esc(plat) + '">' +
        '<div class="post-entry-head"><b>' + esc(word) + '</b></div>' +
        '<label class="field-label" for="pl-' + id + '">' + esc(t().postLink) + '</label>' +
        '<textarea class="input" id="pl-' + id + '" rows="1" data-oneline inputmode="url" autocapitalize="off" autocomplete="off" spellcheck="false" data-k="url" placeholder="https://">' + esc(p.post_url || '') + '</textarea>' +
        '<label class="field-label" for="pd-' + id + '">' + esc(t().postedOn) + '</label>' +
        '<input class="input" id="pd-' + id + '" type="date" data-k="published" value="' + esc(p.published_at || '') + '">' +
        /* A phone keeps its own date box, in the device's order; the day
           is written under it as the portal writes a date (CREATOR-4). */
        '<p class="post-entry-day" data-day hidden></p>' +
        (period
          ? '<p class="post-entry-period">' + esc(fill(t().countPeriod, { a: fmtDate(p.measure_from), b: fmtDate(p.measure_to) })) + '</p>' +
            '<div class="post-nums-in">' + nums.map(function (n) {
              return '<div><label class="field-label" for="pn-' + n[0] + '-' + id + '">' + esc(t()[n[0]]) + '</label>' +
                '<input class="input" id="pn-' + n[0] + '-' + id + '" type="text" inputmode="numeric" pattern="[0-9]*" data-k="' + n[0] + '" value="' + esc(numVal(n[1])) + '"></div>';
            }).join('') + '</div>'
          : '') +
        '<div class="msg" data-postmsg></div></div>';
    }).join('');
    /* One Save for every placement (ux-audit CREATOR-3, 2026-10-14): blue
       while the post is what is owed, tonal once the payment form is the
       view's one blue action. */
    var foot = open
      ? '<div class="kactions"><button class="btn' + (payDue(b.state) ? '' : ' btn-primary') + '" type="button" data-a="postsave">' +
          esc(t().save) + '</button></div><div class="msg" data-postsmsg></div>'
      : '';
    return '<div class="booking-deliver booking-posts"><div class="kstep-title">' + esc(t().postsHead) + '</div>' + rows + foot + '</div>';
  }
  function wirePosts(card, b) {
    var block = card.querySelector('.booking-posts');
    var btn = block && block.querySelector('[data-a="postsave"]');
    if (!btn) return;
    var boxes = Array.prototype.slice.call(block.querySelectorAll('.post-entry[data-plat]'));
    var KEYS = ['url', 'published', 'views', 'engagements', 'impressions'];
    var read = function (box) {
      var v = {};
      KEYS.forEach(function (k) { var el = box.querySelector('[data-k="' + k + '"]'); if (el) v[k] = el.value.trim(); });
      return v;
    };
    var sayIn = function (box, text, cls) {
      var note = box.querySelector('[data-postmsg]');
      note.textContent = text || ''; note.className = 'msg' + (cls ? ' ' + cls : '');
    };
    var blockMsg = block.querySelector('[data-postsmsg]');
    var sayBlock = function (text, cls) { blockMsg.textContent = text || ''; blockMsg.className = 'msg' + (cls ? ' ' + cls : ''); };
    var was = boxes.map(read);
    boxes.forEach(function (box) {
      var day = box.querySelector('[data-k="published"]');
      var line = box.querySelector('[data-day]');
      var show = function () {
        var v = day.value;
        line.hidden = !!day.__dmy || !v;
        line.textContent = v && !day.__dmy ? fmtDate(v) : '';
      };
      day.addEventListener('change', show);
      day.addEventListener('input', show);
      setTimeout(show, 0);
      ['views', 'engagements', 'impressions'].forEach(function (k) {
        var el = box.querySelector('[data-k="' + k + '"]');
        if (el) el.addEventListener('blur', function () { el.value = numVal(el.value.trim()); });
      });
    });
    /* What one placement sends, or why it cannot: checked for every
       placement before anything is sent. */
    function plan(box, i) {
      var plat = box.getAttribute('data-plat');
      var v = read(box), before = was[i];
      if (!KEYS.some(function (k) { return (v[k] || '') !== (before[k] || ''); })) return null;
      var url = v.url || '';
      if (url && !/^https?:\/\//i.test(url)) url = 'https://' + url;
      url = url.replace(/^http:\/\//i, 'https://');
      if (url && !postLinkOk(plat, url)) return { box: box, bad: fill(t().linkWrong, { p: platsOf(plat)[0] || plat }) };
      var nums = {}, bad = false, any = false;
      ['views', 'engagements', 'impressions'].forEach(function (k) {
        if (v[k] == null) return;
        var n = v[k].replace(/[,\s]/g, '');
        if (n === '') { nums[k] = null; return; }
        if (!/^\d+$/.test(n)) { bad = true; return; }
        nums[k] = Number(n); any = true;
      });
      if (bad) return { box: box, bad: t().numWrong };
      return { box: box, plat: plat, args: {
        p_code: code, p_option: b.id, p_platform: plat, p_url: url || null,
        p_published: v.published || null,
        p_impressions: any ? nums.impressions : null,
        p_engagements: any ? nums.engagements : null,
        p_views: any ? nums.views : null
      } };
    }
    btn.addEventListener('click', function () {
      sayBlock('');
      boxes.forEach(function (box) { sayIn(box, ''); });
      var plans = boxes.map(plan).filter(Boolean);
      var refused = plans.filter(function (x) { return x.bad; });
      if (refused.length) { refused.forEach(function (x) { sayIn(x.box, x.bad, 'err'); }); return; }
      if (!plans.length) { sayBlock(t().noChange); return; }
      btn.disabled = true;
      var outcome = [];
      /* One placement after another, so the first link moves the booking
         to Posted once and each answer is its own. */
      var chain = plans.reduce(function (p, x) {
        return p.then(function () {
          return db.rpc('creator_post_save', x.args).then(function (r) {
            var d = (r && r.data) || {};
            if ((r && r.error) || d.error) {
              outcome.push({ plat: x.plat, values: read(x.box), err: d.error === 'link' ? fill(t().linkWrong, { p: platsOf(x.plat)[0] || x.plat })
                : d.error === 'number' ? t().numWrong
                : d.error === 'period' ? t().periodWait : t().failText });
            } else outcome.push({ plat: x.plat });
          }).catch(function () { outcome.push({ plat: x.plat, values: read(x.box), err: t().failText }); });
        });
      }, Promise.resolve());
      chain.then(function () {
        btn.disabled = false;
        if (!outcome.some(function (o) { return !o.err; })) {
          outcome.forEach(function (o) {
            var box = block.querySelector('.post-entry[data-plat="' + o.plat + '"]');
            if (box) sayIn(box, o.err, 'err');
          });
          return;
        }
        /* Read again, so the step, the chip and the period are the
           database's; each placement's outcome is said once it is drawn,
           and what was refused keeps what was typed. */
        load(code).then(function () {
          var again = document.querySelector('.booking[data-id="' + b.id + '"] .booking-posts');
          if (!again) return;
          outcome.forEach(function (o) {
            var box = again.querySelector('.post-entry[data-plat="' + o.plat + '"]');
            if (!box) return;
            if (o.values) KEYS.forEach(function (k) {
              var el = box.querySelector('[data-k="' + k + '"]');
              if (el && o.values[k] != null) el.value = o.values[k];
            });
            sayIn(box, o.err || t().saved, o.err ? 'err' : 'ok');
          });
        });
      });
    });
  }

  /* Once the post is out its own Save is no longer the booking's one step,
     so it is drawn tonal. Payment details are the page's own card
     (2026-11-08), asked once from the first booking, never on a booking. */
  function payDue(s) { return s === 'posted'; }

  /* What the last block on a finished booking asks. The job is over and the
     payment form has gone, so the one thing still worth a creator's tap is
     how it went for them. Five states and nothing to type: a comment box on
     this page would be a second inbox nobody reads. */
  function rateHtml(b) {
    var given = Number(b.rating || 0);
    var stars = '';
    for (var i = 1; i <= 5; i++) {
      stars += '<button class="star' + (i <= given ? ' is-on' : '') + '" type="button" ' +
        'data-star="' + i + '" role="radio" aria-checked="' + (i === given) + '" ' +
        'aria-label="' + esc(t().rateStar(i)) + '">' +
        '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3.6 2.6 5.3 5.8.8-4.2 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8L3.6 9.7l5.8-.8z"/></svg>' +
        '</button>';
    }
    return '<div class="booking-rate"><div class="kstep-title">' + esc(t().rateHead) + '</div>' +
      '<div class="stars" role="radiogroup" aria-label="' + esc(t().rateHead) + '">' + stars + '</div>' +
      '<div class="msg" data-ratemsg></div></div>';
  }

  function wireRate(card, b) {
    var box = card.querySelector('.booking-rate');
    if (!box) return;
    var note = box.querySelector('[data-ratemsg]');
    box.addEventListener('click', function (e) {
      var btn = e.target.closest && e.target.closest('[data-star]');
      if (!btn) return;
      var n = Number(btn.getAttribute('data-star'));
      Array.prototype.forEach.call(box.querySelectorAll('[data-star]'), function (s) {
        var v = Number(s.getAttribute('data-star'));
        s.classList.toggle('is-on', v <= n);
        s.setAttribute('aria-checked', String(v === n));
      });
      db.rpc('creator_rate', { p_code: code, p_option: b.id, p_stars: n }).then(function (r) {
        var d = (r && r.data) || {};
        if ((r && r.error) || d.error) {
          note.className = 'msg err';
          note.textContent = t().failText;
          return;
        }
        b.rating = n;
        note.className = 'msg ok';
        note.textContent = t().rateThanks;
      }).catch(function () {
        note.className = 'msg err';
        note.textContent = t().failText;
      });
    });
  }

  /* ---- Payment details (2026-11-08) --------------------------------------
     Asked once, from the first booking (`creator_pay_form` answers `due`),
     read back as approved, and changed through the same form, which goes
     back for approval. The ID and account numbers come back as their last
     four alone; one left blank keeps the number held. */
  var pay = null;
  var addrShown = false;
  /* 'address' asks the billing address alone, on the set approved. */
  var payMode = '';
  var BANKS = ['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank', 'Bank Islam', 'Public Bank',
    'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital', '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB', '[SG] CIMB',
    '[SG] Maybank', '[SG] Bank of China'];
  var METHODS = { MYR: ['bank', 'duitnow', 'tng'], SGD: ['bank', 'paynow'] };
  function loadPay() {
    if (!db || !code) return Promise.resolve();
    return db.rpc('creator_pay_form', { p_code: code }).then(function (r) {
      var d = r.data;
      pay = !r.error && d && d.ok ? d : null;
      paintPay();
    }).catch(function () { pay = null; paintPay(); });
  }
  function payDay(ts) { return ADspaceClock.date(ts, { zh: lang === 'zh' }); }
  function paintPay() {
    var box = $('payBox');
    if (!box) return;
    paintPays();
    if (feed) paintTabs();
    box.hidden = !(pay && (pay.due || pay.address_needed));
    if (box.hidden) return;
    var T0 = t(), last = pay.last, paid = pay.paid;
    $('payTitle').textContent = T0.payHead;
    /* Each part of the line held whole, breaking only between parts. */
    var part = function (html, first) { return '<span class="crpay-part">' + (first ? '' : '<span class="crpay-sep"> · </span>') + html + '</span>'; };
    var chip = function (tone, word) { return part('<span class="chip-state ' + tone + '">' + esc(word) + '</span>', true); };
    var line;
    if (!last) line = esc(T0.payNone);
    else if (last.status === 'pending') line = chip('is-warn', paid ? T0.payChangePending : T0.payPending) +
      part(esc(fill(T0.paySentOn, { d: payDay(last.created_at) }))) + part(esc(last.ref));
    else if (last.status === 'declined') line = chip('is-danger', T0.payDeclined) + part(esc(last.note ? last.note : T0.payAgain));
    else if (pay.address_needed) line = chip('is-warn', T0.payAddrNeeded) + part(esc((paid || last).ref));
    else line = chip('is-ok', T0.payApproved) + part(esc((paid || last).ref));
    $('payLine').innerHTML = line;
    var asks = !last || last.status === 'declined' || pay.address_needed;
    $('payEdit').textContent = pay.address_needed ? T0.payAddrGo : asks && !paid ? T0.payGo : T0.payChange;
    $('payEdit').className = 'btn btn-sm' + (asks ? ' btn-primary' : '');
    var f = $('payFacts');
    f.hidden = !paid;
    if (paid) {
      f.innerHTML = [
        [T0.payTo, paid.payee],
        [T0.payMethod, [T0.payMethods[paid.method] || paid.method, paid.bank]],
        [T0.payAccount, fill(T0.payEnding, { n: paid.account_end })],
        [T0.payBilling, [T0.payKinds[paid.bill_kind] || '', fill(T0.payEnding, { n: paid.id_end })]],
        [T0.payName, paid.legal_name],
        [T0.payEmail, paid.email]
      ].map(function (r) {
        var v = typeof r[1] === 'string' ? esc(r[1]) : r[1].filter(Boolean).map(function (x, i) { return part(esc(x), !i); }).join('');
        return '<div><dt>' + esc(r[0]) + '</dt><dd>' + v + '</dd></div>';
      }).join('');
    }
  }
  function paySay(text, tone) { $('payMsg').textContent = text || ''; $('payMsg').className = 'msg' + (tone ? ' ' + tone : ''); }

  /* The form's values while it is open; a number left blank keeps the one
     held, which the database knows by its last four. */
  var payTyped = {};
  /* Each kind of number takes only what it holds: an NRIC 12 digits laid
     out XXXXXX-XX-XXXX, a registration number 12 digits, a passport 20
     letters or digits (as creator_pay_check reads them). */
  var ID_SHAPE = {
    nric: 'inputmode="numeric" data-shape="######-##-####" placeholder="XXXXXX-XX-XXXX"',
    brn: 'inputmode="numeric" data-shape="############"',
    passport: 'data-shape="XXXXXXXXXXXXXXXXXXXX"'
  };
  function payHeld() { return pay && (pay.last && pay.last.status !== 'declined' ? pay.last : pay.paid); }
  function payStart() {
    var h = payHeld() || (pay && pay.last) || {};
    /* The page holds these details masked (2026-11-10): a field opens empty,
       and left blank keeps the one held. */
    var m = !!h.masked;
    payTyped = { bill_kind: h.bill_kind || 'nric', id_no: '', legal_name: m ? '' : h.legal_name || '', tin: m ? '' : h.tin || '',
      address: m ? '' : h.address || '', currency: h.currency || 'MYR', method: h.method || 'bank', bank: h.bank || '', account: '',
      payee: m ? '' : h.payee || '', email: m ? '' : h.email || '', whatsapp: m ? '' : h.whatsapp || '', confirm: false };
  }
  function payRead() {
    Array.prototype.forEach.call($('payFields').querySelectorAll('[data-k]'), function (el) {
      payTyped[el.getAttribute('data-k')] = el.type === 'checkbox' ? el.checked : el.value;
    });
  }
  /* What the details are for (2026-11-10): each payment's e-Invoice to
     LHDN is issued with them, said in its own section above the tick. */
  function einv(more) {
    var T0 = t();
    return '<section class="fsec"><h4 class="fsec-h">' + esc(T0.payEinvHead) + '</h4><p class="crpay-einv">' + esc(T0.payEinv) + '</p>' + (more || '') + '</section>';
  }
  function payFields() {
    var T0 = t(), v = payTyped, h = payHeld();
    if (payMode === 'address') {
      $('payFields').innerHTML = '<div class="row"><div><label class="field-label" for="pf_address">' + esc(T0.payAddress) + '</label>' +
        '<textarea class="input" id="pf_address" data-k="address" aria-required="true" rows="3" maxlength="300">' + esc(v.address || '') + '</textarea>' +
        '<span class="msg" id="pf_addressMsg"></span></div></div>' + einv() + '<div class="msg" id="paySheetMsg" role="status"></div>';
      return;
    }
    var keepId = h && h.bill_kind === v.bill_kind && h.id_end;
    var kept = function (k) { return h && h.masked && h[k] ? h[k] : ''; };
    var keepAs = function (k) { return kept(k) ? fill(T0.payKeepAs, { v: kept(k) }) : ''; };
    var keepAcct = h && h.method === v.method && h.currency === v.currency && String(h.bank || '') === String(v.bank || '') && h.account_end;
    var field = function (k, label, inner, hint) {
      return '<div class="row"><div><label class="field-label" for="pf_' + k + '">' + esc(label) + '</label>' + inner +
        (hint ? '<span class="hint">' + esc(hint) + '</span>' : '') + '<span class="msg" id="pf_' + k + 'Msg"></span></div></div>';
    };
    var input = function (k, req, attrs) {
      return '<input class="input" id="pf_' + k + '" data-k="' + k + '"' + (req ? ' aria-required="true"' : '') + ' ' + (attrs || '') +
        ' value="' + esc(v[k] || '') + '">';
    };
    var options = function (list, word, cur) {
      return list.map(function (o) { return '<option value="' + esc(o) + '"' + (cur === o ? ' selected' : '') + '>' + esc(word ? word[o] : o) + '</option>'; }).join('');
    };
    var methods = METHODS[v.currency] || METHODS.MYR;
    if (methods.indexOf(v.method) < 0) v.method = methods[0];
    var banks = BANKS.filter(function (b) { return (v.currency === 'SGD') === (b.indexOf('[SG]') === 0); });
    $('payFields').innerHTML =
      '<section class="fsec"><h4 class="fsec-h">' + esc(T0.payHeads.billing) + '</h4>' +
        field('bill_kind', T0.payBilling, '<select class="select" id="pf_bill_kind" data-k="bill_kind" data-seg aria-required="true">' +
          options(['nric', 'passport', 'brn'], T0.payKinds, v.bill_kind) + '</select>') +
        field('id_no', T0.payIdLabel[v.bill_kind], input('id_no', !keepId, 'autocomplete="off" autocapitalize="characters" spellcheck="false" ' +
          ID_SHAPE[v.bill_kind]),
          keepId ? fill(T0.payKeep, { n: h.id_end }) : '') +
        field('legal_name', T0.payNameLabel[v.bill_kind], input('legal_name', !kept('legal_name'), 'maxlength="120" autocomplete="name"'), keepAs('legal_name')) +
        field('tin', T0.payTin, input('tin', false, 'maxlength="20" autocapitalize="characters" spellcheck="false" placeholder="' + esc(T0.payOptional) + '"'), keepAs('tin')) +
        field('address', T0.payAddress, '<textarea class="input" id="pf_address" data-k="address"' + (kept('address') ? '' : ' aria-required="true"') +
          ' rows="3" maxlength="300">' + esc(v.address || '') + '</textarea>', keepAs('address')) +
      '</section>' +
      '<section class="fsec"><h4 class="fsec-h">' + esc(T0.payHeads.payment) + '</h4>' +
        field('currency', T0.payCurrency, '<select class="select" id="pf_currency" data-k="currency" data-seg aria-required="true">' + options(['MYR', 'SGD'], null, v.currency) + '</select>') +
        field('method', T0.payMethod, '<select class="select" id="pf_method" data-k="method" aria-required="true">' + options(methods, T0.payMethods, v.method) + '</select>') +
        (v.method === 'bank' ? field('bank', T0.payBank, '<select class="select" id="pf_bank" data-k="bank" aria-required="true"><option value="">' +
          esc(T0.payChooseBank) + '</option>' + options(banks, null, v.bank) + '</select>') : '') +
        field('account', T0.payAcctLabel[v.method], input('account', !keepAcct, 'inputmode="' + (v.method === 'bank' ? 'numeric' : 'text') + '" autocomplete="off" spellcheck="false" maxlength="40"'),
          keepAcct ? fill(T0.payKeep, { n: h.account_end }) : '') +
        field('payee', T0.payPayee, input('payee', !kept('payee'), 'maxlength="120"'), keepAs('payee')) +
      '</section>' +
      '<section class="fsec"><h4 class="fsec-h">' + esc(T0.payHeads.contact) + '</h4>' +
        field('email', T0.payEmail, input('email', !kept('email'), 'type="email" inputmode="email" autocomplete="email" maxlength="160" placeholder="email@adspace.me"'), keepAs('email')) +
        field('whatsapp', T0.payWhatsapp, input('whatsapp', !kept('whatsapp'), 'type="tel" inputmode="tel" autocomplete="tel" maxlength="20" placeholder="012-345 6789"'), keepAs('whatsapp')) +
      '</section>' + einv('<label class="tickline"><input type="checkbox" id="pf_confirm" data-k="confirm"' + (v.confirm ? ' checked' : '') + '><span>' + esc(T0.payConfirm) + '</span></label>' +
        '<span class="msg" id="pf_confirmMsg"></span>') +
      '<div class="msg" id="paySheetMsg" role="status"></div>';
    if (window.ADspaceForm) window.ADspaceForm.scan($('payFields'));
  }
  function openPay(opener, mode) {
    var T0 = t();
    payMode = mode || '';
    payStart();
    $('paySheetTitle').textContent = payMode === 'address' ? T0.payAddrGo : T0.payHead;
    $('paySend').textContent = payMode === 'address' ? T0.save : T0.payGo;
    $('payCancel').textContent = T0.cancel;
    $('payClose').setAttribute('aria-label', T0.close);
    payFields();
    paySay('');
    window.ADspaceSheet.show($('paySheet'), { opener: opener || $('payEdit') });
  }
  function sendPay() {
    payRead();
    var T0 = t(), btn = $('paySend');
    Array.prototype.forEach.call($('payFields').querySelectorAll('[aria-invalid]'), function (el) { el.removeAttribute('aria-invalid'); });
    Array.prototype.forEach.call($('payFields').querySelectorAll('.msg'), function (el) { el.textContent = ''; el.className = 'msg'; });
    var wrong = function (k) {
      var el = $('pf_' + k), m = $('pf_' + k + 'Msg');
      var said = T0.payBad[k]; if (said && typeof said === 'object') said = said[payTyped.bill_kind];
      if (m) { m.textContent = said || T0.payFail; m.className = 'msg err'; }
      if (el) { el.setAttribute('aria-invalid', 'true'); try { el.focus(); } catch (e) {} }
    };
    if (payMode === 'address') {
      if (String(payTyped.address || '').trim().length < 5) { wrong('address'); return; }
      btn.disabled = true;
      db.rpc('creator_pay_address', { p_code: code, p_address: payTyped.address }).then(function (r) {
        btn.disabled = false;
        var d = r.data || {};
        if (d.error === 'bad') { wrong('address'); return; }
        if (d.error === 'locked') { $('paySheetMsg').textContent = W.lockedLine(T0, d.minutes); $('paySheetMsg').className = 'msg err'; return; }
        if (r.error || d.error) { $('paySheetMsg').textContent = T0.payFail; $('paySheetMsg').className = 'msg err'; return; }
        window.ADspaceSheet.close();
        loadPay().then(function () { paySay(T0.payAddrSent, 'ok'); });
      }).catch(function () { btn.disabled = false; $('paySheetMsg').textContent = T0.payFail; $('paySheetMsg').className = 'msg err'; });
      return;
    }
    if (!payTyped.confirm) { wrong('confirm'); return; }
    btn.disabled = true;
    var vals = {};
    Object.keys(payTyped).forEach(function (k) { vals[k] = payTyped[k]; });
    vals.confirm = 'true';
    if (vals.method !== 'bank') vals.bank = '';
    db.rpc('creator_pay_submit', { p_code: code, p_values: vals }).then(function (r) {
      btn.disabled = false;
      var d = r.data || {};
      if (r.error || !d) { $('paySheetMsg').textContent = T0.payFail; $('paySheetMsg').className = 'msg err'; return; }
      if (d.error === 'bad') { wrong(d.field); return; }
      if (d.error === 'locked') { $('paySheetMsg').textContent = W.lockedLine(T0, d.minutes); $('paySheetMsg').className = 'msg err'; return; }
      if (d.error === 'too-many') { $('paySheetMsg').textContent = T0.payTooMany; $('paySheetMsg').className = 'msg err'; return; }
      if (d.error) { $('paySheetMsg').textContent = T0.payFail; $('paySheetMsg').className = 'msg err'; return; }
      window.ADspaceSheet.close();
      loadPay().then(function () { paySay(T0.paySent, 'ok'); paint(); });
    }).catch(function () { btn.disabled = false; $('paySheetMsg').textContent = T0.payFail; $('paySheetMsg').className = 'msg err'; });
  }

  function isImg(k) { return k === 'image'; }
  function kindLabel(f) {
    return String(f.name || '').split('.').pop().toUpperCase() || 'FILE';
  }

  /* Two shapes, because the file is doing two different jobs. While the
     creator is still assembling a hand-in it is a thing they are handling —
     tiles they can look over and take back off. Once it is submitted it is a
     receipt: the page cannot play a 300 MB video or open a PDF inside a
     card, so a wall of 9:16 squares showing a file type and a truncated name
     spent most of the screen saying nothing. It becomes an attachment line,
     which is what it is. */
  function filesHtml(b) {
    var files = b.files || [];
    if (!files.length) return '';
    /* At Submitted the box stays open for more files, but a file already
       handed in keeps no ×: a submission under review is not emptied from
       here, and the database refuses it too (creator_can_retract). */
    var body = b.can_deliver
      ? '<div class="filegrid" data-files>' + files.map(function (f) {
          return fileHtml(f, needsCreator(b));
        }).join('') + '</div>'
      : '<div class="filepins" data-files>' + files.map(pinHtml).join('') + '</div>';
    return '<div class="booking-files"><div class="kstep-title">' +
      esc(b.can_deliver ? t().addFiles : t().filesHead) + '</div>' + body + '</div>';
  }

  /* Kilobytes are what a phone reports about a file it has sent, and the size
     is the one fact that says a 40 MB video and a stray 2 KB screenshot are
     not the same hand-in. */
  function sizeOf(bytes) {
    var n = Number(bytes || 0);
    if (!n) return '';
    if (n >= 1048576) return Math.round(n / 1048576) + ' MB';
    return Math.max(1, Math.round(n / 1024)) + ' KB';
  }

  function pinHtml(f) {
    var size = sizeOf(f.bytes);
    return '<a class="filepin" href="' + esc(absUrl(f.url)) + '" target="_blank" rel="noopener">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
        'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<path d="M21 11.5 12.5 20a5 5 0 0 1-7-7l8-8a3.3 3.3 0 0 1 4.7 4.7l-8 8a1.7 1.7 0 0 1-2.4-2.4l7.3-7.3"/>' +
      '</svg>' +
      '<span class="filepin-name">' + esc(f.name) + '</span>' +
      (size ? '<span class="filepin-size">' + esc(size) + '</span>' : '') +
    '</a>';
  }

  /* Taking a file back off is theirs only while we are still waiting for the
     draft. Once it is handed in it is ours, and a × on it would offer a
     creator a way to empty a submission we are already reviewing. */
  function fileHtml(f, mine) {
    return '<div class="filecard" data-file="' + esc(f.id) + '">' +
      /* A thumbnail that cannot load shows what the file is rather than the
         browser's broken image mark, which tells a creator their work is gone
         when it is only the preview that failed. */
      (isImg(f.kind)
        ? '<img src="' + esc(f.url) + '" alt="" loading="lazy" ' +
          'onerror="this.remove()"><span class="filecard-kind">' +
          esc(kindLabel(f)) + '</span>'
        : '<span class="filecard-kind">' + esc(kindLabel(f)) + '</span>') +
      '<span class="filecard-name">' + esc(f.name) + '</span>' +
      (mine ? '<button class="filecard-x" type="button" data-a="rm" aria-label="' +
        esc(t().remove + ' ' + f.name) + '">×</button>' : '') +
      '</div>';
  }

  function deliverHtml(b) {
    return '<div class="booking-deliver">' +
      (needsCreator(b) ? '' : '<div class="kstep-title">' + esc(t().deliverHead) + '</div>') +
      /* One large area to tap (or drop onto), the file field itself laid
         over it unseen, so the browser's own picker opens from anywhere on
         it and the field keeps its name. */
      '<label class="cx-drop" for="pick-' + esc(b.id) + '">' +
        (window.ADspaceIcons ? window.ADspaceIcons.svg('upload') : '') +
        '<b>' + esc(t().dropTitle) + '</b><span>' + esc(t().dropSub) + '</span>' +
        '<input class="cx-drop-in" type="file" id="pick-' + esc(b.id) + '" multiple ' +
          'accept="' + esc(API.uploadAccept(['image', 'video', 'pdf'])) + '" data-a="pick" aria-label="' + esc(t().addFiles) + '"></label>' +
      '<div class="filegrid" data-held' + ((held[b.id] || []).length ? '' : ' hidden') + '>' +
        heldHtml(b.id) + '</div>' +
      /* The same progress the console draws on Content Review: what is going
         up on the left, how far on the right, one bar under both. A thin bar
         with "Uploading 1/1" beside it said neither how far it had got nor
         what it was waiting for, so a 300 MB video looked identical whether
         it was moving or dead. */
      '<div class="progress" data-up hidden>' +
        '<div class="progress-head"><span data-uptext></span><span data-uppct></span></div>' +
        '<div class="progress-track"><div class="progress-fill" data-bar></div></div></div>' +
      '<label class="field-label" for="cap-' + esc(b.id) + '">' + esc(t().captionLabel) + '</label>' +
      '<textarea class="input textarea" id="cap-' + esc(b.id) + '" rows="2" maxlength="5000" data-cap ' +
        'placeholder="' + esc(t().captionHint) + '">' + esc(capOf(b)) + '</textarea>' +
      '<div class="kactions"><button class="btn btn-go" type="button" data-a="submit">' +
        esc(b.state === 'submitted' ? t().update : t().submit) + '</button></div>' +
      '<div class="msg" data-msg></div></div>';
  }

  /* A caption typed and not yet handed in is kept a booking, so a booking
     switch, the language or a repaint never empties it (audit F4,
     2026-10-10). It lives in this tab's session, under the code: it ends
     with the tab, on Submit, and on Forget this device. It is never sent
     by anything but Submit. */
  var DRAFTS = 'adspace-creator-drafts:';
  var drafts = {};
  function draftsLoad() {
    drafts = {};
    try { var v = JSON.parse(sessionStorage.getItem(DRAFTS + code) || '{}'); if (v && typeof v === 'object') drafts = v; } catch (e) {}
  }
  function draftsKeep() {
    try {
      if (Object.keys(drafts).length) sessionStorage.setItem(DRAFTS + code, JSON.stringify(drafts));
      else sessionStorage.removeItem(DRAFTS + code);
    } catch (e) {}
  }
  function capOf(b) { return Object.prototype.hasOwnProperty.call(drafts, b.id) ? drafts[b.id] : (b.caption || ''); }
  document.addEventListener('input', function (e) {
    var f = e.target;
    if (!f || !f.hasAttribute || !f.hasAttribute('data-cap')) return;
    var id = String(f.id || '').replace(/^cap-/, '');
    var b = feed && (feed.bookings || []).filter(function (x) { return x.id === id; })[0];
    if (b && f.value === (b.caption || '')) delete drafts[id]; else drafts[id] = f.value;
    draftsKeep();
  });

  /* Files picked but not yet handed in stay on this device, one list a
     booking: shown from the device, taken off with × at no cost, and sent to
     storage only when Submit is pressed. A file removed before then never
     reaches S3. They live in memory, so a reload lets them go, and leaving
     the page with one waiting is warned about. */
  var held = {};

  function heldHtml(id) {
    return (held[id] || []).map(function (h, i) {
      var f = h.file;
      return '<div class="filecard is-held" data-held-i="' + i + '">' +
        (kindOf(f) === 'image'
          ? '<img src="' + esc(h.url) + '" alt="" onerror="this.remove()">'
          : '') +
        '<span class="filecard-kind">' + esc(String(f.name.split('.').pop() || '').toUpperCase()) + '</span>' +
        '<span class="filecard-name">' + esc(f.name) + '</span>' +
        '<button class="filecard-x" type="button" data-a="unhold" aria-label="' +
          esc(t().remove + ' ' + f.name) + '">×</button>' +
        '</div>';
    }).join('');
  }

  function letGo(h) { try { URL.revokeObjectURL(h.url); } catch (e) {} }

  window.addEventListener('beforeunload', function (e) {
    var waiting = Object.keys(held).some(function (k) { return held[k].length; }) || Object.keys(drafts).length > 0;
    if (!waiting) return;
    e.preventDefault();
    e.returnValue = '';
  });

  // ---- Upload ---------------------------------------------------------------

  /* A phone does not always say what a file is: a .mov picked from Files
     can arrive with no type at all, and a video recorded as `file` was drawn
     in the console as an attachment that downloaded when pressed. The
     extension is the fallback, for the kind and for the type S3 stores, so
     the console's player and the browser's own viewer both get a real type. */
  var EXT_TYPE = {
    mp4: 'video/mp4', m4v: 'video/x-m4v', mov: 'video/quicktime', webm: 'video/webm', mkv: 'video/x-matroska',
    jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp',
    heic: 'image/heic', heif: 'image/heif', pdf: 'application/pdf'
  };
  function typeOf(file) {
    if (file.type) return file.type;
    var ext = String(file.name || '').split('.').pop().toLowerCase();
    return EXT_TYPE[ext] || 'application/octet-stream';
  }
  function kindOf(file) {
    var type = typeOf(file);
    if (/^image\//.test(type)) return 'image';
    if (/^video\//.test(type)) return 'video';
    return 'file';
  }

  /* A creator hands in video, so the ceiling is the one the team quoted them
     and not whatever the browser will attempt. Refused here, before a single
     byte moves, because a file that is turned away after a ten minute upload
     is a file uploaded twice. */
  function maxBytes() {
    var cfg = window.ADSPACE_CONFIG || {};
    return (((cfg.s3 && cfg.s3.maxUploadMB) || 1024)) * 1024 * 1024;
  }

  function fill(s, map) {
    return String(s).replace(/\{(\w+)\}/g, function (m, k) {
      return map[k] == null ? m : map[k];
    });
  }

  /* No total deadline: 300 MB up a Malaysian home line is slow, not stuck.
     Silence is stuck, so the attempt ends when no byte has moved for two
     minutes, with a reason rather than a bar nobody can leave. */
  var STALL_MS = 120000;

  function putToS3(url, blob, contentType, onProgress) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      var timer;
      function stop() { clearTimeout(timer); }
      function tick() {
        stop();
        timer = setTimeout(function () {
          try { xhr.abort(); } catch (e) {}
          reject(new Error('stalled'));
        }, STALL_MS);
      }
      xhr.open('PUT', url, true);
      xhr.setRequestHeader('Content-Type', contentType || 'application/octet-stream');
      xhr.setRequestHeader('Cache-Control', 'public, max-age=31536000, immutable');
      xhr.upload.onprogress = function (e) {
        tick();
        if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total);
      };
      // Every byte is out; S3 has still to answer, which is its own wait.
      xhr.upload.onload = function () { tick(); if (onProgress) onProgress(1); };
      xhr.onload = function () {
        stop();
        if (xhr.status >= 200 && xhr.status < 300) resolve();
        else reject(new Error('storage rejected the upload (HTTP ' + xhr.status + ')'));
      };
      xhr.onerror = function () { stop(); reject(new Error('the connection dropped')); };
      xhr.send(blob);
      tick();
    });
  }

  /* A write with no deadline is how a page comes to sit on a full bar for ever.
     Supabase's fetch has none of its own, so one is put on it here. */
  function within(p, ms) {
    return new Promise(function (resolve, reject) {
      var done = false;
      var timer = setTimeout(function () {
        if (!done) { done = true; reject(new Error('timed out')); }
      }, ms);
      p.then(function (v) {
        if (done) return; done = true; clearTimeout(timer); resolve(v);
      }, function (e) {
        if (done) return; done = true; clearTimeout(timer); reject(e);
      });
    });
  }

  // The card a repaint has just rebuilt, found again by the booking it is for.
  function sayOn(id, text, cls) {
    var el = document.querySelector('.booking[data-id="' + id + '"] [data-msg]');
    if (!el) return;
    el.textContent = text || '';
    el.className = 'msg' + (cls ? ' ' + cls : '');
  }

  function wireDeliver(card, b) {
    var msgBox = card.querySelector('[data-msg]');
    var up     = card.querySelector('[data-up]');
    var bar    = card.querySelector('[data-bar]');
    var upText = card.querySelector('[data-uptext]');
    var upPct  = card.querySelector('[data-uppct]');
    var pick   = card.querySelector('[data-a="pick"]');
    var send   = card.querySelector('[data-a="submit"]');
    var busy   = false;

    function say(text, cls) {
      msgBox.textContent = text || '';
      msgBox.className = 'msg' + (cls ? ' ' + cls : '');
    }

    /* Submit is shut while files are still going up, or the creator is told to
       attach a file they are watching upload. That is the error they reported. */
    function lock(on) {
      busy = on;
      send.disabled = on;
      pick.disabled = on;
    }

    function show(i, n, file, pct, saving) {
      up.hidden = false;
      upText.textContent = (n > 1 ? i + '/' + n + ' · ' : '') + file.name;
      upPct.textContent = saving ? t().saving : Math.round(pct * 100) + '%';
      bar.style.width = Math.round(pct * 100) + '%';
    }

    // One file: signed, sent, then recorded. It is not uploaded until the row
    // exists, so every step's failure is a failure of the whole file.
    function sendOne(file, i, n) {
      show(i, n, file, 0, false);
      /* The name's extension where sign-upload takes it, else the one its
         type has (a phone's file may carry no extension; 2026-10-17). */
      var ext = (file.name.split('.').pop() || '').toLowerCase().replace(/[^a-z0-9]/g, '');
      if (!EXT_TYPE[ext]) ext = Object.keys(EXT_TYPE).filter(function (k) { return EXT_TYPE[k] === typeOf(file); })[0] || ext;
      return db.functions.invoke('sign-upload', {
        body: { ext: ext || 'bin', size: file.size, creatorCode: code, optionId: b.id }
      }).then(function (r) {
        if (!r.error && r.data && r.data.uploadUrl) return r;
        /* The reason is read where supabase-js leaves a non-2xx answer
           (2026-10-17): a type sign-upload does not take is said so. */
        return API.fnRefusal(r).then(function (why) {
          var e = new Error(why || (r.error && r.error.message) || 'refused');
          e.refused = why;
          throw e;
        });
      }).then(function (r) {
        return putToS3(r.data.uploadUrl, file, r.data.contentType || typeOf(file), function (p) {
          show(i, n, file, p, p >= 1);
        }).then(function () {
          show(i, n, file, 1, true);
          return within(db.rpc('creator_add_file', {
            p_code: code, p_option: b.id, p_url: r.data.publicUrl,
            p_name: file.name, p_kind: kindOf(file), p_bytes: file.size
          }), 60000);
        });
      }).then(function (res) {
        /* The file reaching storage is only half of it: until this row is
           written the upload is invisible to everybody. This check existed and
           threw from inside a fulfilment handler whose sibling rejection
           handler cannot catch it, so the one error worth reporting went
           nowhere: the bar stood at 100% and Submit then said no file was
           attached. Every failure below reaches the .catch on the queue. */
        var bad = (res && res.error) || (res && res.data && res.data.error);
        if (bad) throw new Error(typeof bad === 'string' ? bad : (bad.message || 'not saved'));
      });
    }

    var grid = card.querySelector('[data-held]');
    function paintHeld() {
      grid.innerHTML = heldHtml(b.id);
      grid.hidden = !(held[b.id] || []).length;
    }
    grid.addEventListener('click', function (e) {
      var x = e.target.closest && e.target.closest('[data-a="unhold"]');
      if (!x || busy) return;
      var i = Number(x.closest('[data-held-i]').getAttribute('data-held-i'));
      var list = held[b.id] || [];
      if (list[i]) { letGo(list[i]); list.splice(i, 1); }
      paintHeld();
    });

    pick.addEventListener('change', function () {
      var picked = Array.prototype.slice.call(this.files || []);
      this.value = '';
      if (busy || !picked.length) return;
      say('');

      var cap = maxBytes();
      var big = picked.filter(function (f) { return f.size > cap; });
      var queue = picked.filter(function (f) { return f.size <= cap; });
      var mb = Math.round(cap / 1048576);
      if (big.length) {
        say(big.length === 1
          ? fill(t().sizeOne, { file: big[0].name, mb: mb })
          : fill(t().sizeMany, { n: big.length, mb: mb }), 'err');
      }
      if (!queue.length) return;
      held[b.id] = (held[b.id] || []).concat(queue.map(function (f) {
        return { file: f, url: URL.createObjectURL(f) };
      }));
      paintHeld();
    });

    /* Submit sends what is held, one file at a time with the bar, and hands
       in only once every one is in. A file that fails stays held, named, and
       nothing is handed in; the ones that went up are kept, so pressing
       Submit again sends only what is left. */
    send.addEventListener('click', function () {
      var btn = this;
      if (busy) return;
      var cap = card.querySelector('[data-cap]').value;
      var list = held[b.id] || [];
      var was = btn.textContent;
      lock(true);
      btn.textContent = t().submitting;
      say('');
      var failed = [], wrongType = 0, tooMany = 0;

      function run(i) {
        if (i >= list.length) return Promise.resolve();
        var h = list[i];
        return sendOne(h.file, i + 1, list.length).then(function () {
          h.sent = true;
        }, function (e) {
          failed.push(h.file.name);
          if (e && e.refused === 'bad_extension') wrongType++;
          if (e && e.refused === 'too_many') tooMany++;
          if (window.console) console.warn('[creator upload] ' + h.file.name, e);
        }).then(function () { return run(i + 1); });
      }

      function finish(text, cls) {
        up.hidden = true;
        lock(false);
        btn.textContent = was;
        if (text) say(text, cls);
      }

      run(0).then(function () {
        list.filter(function (h) { return h.sent; }).forEach(letGo);
        held[b.id] = list.filter(function (h) { return !h.sent; });
        paintHeld();
        if (failed.length) {
          var text = failed.length === 1
            ? fill(t().failOne, { file: failed[0] })
            : fill(t().failMany, { n: failed.length });
          /* A file of a kind sign-upload does not take is named for what it
             is, never "Please try again" (2026-10-17). */
          if (wrongType) text = (wrongType === failed.length ? '' : text + ' ') + t().uploadType;
          if (tooMany) text = (tooMany === failed.length ? '' : text + ' ') + t().uploadMany;
          /* Repainted from the database so the files that did go up show as
             handed in, and the answer written onto the card that replaced
             this one. */
          return db.rpc('get_creator', { p_code: code }).then(function (r) {
            if (r.data && !r.data.error) { feed = r.data; paint(); sayOn(b.id, text, 'err'); }
            else finish(text, 'err');
          }, function () { finish(text, 'err'); });
        }
        return db.rpc('creator_submit', { p_code: code, p_option: b.id, p_caption: cap }).then(function (r) {
          var d = r.data || {};
          if (d.error === 'empty') { finish(t().needFiles, 'err'); return; }
          if (d.error === 'too-long') { finish(t().tooLong, 'err'); return; }
          if (r.error || d.error) { finish(t().failText, 'err'); return; }
          delete drafts[b.id]; draftsKeep();
          finish();
          load(code);
        }).catch(function () { finish(t().failText, 'err'); });
      });
    });
  }

  // Removing a file is the creator's own, and only while we are still waiting.
  document.addEventListener('click', function (e) {
    var x = e.target.closest && e.target.closest('[data-a="rm"]');
    if (!x) return;
    var cardEl = x.closest('.filecard');
    db.rpc('creator_remove_file', { p_code: code, p_file: cardEl.getAttribute('data-file') })
      .then(function () { load(code); });
  });

  // ---- Language and sign out ------------------------------------------------

  function setLang(next) {
    lang = next;
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    /* The bar's kicker follows the page's language (CREATOR-7). */
    if (window.ADspaceChrome && window.ADspaceChrome.kicker) window.ADspaceChrome.kicker(lang === 'zh' ? '创作者平台' : 'Creator Portal');
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    $('codeInput').setAttribute('aria-label', t().codeTitle);
    $('codeGo').textContent = t().openCode;
    $('crTabs').setAttribute('aria-label', t().tabsLabel);
    $('workQueue').setAttribute('aria-label', t().work);
    if (following && window.ADspacePush) window.ADspacePush.relabel();
    if (feed) paint(); else if (!$('stateBox').hidden) {
      if (!$('codeRow').hidden) askCode();
    }
  }
  if ($('langToggle')) {
    $('langToggle').addEventListener('click', function () { setLang(lang === 'en' ? 'zh' : 'en'); });
  }

  var chromeActions = window.ADspaceChrome && window.ADspaceChrome.actions();
  if (chromeActions) {
    var forgetBtn = document.createElement('button');
    forgetBtn.className = 'pill';
    forgetBtn.id = 'signOutBtn'; forgetBtn.type = 'button';
    forgetBtn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 17l5-5-5-5"/><path d="M15 12H3"/><path d="M12 4h6a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-6"/></svg><span></span>';
    /* Named and hidden from the start. Its label was only written once a
       booking painted, so the sign-in cover carried an icon-only button with
       no name, offering to sign out of a session nobody had yet. */
    forgetBtn.querySelector('span').textContent = t().signOut;
    forgetBtn.setAttribute('aria-label', t().signOut);
    forgetBtn.hidden = true;
    /* Just left of the language toggle, which keeps the far right on every
       client page: the bell, then sign out, then 中文 (the user, 2026-09-28). */
    chromeActions.insertBefore(forgetBtn, $('langToggle') || null);
  }
  $('signOutBtn').addEventListener('click', function () {
    // The creator's media pass goes with the device's code (second audit, item 7).
    if (window.ADspaceMedia && window.ADspaceMedia.forget) window.ADspaceMedia.forget({ client: true });
    forget(); askCode();
  });
  $('linksEdit').addEventListener('click', openLinks);
  $('payEdit').addEventListener('click', function () { paySay(''); openPay($('payEdit'), pay && pay.address_needed ? 'address' : ''); });
  $('paySend').addEventListener('click', sendPay);
  $('payCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('payClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  /* A choice that changes the fields under it redraws them, keeping what
     was typed. */
  $('payFields').addEventListener('change', function (e) {
    var k = e.target && e.target.getAttribute('data-k');
    if (k !== 'bill_kind' && k !== 'currency' && k !== 'method' && k !== 'bank') return;
    payRead();
    if (k === 'currency') payTyped.bank = '';
    // One kind's number is never another's.
    if (k === 'bill_kind') payTyped.id_no = '';
    payFields();
    var again = $('pf_' + k); if (again) try { again.focus(); } catch (x) {}
  });
  $('linksSave').addEventListener('click', saveLinks);
  $('linksCancel').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('linksClose').addEventListener('click', function () { window.ADspaceSheet.close(); });
  $('linksFields').addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); saveLinks(); }
  });

  var checking = false, tried = '';
  $('codeGo').addEventListener('click', function () {
    var c = tidy($('codeInput').value);
    if (c.length !== 8) {
      $('stateMsg').textContent = t().codeWrong;
      $('stateMsg').className = 'msg err';
      return;
    }
    if (checking) return;
    checking = true; tried = c;
    var done = function () { checking = false; };
    load(c, true).then(done, done);
  });
  /* The code checks itself once its eighth character is typed or pasted
     (the user, 2026-10-27): the same code is not sent again until it is
     changed, and nothing goes while an input method is composing. Open
     stays for the keyboard and for a try again. */
  function autoCheck() {
    var c = tidy($('codeInput').value);
    if (c.length < 8) { tried = ''; return; }
    if (c !== tried && !checking) $('codeGo').click();
  }
  $('codeInput').addEventListener('compositionend', autoCheck);
  $('codeInput').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { e.preventDefault(); $('codeGo').click(); }
  });
  /* The code reads as it is printed, 7K2M-9PQR: the dash comes by itself
     once the fourth character is typed and a deletion takes it back
     (the user, 2026-10-27); tidy() drops it, so the code sent never holds it. */
  function codeShape(raw, adding) {
    var c = tidy(raw).slice(0, 8);
    return c.length > 4 || (adding && c.length === 4) ? c.slice(0, 4) + '-' + c.slice(4) : c;
  }
  $('codeInput').addEventListener('input', function (e) {
    var el = this, adding = !/^delete/.test(e.inputType || '');
    var pos = el.selectionStart == null ? el.value.length : el.selectionStart;
    var before = tidy(el.value.slice(0, pos)).length;
    var v = codeShape(el.value, adding);
    if (v !== el.value) {
      el.value = v;
      var at = Math.min(v.length, before + (before > 4 || (before === 4 && adding) ? 1 : 0));
      try { el.setSelectionRange(at, at); } catch (x) {}
    }
    if (!e.isComposing) autoCheck();
  });

  // ---- Start ----------------------------------------------------------------

  setLang('en');
  var fromLink = tidy(new URLSearchParams(location.search).get('k') || '');
  var kept = '';
  try { kept = localStorage.getItem(KEY) || ''; } catch (e) {}
  var start = fromLink || kept;
  /* The link's code is stored, so the address bar stops carrying it around;
     the pane and the booking an email named (`?tab=`, `#b=`) stay. */
  if (fromLink) {
    var rest = new URLSearchParams(location.search);
    rest.delete('k');
    history.replaceState(null, '', location.pathname + (rest.toString() ? '?' + rest.toString() : '') + location.hash);
  }
  /* The page's own turning mark stands while it loads (`.pageload`, 2026-10-15). */
  if (start.length === 8) load(start);
  else { askCode(); if (fromLink) linkWrong(fromLink); }
})();
