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
 *                           budget, the commitment, the one-time items
 *   4 Your details          name, work email, WhatsApp, brand, industry,
 *                           Planned commencement (a period, or On a
 *                           specific date and the day), consent; View
 *                           quotation makes the quotation
 *   5 Your quotation        priced by the database (`quote-request`, then
 *                           `quote_website_read` by its key, `?q=` in the
 *                           address), the rates at once; Download; beside
 *                           it Accept this quotation, else the colleague
 *                           who took the lead. The link shows the latest revision the
 *                           team made of it. No billing is asked: the Letter
 *                           of Offer is the sales team's.
 *
 * No rate is shown before the quotation: the catalogue (`quote_catalogue`)
 * holds none (the user, 2026-11-25: "Prices after we send"). The steps are
 * the boards QuotePhone and QuoteDesk: the plans as cards (Without ads /
 * With ads, the middle one Recommended), the chosen plan's content and
 * inclusions, platforms with their ink marks, files, 6, 12 or 24 months. What the person picked is kept in this tab
 * (`adspace-quote`), so Back and a refresh keep it.
 */
(function () {
  'use strict';
  var AGENCY = window.ADspaceAgency || {};
  var API = window.ADspaceAPI, db = API && API.client;
  var cfg = window.ADSPACE_CONFIG || {};
  var KEEP = 'adspace-quote', LANG_KEY = 'adspace.quote.lang';
  function $(id) { return document.getElementById(id); }
  function esc(s) { return window.ADspaceWords.esc(s); }
  /* A note one sentence a line, as every client form draws it (js/words.js). */
  function noteH(s) { return window.ADspaceWords.note(s); }

  var WORDS = {
    en: {
      lang: '中文',
      introT: 'Get your quotation',
      introP: 'Select the services your brand requires and request your quotation.',
      introSteps: ['Select the services you require.', 'Choose your plan and customise the content, languages and commitment.',
        'Provide your contact details. ' + AGENCY.trading_name + ' will review your request and send your quotation on WhatsApp.', 'Accept and sign the quotation on this page. ' + AGENCY.trading_name + ' will then confirm your start date.'],
      introNote: 'This takes approximately three minutes.',
      needT: 'Choose your services',
      need: {
        social: ['Social media management', 'Monthly content and account management'],
        ads: ['Advertising', 'Meta and TikTok campaigns, managed monthly'],
        content: ['Content production', 'Graphics and videos, charged per item'],
        koc: ['KOC or KOL campaign', 'Creators engaged for your brand'],
        verify: ['Account verification', 'Meta Verified and rednote Professional']
      },
      needNone: 'Select at least one service.',
      reqOnly: 'KOL campaigns and custom creator lists are quoted on request. Please add a service with a listed rate, or contact ' + AGENCY.trading_name + ' on WhatsApp.',
      planT: 'Platforms and plan', platsH: 'Choose your platforms', planH: 'Choose your plan', noAds: 'Without ads', withAds: 'With ads',
      plan: 'Plan {p}', platOne: '1 platform',
      ratesLater: 'The rates will be shown on the quotation.', adNot: null,
      recommended: 'Recommended', piecesN: '{n} content pieces', platsN: '{n} platforms', adUpTo: 'Advertising budget up to RM\u00a0{b}',
      piecesHead: '{n} content pieces per month', piecesPick: '{n} content pieces per month. Please choose one combination.',
      kindS: { graphic: ['{n} graphic', '{n} graphics'], reel: ['{n} reel', '{n} reels'] }, mixSep: ', ',
      platHead1: 'Plan {p} includes 1 platform. Each additional platform is charged per month.',
      platHeadN: 'Plan {p} includes {n} platforms. Each additional platform is charged per month.',
      files: 'Additional files', filesOpt: 'Optional',
      filesNote: 'Working files and raw footage may be added now or requested at a later date. Each is charged per content piece.',
      delivered: 'Every content piece is delivered in high definition, formatted for the platform it is posted on.',
      termMin: 'The minimum commitment is 6 months.',
      planNone: 'Select a platform and a plan.',
      customT: 'Customise', customPlan: 'Customise Plan {p}',
      extra: 'Add content pieces per month to the plan', fewer: 'One fewer', more: 'One more',
      langs: 'Choose your languages', langsNote: 'Each content piece is published in one language. The monthly content pieces may be divided across the languages selected, for example 2 in English and 4 in Chinese, at no additional charge.',
      translate: 'Make every content piece bilingual', translateNote: 'Each additional language is charged per content piece.',
      budget: 'Advertising budget per month', budgetIn: 'Up to RM {b} (managed within the plan)', budgetUp: 'Up to RM {b}',
      budgetAbove: 'Above RM {b}', budgetOver: 'Advertising budget above {c} {b}', budgetReq: 'Advertising budget', term: 'Choose your commitment', months: '{n} months',
      once: 'Choose the content to produce', onceNote: 'One-time, charged per item',
      koc: 'KOC creators', kocNone: 'None', kocN: '{n} creators', kocCustom: 'Custom list (quoted on request)',
      kol: 'KOL campaign (quoted on request)', verify: 'Choose accounts to verify',
      detailsT: 'Your details', salutation: 'Salutation', name: 'Name', email: 'Work email', wa: 'WhatsApp number',
      waHint: 'Malaysian or Singaporean number', brand: 'Brand', industry: 'Industry', optional: 'Optional',
      commence: 'Planned commencement', choose: 'Select', starts3: [['1_3', 'Within 3 months'], ['3_6', '3 to 6 months'], ['6_plus', 'More than 6 months'], ['date', 'On a specific date']],
      startOn: 'Preferred start date',
      /* The intake (QUOTE INTAKE, 2026-11-27): what the team needs to quote
         a business on day one, and the fields the team asks for later. */
      ik: {
        secContact: 'Contact person', secBiz: 'Business registration', secBrand: 'Brand', secStart: 'Commencement',
        kind: 'Registering as', kinds: [['company', 'Company'], ['soleprop', 'Sole / Partnership']],
        brn: 'Business Registration No. (BRN)', legal: 'Registered Name', site: 'Website', noSite: 'No website',
        plat: 'Platform', plats: [['instagram', 'Instagram'], ['facebook', 'Facebook'], ['tiktok', 'TikTok'], ['xhs', 'rednote']],
        handle: 'Social media account', comments: 'Comments',
        say: { brn: 'Enter the 12-digit Business Registration No., such as 202301012345.',
          toSole: 'This number is registered to a sole proprietorship or partnership. Choose Sole / Partnership above.',
          toCo: 'This number is registered to a company. Choose Company above.', legal: 'Enter the Registered Name.',
          industry: 'Choose your industry.', site: 'Enter your website, or tick No website.', siteBad: 'Enter a web address.',
          handle: 'Enter a social media account.', handleBad: 'Enter the account name only, such as @' + AGENCY.trading_name.toLowerCase() + '.',
          comments: 'Enter no more than 1,000 characters.' },
        askT: 'Complete your details', askP: 'Please provide the following details by {d} to prepare your quotation.',
        askNote: 'Note from ' + AGENCY.trading_name, submit: 'Submit', rcvDetails: 'Details received', reqClosedT: 'This quotation request has been closed'
      },
      consent: 'I consent to ' + AGENCY.trading_name + ' keeping these details to prepare my quotation and to contact me about it.',
      fullBrand: 'Your quotation will be prepared for your brand. Incomplete requests may not receive a quotation.',
      freeMail: 'A work email address is recommended.',
      waBad: 'Enter a Malaysian or Singaporean WhatsApp number.',
      req: { name: 'Enter your name.', email: 'Enter a valid email address.', brand: 'Enter your brand name.', commence: 'Choose when you plan to commence.', startOn: 'Choose a preferred start date from today onwards.', consent: window.ADspaceWords.en.tickToContinue },
      make: 'View quotation',
      /* What changed since the page read the Rate Card (QUOTATION PREFLIGHT, 2026-11-25). */
      pf: {
        pfHead: 'Changes to your selection', pfEdit: 'Edit', pfCont: 'Continue', pfThing: 'A selected item',
        pfWait: 'Please review the changes above to continue.',
        pageOff: 'The quotation portal is temporarily unavailable. Please try again later.',
        cardMoved: 'The Rate Card was updated while this page was open. Your quotation will be prepared on the current Rate Card.',
        gonePlan: '{x} is no longer offered. Please choose another plan.',
        goneMix: 'The content option chosen for {x} is no longer offered. Please choose another option.',
        gonePlatform: '{x} is no longer offered. Please choose your platforms again.',
        goneExtra: 'Additional {x} is no longer offered. Please review your additional content pieces.',
        goneTranslate: 'Bilingual content is no longer offered. Please review your languages.',
        goneTerm: 'The {x}-month commitment is no longer offered. Please choose another commitment.',
        goneOnce: '{x} is no longer offered. Please review your selection.',
        goneCap: '{x} cannot exceed the content pieces chosen. Please choose the number of files again.',
        priceMoved: 'The price of these changes has been updated. Please review it before you request the changes.',
        choiceGone: 'A choice is no longer offered on this quotation. Please review your changes.'
      },
      quoteT: 'Your quotation', valid: 'Valid until {d}', expired: 'Expired on {d}', change: 'Change selection',
      line: 'Service', qty: 'Qty', rate: 'Rate ({c})', sub: 'Subtotal ({c})', onReq: 'Quoted on request',
      download: 'Download', pdfFail: 'The PDF could not be prepared. Please try again.', chat: 'Chat on WhatsApp',
      adHow: null,
      /* How ad spend works (2026-11-27): an explainer, no choice; the
         figures are Settings' (`ad_prepay_pct`, `ad_credit_fee_pct`). */
      ads: {
        lead: 'Choose one of the two options below to pay the advertising budget.', opt: 'Option {n}', or: 'or',
        /* The two options side by side (the user, 2026-11-27: either one, never both). */
        cmp: { paid: 'Paid to', paidA: 'Meta, charged to your credit card', paidB: AGENCY.trading_name, when: 'Payment timing', whenA: 'As the ads run', whenB: 'Before each month',
          fee: 'Agency Credit Term Fee', feeA: 'None', feeB: 'None when prepaid; {fee}% if billed with the invoice' },
        own: 'Your own ad account',
        ownPts: ['Meta charges the ads directly to your own credit card.',
          'The account is linked to the ' + AGENCY.trading_name + ' Meta business portfolio, so ' + AGENCY.trading_name + ' runs and manages the campaigns.'],
        pre: 'Prepaid through ' + AGENCY.trading_name,
        prePts: ['The first month\'s advertising budget is paid to ' + AGENCY.trading_name + ' before the ads start.',
          'Each following month is requested when about {pct}% of the current budget is spent.',
          'If payment is not received, the ads will be paused until payment is received.'],
        termH: 'Billed with the invoice',
        term: 'Where the advertising budget is billed with the invoice on the quotation\'s payment terms instead of prepaid, an Agency Credit Term Fee of {fee}% will be added to the advertising budget.',
        eg: 'For example, a budget of {c}\u00a0{b} carries a fee of {c}\u00a0{x}.', close: 'Close'
      },
      adLine: '{p} advertising budget', adsT: 'Advertising budget for the term',
      adsNote: 'The advertising budget is paid to the advertising platforms on the Client\'s behalf and is payable before the service commences.',
      payNote: 'Payment is due within {d} days of the invoice date.', payApprove: 'Payment is due within {d} days of the invoice date, subject to ' + AGENCY.trading_name + '\'s approval.',
      billManaged: 'The fees include the management of an advertising budget of up to {c}\u00a0{b} per month.',
      basis: 'Rates are based on the ' + AGENCY.trading_name + ' Rate Card v.{v}.',
      reviewT: 'Request received', reviewP: AGENCY.trading_name + ' will review your quotation and send it to you on WhatsApp by {d}.',
      rcvSent: 'Request sent', rcvSend: 'Quotation sent on WhatsApp',
      rcvBy: 'By {d}', rcvSign: 'Accept and sign on this page', rcvYours: 'Your request',
      repT: window.ADspaceWords.en.representative, repP: '{n} will be pleased to go through the quotation and finalise the details with you.',
      repChat: 'Chat with {n} on WhatsApp', revised: 'Revised on {d}. It replaces {r}.', offer: 'Letter of Offer issued',
      billT: 'Billing details', billP: 'Please provide your company\'s billing details. ' + AGENCY.trading_name + ' will then prepare your quotation for signing.', billBtn: 'Provide billing details',
      billSentT: 'Billing details received', billSentP: AGENCY.trading_name + ' will send your quotation for signing shortly.',
      letterP: 'Please review and sign the Letter of Offer, then return the signed copy to ' + AGENCY.trading_name + '.',
      signedT: 'Signed copy received', signedP: AGENCY.trading_name + ' will confirm your services shortly.', confirmed: 'Confirmed',
      welcomeT: 'Welcome to ' + AGENCY.trading_name, welcomeP: 'Your services, letters, reports and meetings are available in your Client Portal.',
      portalBtn: 'Sign in to your Client Portal', portalLater: 'Your account manager will set up your Client Portal access.',
      goneT: 'This quotation has expired', goneP: 'Request a new quotation at the current rates, or contact ' + AGENCY.trading_name + ' on WhatsApp.',
      goneAsked: 'Request received. ' + AGENCY.trading_name + ' will contact you shortly.',
      closed: 'Cancelled', closedT: 'This quotation has been cancelled',
      decline: 'Decline', declineT: 'Decline this quotation', declineWhy: 'Reason', declineHint: 'Optional',
      declined: 'Declined', declinedT: 'You have declined this quotation',
      withdrawn: 'Withdrawn', withdrawnP: 'This quotation was withdrawn with effect from {d}.',
      monthSub: 'Monthly subtotal', monthExcl: 'Monthly excl. SST',
      sst: 'SST {p}%', sstNone: 'SST not applicable', onceSub: 'One-time subtotal', onceTag: 'One-time', packH: 'Package', aoH: null, aoLead: null, aoTerm: null, aoExtra: null,
      monthlyNone: 'Monthly', firstNone: 'First month', oneOffNone: 'One-time total',
      monthly: 'Monthly incl. SST', firstExcl: 'First month excl. SST', first: 'First month incl. SST', oneOff: 'One-time incl. SST',
      newQuote: 'New quotation',
      chgT: 'Change your selection', chgReq: 'Request these changes', chgCancel: 'Cancel', chgTotal: 'Your quotation with these changes',
      chgNone: 'Change a choice to see the revised price.', chgPendT: 'Changes requested',
      chgPend: 'Your changes were requested on {d}. ' + AGENCY.trading_name + ' will send the revised quotation by {r}.', chgWithdraw: 'Withdraw request',
      perMonth: '{a} per month', plusMonth: '+{a} per month', incl: 'Included', each: '{a} each', eachMonth: '{a} each per month',
      err: {
        captcha: 'The security check did not complete. Please try again.', limit: 'You have reached the daily limit of five quotations. Please contact ' + AGENCY.trading_name + ' on WhatsApp.',
        'bad-whatsapp': 'Enter a Malaysian or Singaporean WhatsApp number.', 'bad-email': 'Enter a valid email address.',
        'bad-name': 'Enter your name only, without a web address.', 'bad-brand': 'Enter the brand name only, without a web address.', 'bad-commence': 'Choose when you plan to commence.', 'bad-start-date': 'Choose a preferred start date from today onwards.',
        'bad-industry': 'The industry you selected is no longer offered. Please select your industry again.',
        expired: 'This quotation has expired. Please request a new quotation.', 'not-proceeding': 'This quotation has been cancelled. Please request a new quotation.', 'not-sent': AGENCY.trading_name + ' will review this quotation and send it to you on WhatsApp.', unavailable: 'Online quotations are not available at the moment. Please contact ' + AGENCY.trading_name + ' on WhatsApp.',
        'not-found': 'This quotation could not be found. Please check the link, or request a new quotation.', 'bad-answer': 'Answer both questions to proceed.',
        signed: 'This quotation has already been signed. Please contact ' + AGENCY.trading_name + ' on WhatsApp.',
        empty: 'Select at least one service.', 'nothing-priced': 'KOL campaigns and custom creator lists are quoted on request. Please add a service with a listed rate, or contact ' + AGENCY.trading_name + ' on WhatsApp.', 'no-card': 'Online quotations are not available at the moment. Please contact ' + AGENCY.trading_name + ' on WhatsApp.',
        any: 'Not sent. Please try again.',
        changes: 'This quotation cannot be signed while your changes are being reviewed. Withdraw the request to sign it as it stands.',
        brands: 'Changes to this quotation cannot be requested online. Please contact ' + AGENCY.trading_name + ' on WhatsApp.',
        recent: 'Your changes were submitted recently. Please try again in a minute.',
        busy: 'Too many requests have been made on this quotation in the past hour. Please try again later, or contact ' + AGENCY.trading_name + ' on WhatsApp.'
      },
      /* Accepting the quotation on its link (2026-10-31). */
      sg: {
        title: 'Accept this quotation', line: 'Confirm your company details and sign here. No printing or scanning is needed.',
        steps: ['Company details', 'Review and sign', 'Confirm with the code'], go: 'Accept and sign',
        legal: 'Registered Company Name', reg: 'Business Registration No.', regOld: 'Old Registration No.', addr: 'Billing address',
        addrPh: 'Street, postcode, city, state', sst: 'SST Registration No.', tin: 'Tax Identification Number (TIN)', fin: 'Finance email', contactH: 'Billing contact',
        mobile: 'Mobile', email: 'Email', minTerm: 'Minimum term', termTotal: 'Total for the term', termTotalIncl: 'Total for the term incl. SST',
        signer: 'Full name', desig: 'Designation', sig: 'Signature', clear: 'Clear', typeIn: 'Type instead', drawIn: 'Draw instead',
        pad: 'Signature area', padHint: 'Sign here', typedPh: 'Type your full name',
        agree: 'I am authorised to sign on behalf of {c} and accept this quotation and the ' + AGENCY.trading_name + ' Service Terms.',
        terms: 'Read the Service Terms', sending: 'Sending…',
        codeL: 'Enter the code sent to {e}', digit: 'Digit {n} of 6', resendQ: 'Did not receive it?', resend: 'Send again',
        resendIn: 'Send again ({s}s)', resent: 'A new code has been sent.', finish: 'Accept and sign', finishing: 'Signing…',
        rec: 'The time, IP address and device will be recorded with your signature.',
        waitT: 'Accepted', waitP: 'Signed by {n} on {d} at {t} (GMT+8).',
        confT: 'Confirmed', confP: 'Confirmed by ' + AGENCY.trading_name + ' on {d}.', docId: 'Document ID {id}', sealDl: 'Download signed copy',
        doneP: AGENCY.trading_name + ' will review your details and confirm your start date within two working days.',
        say: {
          legal: 'Enter the Registered Company Name.', reg: 'Enter a valid Business Registration Number.', regOld: 'Enter a valid Old Registration Number.',
          tin: 'Enter a valid Tax Identification Number (TIN).', sst: 'Enter a valid SST Registration Number.', addr: 'Enter the full billing address.', email: 'Enter a valid email address.',
          sal: 'Select a salutation from the list.', name: 'Enter the name of the billing contact.', mobile: 'Enter a valid mobile number.',
          signer: 'Enter your full name.', desig: 'Enter your designation.', sig: 'Draw or type your signature.',
          agree: 'Tick the box to confirm you are authorised to sign.', code: 'Enter the six-digit code.',
          wrong: 'The code is incorrect. {n} attempts remaining.', wrong1: 'The code is incorrect. 1 attempt remaining.',
          locked: 'Too many incorrect attempts. Please send a new code.', expired: 'This code has expired. Please send a new code.',
          noCode: 'Please send a new code.', tooMany: 'Too many codes have been requested. Please try again in an hour.'
        }
      },
      lostT: 'Quotation not found', lostP: 'Please check the link, or request a new quotation.',
      offT: 'Unable to load', offP: 'Please refresh the page, or contact ' + AGENCY.trading_name + ' on WhatsApp.',
      plat: { meta: 'Facebook and Instagram', tiktok: 'TikTok', rednote: 'rednote', linkedin: 'LinkedIn' },
      lang3: { en: 'English', zh: '中文', ms: 'Bahasa Melayu' }
    },
    zh: {
      lang: 'EN',
      introT: '获取报价',
      introP: '选择品牌所需的服务，即可申请报价。',
      introSteps: ['选择所需服务。', '选择方案，并设定内容、语言及合约期。', '填写联系资料，' + AGENCY.trading_name + ' 审核后将通过 WhatsApp 发送报价。', '在此页面接受并签署报价，' + AGENCY.trading_name + ' 随后将与您确认开始日期。'],
      introNote: '整个流程约需三分钟。',
      needT: '请选择您的服务',
      need: {
        social: ['社交媒体管理', '每月内容制作与账号管理'],
        ads: ['广告投放', 'Meta 与 TikTok 广告，按月管理'],
        content: ['内容制作', '图文与视频，按件收费'],
        koc: ['KOC 或 KOL 合作', '为您的品牌邀约创作者'],
        verify: ['账号认证', 'Meta 认证与小红书专业号']
      },
      needNone: '请至少选择一项服务。',
      reqOnly: 'KOL 合作与自定创作者名单需另行报价。请加选有标价的服务，或通过 WhatsApp 联系 ' + AGENCY.trading_name + '。',
      planT: '平台与方案', platsH: '选择平台', planH: '选择方案', noAds: '不含广告', withAds: '含广告',
      plan: '方案 {p}', platOne: '1个平台',
      ratesLater: '价格将在报价单中列明。', adNot: '本报价不包括广告预算。',
      recommended: '推荐', piecesN: '{n}条内容', platsN: '{n}个平台', adUpTo: '广告预算最高 RM\u00a0{b}',
      piecesHead: '每月{n}条内容', piecesPick: '每月{n}条内容，请选择一种组合',
      kindS: { graphic: ['{n}条图文', '{n}条图文'], reel: ['{n}条短视频', '{n}条短视频'] }, mixSep: '、',
      platHead1: '方案 {p} 包含1个平台。每增加一个平台按月收费。',
      platHeadN: '方案 {p} 包含{n}个平台。每增加一个平台按月收费。',
      files: '附加文件', filesOpt: '可选',
      filesNote: '工作文件与原始素材可现在添加，也可日后另行申请。均按每件内容收费。',
      delivered: '所有内容均以高清交付，并按发布平台的格式制作。',
      termMin: '最低合约期为6个月。',
      planNone: '请选择平台与方案。',
      customT: '自定义', customPlan: '自定义方案 {p}',
      extra: '为方案增加每月内容', fewer: '减少一条', more: '增加一条',
      langs: '选择语言', langsNote: '每条内容使用一种语言。每月内容可分配至所选语言，例如2条英文、4条中文，不另收费。',
      translate: '每条内容均制作为双语', translateNote: '每增加一种语言，按每条内容收费。',
      budget: '每月广告预算', budgetIn: '最高 RM {b}（由方案代为管理）', budgetUp: '最高 RM {b}',
      budgetAbove: 'RM {b} 以上', budgetOver: '广告预算 {c} {b} 以上', budgetReq: '广告预算', term: '选择合约期', months: '{n}个月',
      once: '选择制作内容', onceNote: '一次性，按件收费',
      koc: 'KOC 创作者', kocNone: '不需要', kocN: '{n}位创作者', kocCustom: '自定名单（另行报价）',
      kol: 'KOL 合作（另行报价）', verify: '选择需认证的账号',
      detailsT: '您的资料', salutation: '称谓', name: '姓名', email: '工作邮箱', wa: 'WhatsApp 号码',
      waHint: '马来西亚或新加坡号码', brand: '品牌', industry: '行业', optional: '选填',
      commence: '计划开始时间', choose: '请选择', starts3: [['1_3', '三个月内'], ['3_6', '三至六个月'], ['6_plus', '六个月以后'], ['date', '指定日期']],
      startOn: '期望开始日期',
      ik: {
        secContact: '联系人', secBiz: '商业登记', secBrand: '品牌', secStart: '开始时间',
        kind: '登记类别', kinds: [['company', '公司'], ['soleprop', '独资 / 合伙']],
        brn: '商业注册号码（BRN）', legal: '注册名称', site: '网站', noSite: '没有网站',
        plat: '平台', plats: [['instagram', 'Instagram'], ['facebook', 'Facebook'], ['tiktok', 'TikTok'], ['xhs', '小红书']],
        handle: '社交媒体账号', comments: '备注',
        say: { brn: '请填写12位数的商业注册号码，例如202301012345。',
          toSole: '此号码属于独资或合伙企业，请在上方选择“独资 / 合伙”。',
          toCo: '此号码属于公司，请在上方选择“公司”。', legal: '请填写注册名称。',
          industry: '请选择行业。', site: '请填写网站，或勾选“没有网站”。', siteBad: '请填写有效的网址。',
          handle: '请填写社交媒体账号。', handleBad: '请只填写账号名称，例如 @' + AGENCY.trading_name.toLowerCase() + '。',
          comments: '请勿超过1,000个字符。' },
        askT: '补充您的资料', askP: '请于{d}前提供以下资料，以便拟定报价。',
        askNote: AGENCY.trading_name + ' 备注', submit: '提交', rcvDetails: '资料已收到', reqClosedT: '本报价申请已关闭'
      },
      consent: '本人同意 ' + AGENCY.trading_name + ' 保存以上资料，以便准备报价并就此与本人联系。',
      fullBrand: '报价将按您的品牌拟定。资料不完整的申请可能无法获得报价。',
      freeMail: '建议使用工作邮箱。',
      waBad: '请填写马来西亚或新加坡的 WhatsApp 号码。',
      req: { name: '请填写姓名。', email: '请填写有效的邮箱地址。', brand: '请填写品牌。', commence: '请选择计划开始时间。', startOn: '请选择今天或之后的期望开始日期。', consent: window.ADspaceWords.zh.tickToContinue },
      make: '查看报价',
      pf: {
        pfHead: '您的选择有变动', pfEdit: '修改', pfCont: '继续', pfThing: '所选项目',
        pfWait: '请先查看以上变动，再继续。',
        pageOff: '报价门户暂时无法使用，请稍后再试。',
        cardMoved: '本页打开期间，价目表已更新。您的报价将按最新价目表编制。',
        gonePlan: '{x}已不再提供，请选择其他方案。',
        goneMix: '{x}所选的内容组合已不再提供，请选择其他组合。',
        gonePlatform: '{x}已不再提供，请重新选择平台。',
        goneExtra: '额外的{x}已不再提供，请检查额外内容数量。',
        goneTranslate: '双语内容已不再提供，请检查语言选择。',
        goneTerm: '{x}个月的合约期已不再提供，请选择其他合约期。',
        goneOnce: '{x}已不再提供，请检查您的选择。',
        goneCap: '{x}的数量超过所选的内容数量，请重新选择文件数量。',
        priceMoved: '这些修改的价格已更新，请先查看再提交修改请求。',
        choiceGone: '本报价已不再提供您所选的某项内容，请检查您的修改。'
      },
      quoteT: '您的报价', valid: '有效期至 {d}', expired: '已于 {d} 过期', change: '修改选择',
      line: '服务', qty: '数量', rate: '单价（{c}）', sub: '小计（{c}）', onReq: '另行报价',
      download: '下载', pdfFail: 'PDF 未能生成，请重试。', chat: 'WhatsApp 咨询',
      adHow: '广告费用如何支付',
      ads: {
        lead: '请从以下两种方式中选择一种支付广告预算。', opt: '方式 {n}', or: '或',
        cmp: { paid: '付款对象', paidA: 'Meta（您的信用卡）', paidB: AGENCY.trading_name, when: '付款时间', whenA: '广告投放时扣款', whenB: '每月投放前',
          fee: '账期服务费', feeA: '无', feeB: '预付则无；随发票结算加收{fee}%' },
        own: '您自己的广告账户',
        ownPts: ['Meta 直接从您自己的信用卡扣除广告费用。',
          '该账户将关联至 ' + AGENCY.trading_name + ' 的 Meta 商务资产组合，由 ' + AGENCY.trading_name + ' 投放并管理广告活动。'],
        pre: '通过 ' + AGENCY.trading_name + ' 预付',
        prePts: ['首月广告预算须于广告开始投放前支付予 ' + AGENCY.trading_name + '。',
          '当月预算消耗约{pct}%时，' + AGENCY.trading_name + ' 将请款下月预算。',
          '如未收到款项，广告将暂停投放，直至收款为止。'],
        termH: '随发票结算',
        term: '如广告预算按报价单的付款期限随发票结算而非预付，将按广告预算另加收{fee}%的账期服务费（Agency Credit Term Fee）。',
        eg: '例如：广告预算 {c}\u00a0{b}，账期服务费为 {c}\u00a0{x}。', close: '关闭'
      },
      adLine: '{p} 广告预算', adsT: '合约期广告预算',
      adsNote: '广告预算由 ' + AGENCY.trading_name + ' 代客户支付予广告平台，须于服务开始前支付。',
      payNote: '付款期限为发票日期起{d}天内。', payApprove: '付款期限为发票日期起{d}天内，须经 ' + AGENCY.trading_name + ' 批准。',
      billManaged: '费用包括代为管理每月最高 {c}\u00a0{b} 的广告预算。',
      basis: '价格依据 ' + AGENCY.trading_name + ' 价目表 v.{v}。',
      reviewT: '已收到您的请求', reviewP: AGENCY.trading_name + ' 将审核您的报价，并于 {d} 前通过 WhatsApp 发送给您。',
      rcvSent: '已提交请求', rcvSend: '通过 WhatsApp 发送报价',
      rcvBy: '{d}前', rcvSign: '在此页面接受并签署', rcvYours: '您的请求',
      repT: window.ADspaceWords.zh.representative, repP: '{n} 将与您详细说明报价并确认细节。',
      repChat: '通过 WhatsApp 联系 {n}', revised: '已于 {d} 修订，取代 {r}。', offer: '已发出服务确认函',
      billT: '账单资料', billP: '请提供贵公司的账单资料，以便 ' + AGENCY.trading_name + ' 准备报价单供您签署。', billBtn: '填写账单资料',
      billSentT: '已收到账单资料', billSentP: AGENCY.trading_name + ' 将尽快向您发送报价单供您签署。',
      letterP: '请审阅并签署服务确认函，然后将签署副本交回 ' + AGENCY.trading_name + '。',
      signedT: '已收到签署副本', signedP: AGENCY.trading_name + ' 将尽快确认您的服务。', confirmed: '已确认',
      welcomeT: '欢迎加入 ' + AGENCY.trading_name, welcomeP: '您的服务、函件、报告及会议均可在客户平台查看。',
      portalBtn: '登录客户平台', portalLater: '您的客户经理将为您开通客户平台。',
      goneT: '本报价已过期', goneP: '您可按最新价格申请新的报价，或通过 WhatsApp 咨询 ' + AGENCY.trading_name + '。',
      goneAsked: '已收到您的请求，' + AGENCY.trading_name + ' 将尽快与您联系。',
      closed: '已取消', closedT: '本报价已取消',
      decline: '拒绝', declineT: '拒绝此报价', declineWhy: '原因', declineHint: '选填',
      declined: '已拒绝', declinedT: '您已拒绝此报价',
      withdrawn: '已撤回', withdrawnP: '此报价已于{d}起撤回。',
      monthSub: '每月小计', monthExcl: '每月（未含 SST）',
      sst: 'SST {p}%', sstNone: '不适用 SST', onceSub: '一次性小计', onceTag: '一次性',
      packH: '套餐', aoH: '附加服务费率', aoLead: '以下服务可于合约期内任何月份另行申请，费率如下。所有费率均未含 SST。',
      aoTerm: '附加服务不包括在上述费用内。每项附加服务须于开始前以书面确认，并于确认后次月开具发票。', aoExtra: '追加内容', pack: { not: function (list) { return '本套餐不包括' + list.map(function (x) { return String(x || '').trim().replace(/[.;。；]+$/, ''); }).join('、') + '。'; } },
      monthlyNone: '每月', firstNone: '首月', oneOffNone: '一次性合计',
      monthly: '每月（含 SST）', firstExcl: '首月（未含 SST）', first: '首月（含 SST）', oneOff: '一次性（含 SST）',
      ptMonths: '{n}个月总额（含 SST）', ptMonthsNone: '{n}个月总额', ptAll: '总额（含 SST）', ptAllNone: '总额', ptNote: '{n}个月月费加一次性费用，不含广告预算。',
      newQuote: '申请新报价',
      chgT: '修改您的选择', chgReq: '提交修改请求', chgCancel: '取消', chgTotal: '修改后的报价',
      chgNone: '修改任何选项即可查看调整后的价格。', chgPendT: '已提交修改请求',
      chgPend: '您已于{d}提交修改请求，' + AGENCY.trading_name + ' 将于{r}前发送修订后的报价。', chgWithdraw: '撤回请求',
      perMonth: '每月 {a}', plusMonth: '每月另加 {a}', incl: '已包含', each: '每项 {a}', eachMonth: '每项每月 {a}',
      err: {
        captcha: '安全验证未完成，请重试。', limit: '此联系方式今日已获取五份报价，请通过 WhatsApp 联系 ' + AGENCY.trading_name + '。',
        'bad-whatsapp': '请填写马来西亚或新加坡的 WhatsApp 号码。', 'bad-email': '请填写有效的邮箱地址。',
        'bad-name': '请只填写姓名，不要包含网址。', 'bad-brand': '请只填写品牌名称，不要包含网址。', 'bad-commence': '请选择计划开始时间。', 'bad-start-date': '请选择今天或之后的期望开始日期。',
        'bad-industry': '您选择的行业已不再提供，请重新选择行业。',
        expired: '本报价已过期，请申请新的报价。', 'not-proceeding': '本报价已取消，请申请新的报价。', 'not-sent': AGENCY.trading_name + ' 将审核本报价，并通过 WhatsApp 发送给您。', unavailable: '目前暂不提供在线报价，请通过 WhatsApp 联系 ' + AGENCY.trading_name + '。',
        'not-found': '找不到此报价，请检查链接，或申请新的报价。', 'bad-answer': '请回答以上两个问题。',
        signed: '本报价已签署，请通过 WhatsApp 联系 ' + AGENCY.trading_name + '。',
        empty: '请至少选择一项服务。', 'nothing-priced': 'KOL 合作与自定创作者名单需另行报价。请加选有标价的服务，或通过 WhatsApp 联系 ' + AGENCY.trading_name + '。', 'no-card': '目前暂不提供在线报价，请通过 WhatsApp 联系 ' + AGENCY.trading_name + '。',
        any: '未能提交，请重试。',
        changes: '您的修改请求正在审核中，暂时无法签署此报价。如需按原报价签署，请先撤回请求。',
        brands: '此报价无法在线提交修改，请通过 WhatsApp 联系 ' + AGENCY.trading_name + '。',
        recent: '您的修改请求刚已提交，请一分钟后再试。',
        busy: '过去一小时内此报价的请求次数过多，请稍后再试，或通过 WhatsApp 联系 ' + AGENCY.trading_name + '。'
      },
      sg: {
        title: '接受报价', line: '在此确认公司资料并签署，无需打印或扫描。',
        steps: ['公司资料', '审阅并签署', '验证码确认'], go: '接受并签署',
        legal: '公司注册名称', reg: '商业注册号码', regOld: '旧注册号码', addr: '账单地址',
        addrPh: '街道、邮编、城市、州属', sst: 'SST 注册号码', tin: '税务识别号码（TIN）', fin: '财务邮箱', contactH: '账单联系人',
        mobile: '手机号码', email: '邮箱', minTerm: '最低合约期', termTotal: '合约期总额', termTotalIncl: '合约期总额（含 SST）',
        signer: '全名', desig: '职位', sig: '签名', clear: '清除', typeIn: '改为输入', drawIn: '改为手写',
        pad: '签名区', padHint: '请在此签名', typedPh: '请输入您的全名',
        agree: '本人获授权代表 {c} 签署，并接受本报价及 ' + AGENCY.trading_name + ' 服务条款。',
        terms: '阅读服务条款', sending: '发送中…',
        codeL: '请输入发送至 {e} 的验证码', digit: '第{n}位，共6位', resendQ: '没有收到？', resend: '重新发送',
        resendIn: '重新发送（{s}秒）', resent: '新的验证码已发送。', finish: '接受并签署', finishing: '签署中…',
        rec: '签署时间、IP 地址及设备将与您的签名一并记录。',
        waitT: '已接受', waitP: '由{n}于{d} {t}（GMT+8）签署。',
        confT: '已确认', confP: AGENCY.trading_name + ' 已于{d}确认。', docId: '文件识别码 {id}', sealDl: '下载已签署副本',
        doneP: AGENCY.trading_name + ' 将审核您的资料，并于2个工作日内确认开始日期。',
        say: {
          legal: '请填写公司注册名称。', reg: '请填写有效的商业注册号码。', regOld: '请填写有效的旧注册号码。',
          tin: '请填写有效的税务识别号码（TIN）。', sst: '请填写有效的 SST 注册号码。', addr: '请填写完整的账单地址。', email: '请填写有效的邮箱地址。',
          sal: '请从列表中选择称谓。', name: '请填写账单联系人姓名。', mobile: '请填写有效的手机号码。',
          signer: '请填写您的全名。', desig: '请填写您的职位。', sig: '请手写或输入您的签名。',
          agree: '请勾选，确认您获授权签署。', code: '请输入六位数验证码。',
          wrong: '验证码不正确，还可尝试{n}次。', wrong1: '验证码不正确，还可尝试1次。',
          locked: '错误次数过多，请重新发送验证码。', expired: '验证码已过期，请重新发送。',
          noCode: '请重新发送验证码。', tooMany: '请求验证码次数过多，请一小时后再试。'
        }
      },
      lostT: '找不到报价', lostP: '请检查链接，或申请新的报价。',
      offT: '无法加载', offP: '请刷新页面，或通过 WhatsApp 联系 ' + AGENCY.trading_name + '。',
      plat: { meta: 'Facebook 与 Instagram', tiktok: 'TikTok', rednote: '小红书', linkedin: 'LinkedIn' },
      lang3: { en: 'English', zh: '中文', ms: '马来文' }
    }
  };  /* A form in steps says its step, Back, Continue, Start and What to expect
     as every form in steps does (js/words.js, 2026-11-25). */
  ['en', 'zh'].forEach(function (l) {
    var sh = window.ADspaceWords[l];
    WORDS[l].step = sh.stepOf; WORDS[l].cont = sh.stepNext; WORDS[l].back = sh.stepBack;
    WORDS[l].start = sh.stepStart; WORDS[l].introH = sh.stepExpect;
    WORDS[l].rcvReview = sh.rcvByAdspace; WORDS[l].rcvNow = sh.rcvNow;
  });

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
  /* The industries the website offers, from the list kept in Settings
     (`industries_list`, 2026-11-04): each its name and Chinese name, read
     once a visit beside the catalogue. A failed read offers none; the field
     is optional. */
  var INDUSTRIES = [];
  var FREE = /@(gmail|googlemail|yahoo|ymail|hotmail|outlook|live|msn|icloud|me|aol|proton|protonmail|qq|163|126)\./i;
  /* The commitments /quote/ offers (6, 12 and 24 months, the user,
     2026-11-24; 3 and 18 are Build quote's), as the catalogue names them. */
  var TERMS = [6, 12, 24];

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
  /* `named`: a day the reader waits on carries its weekday (js/clock.js). */
  function day(iso, long, named) {
    var C = window.ADspaceClock;
    if (!iso) return '';
    if (long && lang !== 'zh') {
      var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
      var M = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      return m ? Number(m[3]) + ' ' + M[Number(m[2]) - 1] + ' ' + m[1] : iso;
    }
    return C ? C.date(String(iso).slice(0, 10), { zh: lang === 'zh', named: named }) : iso;
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
      plan: null, mix: 0, extra: {}, langs: ['en'], translate: false, budget: null, term: 12, once: {}, files: {}, koc: '', kol: false, verify: [],
      contact: blankContact(), step: 'intro', idem: null };
  }
  function blankContact() {
    return { salutation: '', name: '', email: '', whatsapp: '', brand: '', industry: '', commence: '', commence_on: '', consent: false,
      kind: 'company', brn: '', legal: '', website: '', no_site: false, platform: 'instagram', handle: '', comments: '' };
  }
  var S = blank();
  try { var kept = JSON.parse(sessionStorage.getItem(KEEP) || 'null'); if (kept && kept.need) S = Object.assign(S, kept); } catch (e) {}
  if (!S.files) S.files = {};
  function keep() { try { sessionStorage.setItem(KEEP, JSON.stringify(S)); } catch (e) {} }

  var CAT = null, Q = null;
  /* The changes a preflight reported, each kept until its step is visited
     (`items`), and the selection it last checked (`key`). Never kept in the tab. */
  var PF = { items: [], key: null };
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
  /* One-time contents: with a plan, only those its additional contents do not
     already offer, so a format is never asked twice (the user, 2026-10-14). */
  function onceList() {
    var p = S.need.social ? planOf() : null;
    var monthlyOnes = p ? extrasOf(p).map(function (c) { return c.slug; }) : [];
    return CAT.contents.filter(function (c) { return monthlyOnes.indexOf(c.slug) < 0; }).sort(byKind);
  }

  /* The files a content piece is released with (Working files, Raw
     footage; the user, 2026-11-24): asked wherever content is made. */
  function filesAsked() { return Boolean((S.need.social || S.need.content) && CAT && (CAT.files || []).length); }
  /* The files held to what the selection makes (QUOTE FILES CAPPED, the
     user, 2026-11-25): Working files at most its graphics, Raw footage at
     most its reels, counted as quote_files_cap counts them (the plan's
     content option, its additional content pieces, the one-time content),
     each piece by the catalogue's `piece` for its kind, never its name. A
     file covering neither covers every piece. A catalogue naming no piece
     caps nothing; the database holds the files either way. */
  var STEP_MAX = 30;
  function piecesOf(plan, mix, extra, once) {
    var C = (CAT && CAT.contents) || [], n = { graphic: 0, reel: 0 };
    if (!C.some(function (c) { return c.piece; })) return null;
    var add = function (c, q) { if (c && n[c.piece] != null && Number(q) > 0) n[c.piece] += Number(q); };
    var bySlug = function (sl) { return C.filter(function (c) { return c.slug === sl; })[0]; };
    if (plan) {
      var ms = plan.mix || [], m = ms[mix < ms.length ? mix : 0] || {};
      Object.keys(m).forEach(function (k) { add(C.filter(function (c) { return c.kind === k; })[0], m[k]); });
      Object.keys(extra || {}).forEach(function (sl) { add(bySlug(sl), extra[sl]); });
    }
    (once || []).forEach(function (o) { add(bySlug(o.slug), o.qty); });
    return n;
  }
  function fileCap(x, n) { return !n ? STEP_MAX : Math.min(STEP_MAX, x.covers ? n[x.covers] || 0 : n.graphic + n.reel); }
  function stepPieces() {
    var p = S.need.social ? planOf() : null;
    return piecesOf(p, S.mix, S.extra, S.need.content ? onceList().map(function (c) { return { slug: c.slug, qty: S.once[c.slug] || 0 }; }) : []);
  }
  /* A count above its cap comes down to it; a file the selection makes no piece for leaves. */
  function filesFit() {
    if (!CAT) return;
    var n = stepPieces();
    (CAT.files || []).forEach(function (x) {
      var lim = fileCap(x, n);
      if ((S.files[x.slug] || 0) > lim) { if (lim > 0) S.files[x.slug] = lim; else delete S.files[x.slug]; }
    });
  }
  /* Choose the files to receive: offered only for what the selection makes. */
  function filesHtml() {
    if (!filesAsked()) return '';
    filesFit();
    var n = stepPieces(), list = CAT.files.filter(function (x) { return fileCap(x, n) > 0; });
    if (!list.length) return '';
    return sec(t().files, '<p class="qs-note">' + noteH(t().filesNote) + '</p>' + list.map(function (x) {
      return stepper('files', x.slug, (lang === 'zh' && FILE_ZH[x.name]) || x.name, S.files[x.slug] || 0, '', fileCap(x, n));
    }).join(''), null, t().filesOpt);
  }
  function filesRepaint() { var b = $('qsFilesBox'); if (b) b.innerHTML = filesHtml(); }
  /* A verification for the platforms chosen, where platforms are chosen;
     every one where verification alone is asked. */
  function verifyList() {
    var picked = S.need.social ? S.platforms : null;
    return (CAT.verify || []).filter(function (v) { return !picked || !v.platform || picked.indexOf(v.platform) >= 0; });
  }
  function selection() {
    var p = S.need.social ? planOf() : null, once = [];
    var sel = { term: monthly() ? S.term : 1 };
    if (p) {
      sel.plan = p.slug;
      /* Which of the plan's content options (1 graphic and 3 reels, or 4
         reels), as Build quote asks it; a string, as the website keeps it. */
      if ((p.mix || []).length > 1) sel.mix = String(S.mix < p.mix.length ? S.mix : 0);
      sel.platforms = S.platforms.slice();
      var ex = {};
      Object.keys(S.extra).forEach(function (k) { if (S.extra[k] > 0) ex[k] = S.extra[k]; });
      sel.extra = ex;
      sel.langs = S.langs.slice();
      /* Every content piece bilingual: Build quote's own key, priced there as Translation. */
      if (S.translate && S.langs.length > 1 && CAT.translation) sel.translate = true;
    }
    if (adsAsked()) sel.budget = S.budget == null ? (p && p.ad_budget ? 0 : (CAT.budgets[0] || 0)) : S.budget;
    if (S.need.content) onceList().forEach(function (c) { if (S.once[c.slug] > 0) once.push({ slug: c.slug, qty: S.once[c.slug] }); });
    if (S.need.koc && S.koc) once.push({ slug: S.koc, qty: 1 });
    if (S.need.koc && S.kol && CAT.kol) once.push({ slug: CAT.kol, qty: 1 });
    if (S.need.verify) verifyList().forEach(function (v) { if (S.verify.indexOf(v.slug) >= 0) once.push({ slug: v.slug, qty: 1 }); });
    if (filesAsked()) { filesFit(); (CAT.files || []).forEach(function (x) { if (S.files[x.slug] > 0) once.push({ slug: x.slug, qty: S.files[x.slug] }); }); }
    if (once.length) sel.once = once;
    return sel;
  }

  // ---- Drawing ----------------------------------------------------------------
  function frame(body, foot) {
    var a = steps(), i = a.indexOf(S.step) + 1;
    return '<div class="qs-step qs-wide" data-shown>' + window.ADspaceIcons.stepTrack(i, a.length + 1, f(t().step, { n: i, m: a.length + 1 })) + body +
      '<p class="msg" id="qsMsg" role="status"></p></div>' +
      '<div class="qs-foot qs-wide">' + foot + '</div>';
  }
  function navFoot(first) {
    return (first ? '' : '<button class="btn qs-back" type="button" data-a="back">' + esc(t().back) + '</button>') +
      '<button class="btn btn-primary" type="button" data-a="next">' + esc(S.step === 'details' ? t().make : t().cont) + '</button>';
  }
  // The choice's mark at the card's right edge: an empty ring, the ink disc with its tick once chosen.
  var MARK = '<span class="qs-mark" aria-hidden="true">' + window.ADspaceIcons.glyph('check', '', 'width="12" height="12"') + '</span>';
  function pick(type, name, value, on, title, sub) {
    return '<label class="qs-pick' + (on ? ' is-on' : '') + '"><input type="' + type + '" name="' + esc(name) + '" value="' + esc(value) + '"' +
      (on ? ' checked' : '') + '><span class="qs-text"><b>' + esc(title) + '</b>' + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span>' + MARK + '</label>';
  }
  function chip(name, value, on, label, lead) {
    return '<label class="qs-chip' + (on ? ' is-on' : '') + '"><input type="checkbox" name="' + esc(name) + '" value="' + esc(value) + '"' +
      (on ? ' checked' : '') + '><span class="qs-text">' + (lead ? '<span class="qs-lead-mark">' + lead + '</span>' : '') + esc(label) + '</span>' + MARK + '</label>';
  }
  /* `max`: the most it may count (the files a selection makes); + stops there. */
  function stepper(group, slug, label, n, sub, max) {
    var top = max == null ? STEP_MAX : max;
    return '<div class="qs-stepper"><span>' + esc(label) + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</span><span class="qs-count">' +
      '<button class="btn btn-sm qs-pm" type="button" data-step="-1" data-group="' + group + '" data-slug="' + esc(slug) + '" aria-label="' + esc(t().fewer + ': ' + label) + '"' + (n ? '' : ' disabled') + '>−</button>' +
      '<b aria-live="polite">' + n + '</b>' +
      '<button class="btn btn-sm qs-pm" type="button" data-step="1" data-group="' + group + '" data-slug="' + esc(slug) + '" data-max="' + top + '" aria-label="' + esc(t().more + ': ' + label) + '"' + (n >= top ? ' disabled' : '') + '>+</button></span></div>';
  }
  function seg(id, label, options, value, quiet) {
    return '<div class="field">' + (quiet ? '' : '<span class="field-label" id="' + id + 'L">' + esc(label) + '</span>') +
      '<select class="select" id="' + id + '" data-seg data-seg-value ' + (quiet ? 'aria-label="' + esc(label) + '"' : 'aria-labelledby="' + id + 'L"') + '>' +
      options.map(function (o) { return '<option value="' + esc(o[0]) + '"' + (String(o[0]) === String(value) ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') +
      '</select></div>';
  }
  // A category of choices: its heading over its items, set apart from the next by a hairline.
  /* `tag`: a grey fact beside the heading (Optional). */
  function sec(head, body, forId, tag) {
    return '<section class="qs-sec">' + (forId ? '<label class="qs-sec-h" for="' + forId + '">' : '<h2 class="qs-sec-h">') + esc(head) +
      (tag ? ' <span class="chip">' + esc(tag) + '</span>' : '') + (forId ? '</label>' : '</h2>') + body + '</section>';
  }
  function contentName(c) { return lang === 'zh' && ZH_KIND[c.kind] ? ZH_KIND[c.kind] : EN_KIND[c.kind] || c.name; }
  // The opening page: what the quotation is for, what is asked and what follows (the user, 2026-10-14).
  /* The opening page (the boards QuoteIntroPhone and QuoteIntroDesk,
     2026-11-25): What to expect as cards, each its glyph in a white disc
     with its number on an ink badge, then the time with the clock. The
     services are chosen on the Need step alone, as its tiles (2026-11-25:
     tiles drawn here read as choices and pressed as nothing). */
  var NEED_GLYPH = { 'social': 'plancontent', 'ads': 'planads', 'content': 'picture', 'koc': 'people', 'verify': 'verified' };
  var STEP_GLYPH = ['grid', 'sliders', 'bubble', 'pen'];
  /* The services offered, one list for the opening page's tiles and the
     Need step's cards: what the catalogue cannot quote is not offered. */
  function needKeys() {
    return ['social', 'ads', 'content', 'koc', 'verify'].filter(function (k) {
      return (k !== 'koc' || CAT.koc.length || CAT.kol) && (k !== 'verify' || CAT.verify.length);
    });
  }
  function paintIntro() {
    return '<div class="qs-step qs-intro" data-shown><div class="qs-top"><h1 class="qs-title">' + esc(t().introT) + '</h1><p class="qs-lead">' + esc(t().introP) + '</p></div>' +

      '<section class="qs-sec"><h2 class="qs-sec-h">' + esc(t().introH) + '</h2>' +
        window.ADspaceIcons.stepCards(t().introSteps.map(function (x, i) { return { glyph: STEP_GLYPH[i], line: x }; })) + '</section>' +
      '<p class="qs-note qs-time">' + ic('clock', 'qs-g') + esc(t().introNote) + '</p></div>' +
      '<div class="qs-foot"><a class="btn" href="' + esc(waLink(null)) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(t().chat) + '</a>' +
      '<button class="btn btn-primary" type="button" data-a="start">' + esc(t().start) + '</button></div>';
  }

  function paintNeed() {
    var N = t().need;
    /* The services as tiles (the user, 2026-11-25: "the five boxes replace
       here"): each a toggle on S.need, its glyph in a disc over its name and
       its line, chosen ringed in ink with the several-of mark filled at its
       corner. */
    return frame('<h1 class="qs-title" id="qsNeedT">' + esc(t().needT) + '</h1><div class="qs-svcs" role="group" aria-labelledby="qsNeedT">' +
      needKeys().map(function (k) {
        return '<button class="qs-svc' + (S.need[k] ? ' is-on' : '') + '" type="button" data-a="svc" data-k="' + k + '" aria-pressed="' + Boolean(S.need[k]) + '">' +
          '<span class="qs-disc">' + ic(NEED_GLYPH[k], 'qs-g') + '</span><b>' + esc(N[k][0]) + '</b><small>' + esc(N[k][1]) + '</small>' + MARK + '</button>';
      }).join('') + '</div>', navFoot());
  }

  function ic(name, cls) { return window.ADspaceIcons ? window.ADspaceIcons.svg(name, cls) : ''; }

  /* HOW AD SPEND WORKS (2026-11-27, the user): the advertising budget is
     not included in a quotation, and a press under that line opens the two
     ways it is paid, an explainer with no choice and no price. The English
     line and the button's words are ADspaceWords.line's (the PDF says the
     line too). The figures are Settings' (`ad_prepay_pct`,
     `ad_credit_fee_pct`, js/money.js), as they stood on a sent
     quotation's day, else today. */
  function adw(k) { return t()[k] || window.ADspaceWords.line[{ adNot: 'adNotIncluded', adHow: 'adHow' }[k]]; }
  function adHowBtn() {
    return '<button class="linkbtn qs-adhow" type="button" data-a="adhow" aria-haspopup="dialog">' + esc(adw('adHow')) + ic('go', 'ovgo-chev') + '</button>';
  }
  /* The user's own example (2026-11-27): a budget of 6,000 and its fee. */
  var AD_EG = 6000;
  function pctWord(v) { return String(Math.round(Number(v) * 100) / 100); }
  function adSheetFill() {
    var w = t().ads, at = Q && Q.issued_at ? Q.issued_at : undefined, c = Q ? qc() : 'RM';
    var pct = MON.setting('ad_prepay_pct', at), fee = MON.setting('ad_credit_fee_pct', at);
    var x = Math.round(AD_EG * Number(fee)) / 100;
    var pts = function (list) { return '<ul class="adway-pts">' + list.map(function (p) { return '<li>' + esc(f(p, { pct: pctWord(pct) })) + '</li>'; }).join('') + '</ul>'; };
    $('adHeading').textContent = adw('adHow');
    $('adClose').setAttribute('aria-label', w.close);
    $('adClose').innerHTML = ic('close');
    var C = w.cmp, row = function (h, a, b) { return '<tr><th scope="row">' + esc(h) + '</th><td>' + esc(a) + '</td><td>' + esc(b) + '</td></tr>'; };
    /* Two options, either one: each numbered, an "or" between, then the two
       compared row by row (the user, 2026-11-27). */
    $('adBody').innerHTML = '<p class="adways-lead">' + esc(w.lead) + '</p><div class="stepcards adways">' +
      '<div class="stepcard is-rec"><span class="qs-rec">' + esc(t().recommended) + '</span><span class="stepcard-mark">' + ic('adaccount') + '</span><div class="adway-text">' +
        '<span class="adway-n">' + esc(f(w.opt, { n: 1 })) + '</span>' +
        '<p class="adway-name"><b>' + esc(w.own) + '</b></p>' + pts(w.ownPts) + '</div></div>' +
      '<p class="adways-or" aria-hidden="true"><span>' + esc(w.or) + '</span></p>' +
      '<div class="stepcard"><span class="stepcard-mark">' + ic('prepaid') + '</span><div class="adway-text">' +
        '<span class="adway-n">' + esc(f(w.opt, { n: 2 })) + '</span>' +
        '<p class="adway-name"><b>' + esc(w.pre) + '</b></p>' + pts(w.prePts) +
        '<div class="adway-sub"><h4>' + esc(w.termH) + '</h4><p>' + esc(f(w.term, { fee: pctWord(fee) })) + '</p>' +
          '<p>' + esc(f(w.eg, { c: c, b: n0(AD_EG), x: x % 1 ? n2(x) : n0(x) })) + '</p></div></div></div></div>' +
      '<div class="adcmp-wrap"><table class="adcmp"><thead><tr><td></td><th scope="col">' + esc(f(w.opt, { n: 1 })) + '</th><th scope="col">' + esc(f(w.opt, { n: 2 })) + '</th></tr></thead><tbody>' +
        row(C.paid, C.paidA, C.paidB) + row(C.when, C.whenA, C.whenB) + row(C.fee, C.feeA, f(C.feeB, { fee: pctWord(fee) })) + '</tbody></table></div>';
  }
  /* js/sheet.js is fetched on the first press, from the address the page
     names on the sheet (its stamp kept with the page's), never on load. */
  function adSheet(opener) {
    var box = $('adSheet'), src = box && box.getAttribute('data-script');
    if (!box) return;
    if (window.ADspaceSheet) { adShow(box, opener); return; }
    if (!src || adSheet.asked) return;
    adSheet.asked = true;
    var tag = document.createElement('script');
    tag.src = src;
    tag.onload = function () { if (window.ADspaceSheet) adShow(box, opener); };
    tag.onerror = function () { adSheet.asked = false; tag.remove(); };
    document.head.appendChild(tag);
  }
  function adShow(box, opener) {
    adSheetFill();
    window.ADspaceSheet.show(box, { opener: opener });
    /* The figures read afresh, the sheet filled again once they answer. */
    if (MON.load) MON.load().then(function () { if (window.ADspaceSheet.isOpen(box)) adSheetFill(); }).catch(function () {});
  }
  if ($('adClose')) $('adClose').addEventListener('click', function () { if (window.ADspaceSheet) window.ADspaceSheet.close(); });
  /* A plan's content as the boards write it: "3 graphics, 4 reels". */
  function mixShort(m) {
    var K = t().kindS;
    return ['graphic', 'reel'].concat(Object.keys(m).filter(function (k) { return k !== 'graphic' && k !== 'reel'; }))
      .filter(function (k) { return m[k]; }).map(function (k) {
        var w = K[k] || ['{n} ' + k, '{n} ' + k];
        return f(w[m[k] === 1 ? 0 : 1], { n: m[k] });
      }).join(t().mixSep);
  }
  /* The plans as cards (the boards, 2026-11-25): its mark on top, the name,
     then a line a fact with its glyph; the middle of the three is
     Recommended and wider (1.4 to 1), first and the row's width on a phone,
     its tag on the mark's row at the right edge, never a row of its own. */
  function planCard(p, i, n) {
    var w = t(), on = S.plan === p.slug, feat = n === 3 && i === 1;
    return '<label class="qs-plan' + (on ? ' is-on' : '') + (feat ? ' is-feat' : '') + '"><input type="radio" name="plan" value="' + esc(p.slug) + '"' + (on ? ' checked' : '') + '>' +
      '<span class="qs-plan-top">' + ic(p.ads ? 'planads' : 'plancontent', 'qs-plan-ic') + (feat ? '<span class="qs-rec">' + esc(w.recommended) + '</span>' : '') + '</span>' +
      '<b>' + esc(f(w.plan, { p: p.plan })) + '</b>' +
      '<span class="qs-pl">' + ic('pieces') + esc(f(w.piecesN, { n: p.contents })) + '</span>' +
      '<span class="qs-pl">' + ic('device') + esc(p.platforms === 1 ? w.platOne.charAt(0).toUpperCase() + w.platOne.slice(1) : f(w.platsN, { n: p.platforms })) + '</span>' +
      (p.ad_budget ? '<span class="qs-pl">' + ic('bars') + esc(f(w.adUpTo, { b: n0(p.ad_budget) })) + '</span>' : '') + '</label>';
  }
  function platsHtml() {
    var I = window.ADspaceIcons;
    return '<div class="qs-chips qs-two qs-plats">' + CAT.platforms.map(function (k) {
      return chip('plat', k, S.platforms.indexOf(k) >= 0, t().plat[k] || k, I && I.mark ? I.mark(k) : '');
    }).join('') + '</div>';
  }
  function paintPlan() {
    var plans = CAT.plans.filter(function (p) { return Boolean(p.ads) === Boolean(S.withAds); }), p = planOf();
    return frame('<h1 class="qs-title">' + esc(t().planT) + '</h1><div class="qs-secs">' +
      sec(t().planH, seg('qsAds', t().need.ads[0], [['no', t().noAds], ['ads', t().withAds]], S.withAds ? 'ads' : 'no', true) +
        '<div class="qs-plans">' + plans.map(function (x, i) { return planCard(x, i, plans.length); }).join('') + '</div>' +
        '<div class="qs-xbox" id="qsPlanBox">' + planBox() + '</div>' +
        '<p class="qs-note">' + noteH((S.withAds ? adw('adNot') + ' ' : '') + t().ratesLater) + '</p>' + (S.withAds ? adHowBtn() : '')) +
      '<div class="qs-xbox" id="qsExtraBox">' + extrasHtml() + '</div>' +
      sec(t().platsH, (p ? '<p class="qs-note">' + noteH(f(p.platforms === 1 ? t().platHead1 : t().platHeadN, { p: p.plan, n: p.platforms })) + '</p>' : '') + platsHtml()) +
      '</div>', navFoot());
  }
  // A tick before each of the chosen plan's inclusions (the boards).
  /* What is included, a tick each; the delivery promise is the last (the user, 2026-11-25). */
  function inclList(items) {
    return items.length ? '<ul class="qs-incl">' + items.map(function (x) { return '<li>' + INCL_TICK + '<span>' + esc(x) + '</span></li>'; }).join('') + '</ul>' : '';
  }
  var INCL_TICK = window.ADspaceIcons.glyph('check', 'qs-incl-tick', 'width="14" height="14"');
  /* The plan chosen, under the cards: what it is best for, its content
     each month (a segment where it holds two options, else the one), then
     what it includes, a tick each. */
  function planBox() {
    var p = planOf(), w = t();
    if (!p) return '';
    var mixes = p.mix || [], cur = S.mix < mixes.length ? S.mix : 0;
    return '<div class="qs-plansel">' + '<b>' + esc(f(w.plan, { p: p.plan })) + '</b>' +
      (p.best_for ? '<p class="qs-best">' + esc(p.best_for) + '</p>' : '') +
      '<div class="qs-mixrow"><span class="qs-mixh" id="qsMixL">' + esc(f(mixes.length > 1 ? w.piecesPick : w.piecesHead, { n: p.contents })) + '</span>' +
      (mixes.length > 1 ? '<select class="select" id="qsMix" data-seg data-seg-value aria-labelledby="qsMixL">' + mixes.map(function (m, i) {
          return '<option value="' + i + '"' + (i === cur ? ' selected' : '') + '>' + esc(mixShort(m)) + '</option>'; }).join('') + '</select>'
        : '<span class="qs-mixone">' + esc(mixes[0] ? mixShort(mixes[0]) : '') + '</span>') + '</div>' +
      inclList((p.included || []).concat(w.delivered)) +
      '</div>';
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
        '<p class="qs-note">' + noteH(t().langsNote) + '</p>' +
        (CAT.translation && S.langs.length > 1 ? pick('checkbox', 'translate', '1', S.translate, t().translate, t().translateNote) : ''));
    }
    if (adsAsked()) {
      var opts = budgetOptions(), cur = S.budget == null ? opts[0][0] : S.budget;
      if (!opts.some(function (o) { return String(o[0]) === String(cur); })) cur = opts[0][0];
      S.budget = Number(cur);
      h += sec(t().budget, '<select class="select" id="qsBudget">' +
        opts.map(function (o) { return '<option value="' + o[0] + '"' + (String(o[0]) === String(cur) ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') + '</select>' +
        '<p class="qs-note">' + noteH(adw('adNot')) + '</p>' + adHowBtn(), 'qsBudget');
    }
    // 6, 12 or 24 months: a segment of three (DESIGN.md §4, a choice of two to four).
    if (monthly()) {
      if (TERMS.indexOf(S.term) < 0) S.term = TERMS.indexOf(12) >= 0 ? 12 : TERMS[0];
      h += sec(t().term, seg('qsTerm', t().term, TERMS.map(function (m) { return [m, f(t().months, { n: m })]; }), S.term, true) +
        '<p class="qs-note">' + noteH(t().termMin) + '</p>');
    }
    if (S.need.content && onceList().length) {
      h += sec(t().once, '<p class="qs-note">' + noteH(t().onceNote) + '</p>' + (p ? '' : inclList([t().delivered])) +
        onceList().map(function (c) { return stepper('once', c.slug, contentName(c), S.once[c.slug] || 0); }).join(''));
    }
    if (filesAsked()) h += '<div class="qs-xbox" id="qsFilesBox">' + filesHtml() + '</div>';
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
    if (S.need.verify && verifyList().length) {
      h += sec(t().verify, '<div class="qs-list">' +
        verifyList().map(function (v) { return pick('checkbox', 'verify', v.slug, S.verify.indexOf(v.slug) >= 0, v.name, ''); }).join('') + '</div>');
    }
    return frame('<h1 class="qs-title">' + esc(p ? f(t().customPlan, { p: p.plan }) : t().customT) + '</h1><div class="qs-secs">' + h + '</div>', navFoot());
  }

  var FILE_ZH = { 'Working files': '工作文件', 'Raw footage': '原始素材' };
  function todayMY() { return window.ADspaceClock.today(); }
  function field(id, label, req, html, hint) {
    return '<div class="field"><label class="field-label" for="' + id + '">' + esc(label) + '</label>' + html +
      (hint ? '<span class="qs-hint">' + esc(hint) + '</span>' : '') + '<span class="msg" id="' + id + 'Msg"></span></div>';
  }
  /* The intake's fields (QUOTE INTAKE, 2026-11-27), one copy for Your
     details and for Complete your details, each group as the team may ask
     for it: registration, industry, online, commence. Paired at a desk
     (`.qs-duo`), one column on a phone. */
  var GROUPS = ['registration', 'industry', 'online', 'commence'];
  var FIELD_IDS = ['qsKind', 'qsBrn', 'qsLegal', 'qsInd', 'qsSite', 'qsNoSite', 'qsPlat', 'qsHandle', 'qsStart', 'qsStartOn'];
  function pair(a, b) { return '<div class="qs-duo">' + a + b + '</div>'; }
  function opts(list, cur) {
    return list.map(function (o) { return '<option value="' + esc(o[0]) + '"' + (String(cur) === String(o[0]) ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('');
  }
  function regHtml(c) {
    var k = t().ik;
    return seg('qsKind', k.kind, k.kinds, c.kind || 'company') +
      pair(field('qsBrn', k.brn, true, '<input class="input" id="qsBrn" inputmode="numeric" autocomplete="off" maxlength="16" placeholder="202301012345" aria-required="true" value="' + esc(c.brn) + '">'),
        field('qsLegal', k.legal, true, '<input class="input qs-caps" id="qsLegal" autocomplete="organization" placeholder="' + AGENCY.trading_name.toUpperCase() + ' ADVERTISING SDN BHD" aria-required="true" value="' + esc(c.legal) + '">'));
  }
  function industryHtml(c) {
    return field('qsInd', t().industry, true, '<select class="select" id="qsInd" aria-required="true"><option value="">' + esc(t().choose) + '</option>' +
      INDUSTRIES.map(function (i) { return '<option value="' + esc(i.name) + '"' + (c.industry === i.name ? ' selected' : '') + '>' + esc((lang === 'zh' && i.name_zh) || i.name) + '</option>'; }).join('') + '</select>');
  }
  function onlineHtml(c) {
    var k = t().ik;
    return '<div id="qsSiteBox"' + (c.no_site ? ' hidden' : '') + '>' +
      field('qsSite', k.site, false, '<input class="input" id="qsSite" type="url" inputmode="url" autocomplete="url" placeholder="' + window.ADSPACE_CONFIG.examples.domain + '" value="' + esc(c.website) + '">') + '</div>' +
      '<label class="qs-consent"><input type="checkbox" id="qsNoSite"' + (c.no_site ? ' checked' : '') + '>' + MARK + '<span class="qs-text">' + esc(k.noSite) + '</span></label>' +
      pair(field('qsPlat', k.plat, false, '<select class="select" id="qsPlat">' + opts(k.plats, c.platform || 'instagram') + '</select>'),
        field('qsHandle', k.handle, false, '<input class="input" id="qsHandle" autocomplete="off" autocapitalize="none" placeholder="@' + AGENCY.trading_name.toLowerCase() + '" value="' + esc(c.handle) + '">'));
  }
  function commenceHtml(c) {
    /* One question for the start (ONE START QUESTION, 2026-11-21; the user:
       "Yes"): a period, or On a specific date, which opens the day, from
       today in Malaysia, the period then worked out from it (`startPeriod`). */
    return pair(field('qsStart', t().commence, true, '<select class="select" id="qsStart" aria-required="true"><option value="">' + esc(t().choose) + '</option>' +
        t().starts3.map(function (o) { return '<option value="' + o[0] + '"' + ((c.commence_on ? 'date' : c.commence) === o[0] ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') + '</select>'),
      '<div id="qsStartOnBox"' + (c.commence_on || c.commence === 'date' ? '' : ' hidden') + '>' +
        field('qsStartOn', t().startOn, true, '<input class="input" id="qsStartOn" type="date" min="' + todayMY() + '" max="2099-12-31" aria-required="true" value="' + esc(c.commence_on || '') + '">') + '</div>');
  }
  function paintDetails() {
    var c = S.contact, k = t().ik;
    return frame('<h1 class="qs-title">' + esc(t().detailsT) + '</h1>' +
      '<div class="qs-pfbox" id="qsPfBox"' + (pfPending().length ? '' : ' hidden') + '>' + pfHtml() + '</div>' +
      '<form class="qs-form" id="qsDetails" novalidate>' +
      sec(k.secContact,
        pair(field('qsSal', t().salutation, false, '<select class="select" id="qsSal"><option value="">' + esc(t().optional) + '</option>' +
            SALUTATIONS.map(function (x) { return '<option value="' + esc(x) + '"' + (c.salutation === x ? ' selected' : '') + '>' + esc((lang === 'zh' && SAL_ZH[x]) || x) + '</option>'; }).join('') + '</select>'),
          field('qsName', t().name, true, '<input class="input" id="qsName" autocomplete="name" placeholder="John Doe" aria-required="true" value="' + esc(c.name) + '">')) +
        pair(field('qsEmail', t().email, true, '<input class="input" id="qsEmail" type="email" autocomplete="email" placeholder="email@' + window.ADSPACE_CONFIG.examples.domain + '" aria-required="true" value="' + esc(c.email) + '">'),
          field('qsWa', t().wa, true, '<input class="input" id="qsWa" type="tel" inputmode="numeric" autocomplete="tel" placeholder="012-345 6789" aria-required="true" value="' + esc(c.whatsapp) + '">', t().waHint))) +
      sec(k.secBiz, regHtml(c)) +
      sec(k.secBrand,
        pair(field('qsBrand', t().brand, true, '<input class="input" id="qsBrand" autocomplete="off" placeholder="' + AGENCY.trading_name + ' Advertising" aria-required="true" value="' + esc(c.brand) + '">'),
          industryHtml(c)) + onlineHtml(c)) +
      sec(k.secStart, commenceHtml(c)) +
      field('qsCm', k.comments, false, '<textarea class="textarea" id="qsCm" rows="3" maxlength="1000" placeholder="' + esc(t().optional) + '">' + esc(c.comments) + '</textarea>') +
      '<label class="qs-consent"><input type="checkbox" id="qsConsent"' + (c.consent ? ' checked' : '') + '>' + MARK + '<span class="qs-text">' + esc(t().consent) + '</span></label>' +
      '<span class="msg" id="qsConsentMsg"></span>' +
      '<p class="qs-note">' + noteH(t().fullBrand) + '</p><div class="qs-cf" data-cf></div></form>', navFoot());
  }
  /* What a group's fields hold, read where they stand on the page. */
  function readFields(c) {
    var v = function (id) { return $(id) ? $(id).value : null; };
    if ($('qsKind')) { c.kind = v('qsKind'); c.brn = v('qsBrn').trim(); c.legal = v('qsLegal').replace(/\s+/g, ' ').trim(); }
    if ($('qsInd')) c.industry = v('qsInd');
    if ($('qsNoSite')) {
      c.no_site = $('qsNoSite').checked; c.website = c.no_site ? '' : v('qsSite').trim();
      c.platform = v('qsPlat'); c.handle = v('qsHandle').trim();
    }
    if ($('qsStart')) { c.commence = v('qsStart'); c.commence_on = c.commence === 'date' && $('qsStartOn') ? v('qsStartOn') : ''; }
  }
  function brnDigits(s) { return String(s || '').replace(/[\s-]+/g, ''); }
  /* The number's own refusal: 12 digits from a year, then the entity code
     for what is chosen (a company 01, 02 or 04; Sole / Partnership 03). */
  function brnSay(c) {
    var d = brnDigits(c.brn), k = t().ik.say, y = Number(d.slice(0, 4)), code = d.slice(4, 6);
    if (!/^\d{12}$/.test(d) || y < 1900 || y > Number(todayMY().slice(0, 4))) return k.brn;
    if (c.kind === 'soleprop') return code === '03' ? '' : /^0[124]$/.test(code) ? k.toCo : k.brn;
    return /^0[124]$/.test(code) ? '' : code === '03' ? k.toSole : k.brn;
  }
  function siteOk(s) {
    var u = /^https?:\/\//i.test(s) ? s : 'https://' + s;
    return !!window.ADspaceWords.absUrl(u) && /^https?:\/\/[^\/\s]+\.[^\/\s.]{2,}/i.test(u) && u.length <= 200;
  }
  function checkFields(c, groups, bad) {
    var k = t().ik.say, has = function (g) { return groups.indexOf(g) >= 0; };
    if (has('registration')) {
      var b = brnSay(c);
      if (b) bad('qsBrn', b);
      if (c.legal.length < 2) bad('qsLegal', k.legal);
    }
    if (has('industry') && !c.industry) bad('qsInd', k.industry);
    if (has('online')) {
      if (!c.no_site && !c.website) bad('qsSite', k.site);
      else if (!c.no_site && !siteOk(c.website)) bad('qsSite', k.siteBad);
      if (c.handle && !/^@?[A-Za-z0-9._-]{1,60}$/.test(c.handle)) bad('qsHandle', k.handleBad);
      else if (c.no_site && !c.handle) bad('qsHandle', k.handle);
    }
    if (has('commence')) {
      if (!c.commence) bad('qsStart', t().req.commence);
      else if (c.commence === 'date' && !(/^\d{4}-\d{2}-\d{2}$/.test(c.commence_on) && c.commence_on >= todayMY() && c.commence_on <= '2099-12-31')) bad('qsStartOn', t().req.startOn);
    }
  }
  /* A refusal the server names by field is said at that field. */
  function fieldRefused(d) {
    var k = t().ik.say;
    var to = { 'bad-brn': ['qsBrn', k.brn], 'bad-kind': ['qsBrn', k.brn], 'brn-kind': ['qsBrn', d.kind === 'soleprop' ? k.toSole : k.toCo],
      'bad-legal': ['qsLegal', k.legal], 'need-industry': ['qsInd', k.industry], 'need-site': ['qsSite', k.site], 'bad-site': ['qsSite', k.siteBad],
      'need-handle': ['qsHandle', k.handle], 'bad-handle': ['qsHandle', k.handleBad], 'bad-platform': ['qsPlat', k.handle],
      'bad-comments': ['qsCm', k.comments], 'bad-commence': ['qsStart', t().req.commence], 'bad-start-date': ['qsStartOn', t().req.startOn] }[d.error];
    if (!to || !$(to[0])) return false;
    say(to[0] + 'Msg', to[1]); $(to[0]).setAttribute('aria-invalid', 'true'); $(to[0]).focus();
    return true;
  }
  /* Complete your details (QUOTE DETAILS ASKED, 2026-11-27): the prospect's
     own link while the team asks for details, the fields ticked alone,
     prefilled with what was typed, the team's note as a card, Submit. */
  function paintAsk() {
    var q = Q, a = q.ask || {}, k = t().ik, fl = a.fields || [], c = Object.assign(blankContact(), a.known || {});
    if (a.known && a.known.commence_on) c.commence = 'date';
    var due = a.due ? day(a.due, false, 'ahead') : '';
    var has = function (g) { return fl.indexOf(g) >= 0; };
    return '<div class="qs-step qs-wide" data-shown><div class="qs-top"><h1 class="qs-title">' + esc(k.askT) + '</h1>' +
      '<p class="qs-lead">' + esc(f(k.askP, { d: due })) + '</p><span class="qs-meta">' + esc(q.ref + ' · ' + q.brand) + '</span></div>' +
      (a.note ? window.ADspaceIcons.card(k.askNote, '<p>' + esc(a.note) + '</p>') : '') +
      (fl.length ? '<form class="qs-form" id="qsAsk" novalidate>' +
        (has('registration') ? sec(k.secBiz, regHtml(c)) : '') +
        (has('industry') || has('online') ? sec(k.secBrand, (has('industry') ? industryHtml(c) : '') + (has('online') ? onlineHtml(c) : '')) : '') +
        (has('commence') ? sec(k.secStart, commenceHtml(c)) : '') + '</form>' : '') +
      '<p class="msg" id="qsMsg" role="status"></p></div>' +
      '<div class="qs-foot qs-wide"><button class="btn btn-primary" type="button" data-a="askSend">' + esc(k.submit) + '</button></div>';
  }
  function askSend(btn) {
    var a = (Q && Q.ask) || {}, fl = a.fields || [], c = blankContact(), first = null;
    var bad = function (id, w) { say(id + 'Msg', w); var el = $(id); if (el) el.setAttribute('aria-invalid', 'true'); first = first || el; };
    FIELD_IDS.forEach(function (id) { say(id + 'Msg', ''); if ($(id)) $(id).removeAttribute('aria-invalid'); });
    say('qsMsg', '');
    readFields(c);
    checkFields(c, fl, bad);
    if (first) { first.focus(); return; }
    var ans = {};
    if (fl.indexOf('registration') >= 0) { ans.kind = c.kind; ans.brn = brnDigits(c.brn); ans.legal = c.legal; }
    if (fl.indexOf('industry') >= 0) ans.industry = c.industry;
    if (fl.indexOf('online') >= 0) { ans.website = c.no_site ? '' : c.website; ans.no_site = !!c.no_site; ans.platform = c.handle ? c.platform : null; ans.handle = c.handle; }
    if (fl.indexOf('commence') >= 0) { ans.commence = startPeriod(c); ans.commence_on = c.commence_on || null; }
    btn.disabled = true;
    db.rpc('quote_details_submit', { p_key: qKey(), p_answers: ans }).then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error) {
        btn.disabled = false;
        if (d.error && fieldRefused(d)) return;
        if (['closed', 'sent', 'received', 'not-found'].indexOf(d.error) >= 0) { read(qKey()); return; }
        say('qsMsg', t().err[d.error] || t().err.any);
        return;
      }
      read(qKey());
    }).catch(function () { btn.disabled = false; say('qsMsg', t().err.any); });
  }

  /* A Singapore lead's quotation is in S$: its totals say so and carry the
     rate it was priced at, which turns the card's own RM budgets too
     (2026-10-15). */
  function qc() { return Q && Q.totals && Q.totals.currency === 'SGD' ? 'S$' : 'RM'; }
  function qb(n) { var fx = Q && Q.totals && Number(Q.totals.fx); return fx ? Math.round(Number(n) / fx) : Number(n); }
  /* A Singapore client billed in RM reads each total with the S$ it comes
     to (2026-11-27), at the rate the read carries (the quotation's, else
     the setting on its day of issue); billed in S$, or in Malaysia,
     nothing. ADspaceMoney.approx is the one copy. */
  function qCli() { return Q ? { market: Q.market, bill_market: qc() === 'S$' ? 'SG' : 'MY' } : null; }
  function qDay() { return Q && Q.issued_at ? (window.ADspaceClock ? window.ADspaceClock.day(Q.issued_at) : String(Q.issued_at).slice(0, 10)) : undefined; }
  function near(v) { return Q ? window.ADspaceMoney.approx(v, qCli(), qDay(), Q.fx_sgd, lang === 'zh') : ''; }
  /* The totals as a list: label, figure, a total in bold with its S$ under it. */
  function totHtml(rows, cls) {
    return rows.length ? '<dl class="qs-tot' + (cls ? ' ' + cls : '') + '">' + rows.map(function (x) {
      return '<div' + (x[2] ? ' class="is-total"' : '') + '><dt>' + esc(x[0]) + (x[4] ? '<small class="qs-near">' + esc(x[4]) + '</small>' : '') + '</dt><dd>' + esc(x[1]) +
        (x[3] ? '<small class="qs-near">' + esc(x[3].trim()) + '</small>' : '') + '</dd></div>';
    }).join('') + '</dl>' : '';
  }
  /* SST said as the Letter of Offer says it (ADspaceMoney.sstApplies): where
     it does not apply, its row reads not applicable, no total names it and
     the row before it, the same figure, is left out. */
  /* The lines priced: the quotation's own, or a change's while its figures draw. */
  var LINES_AT = null;
  function curLines() { return LINES_AT || (Q && Q.lines); }
  function taxed(tt) { return window.ADspaceMoney.sstOf(curLines(), tt.sst_pct); }
  function sstOn(tt) { return taxed(tt).on; }
  function word(tt, key) { return sstOn(tt) ? t()[key] : t()[key + 'None']; }
  function adsOf(tt) { return tt.layout === 2 && Array.isArray(tt.ads) ? tt.ads : []; }
  function termWords(n, p) {
    var line = window.ADspaceMoney.termLine(n, p, lang === 'zh');
    return lang === 'zh' ? line : line.charAt(0).toUpperCase() + line.slice(1);
  }
  function totalsRows(tt) {
    /* The rows are ADspaceMoney.quoteRows', one copy (2026-10-22, QT-4). */
    var w = t(), on = sstOn(tt);
    /* The rate the lines carry (a revision may hold a line's own code; the
       audit of 2026-10-26, finding 9), else SST where they differ. */
    var rt = /([\d.]+)%/.exec(taxed(tt).word);
    var sst = on ? (rt ? f(w.sst, { p: rt[1] }) : 'SST') : w.sstNone;
    var WORD = { monthSub: w.monthSub, onceSub: w.onceSub, firstExcl: w.firstExcl, monthExcl: w.monthExcl, sst: sst,
      first: word(tt, 'first'), monthly: word(tt, 'monthly'), oneOff: word(tt, 'oneOff') };
    /* A quotation in sections (layout 2, 2026-11-12) never adds the one-time
       items into a first month: each closes on its own total, as its PDF
       prints it, then the advertising budget for the term. */
    /* The whole period's totals where the team ticked them (PERIOD TOTAL ON
       A QUOTATION, 2026-11-27): the period under the monthly total, and the
       total with the one-time fees (`r.all`) a block of its own. */
    var pt = periodOf(tt), r = [];
    window.ADspaceMoney.quoteRows(tt, tt.layout === 2 ? [] : curLines(), on).forEach(function (x) {
      /* a row a term percentage where the lines differ (2026-11-15), in
         the PDF's words: a row whose lines run different months names
         none (2026-11-24) */
      var label = x[0] === 'term' ? termWords(x[4] ? x[4].months : tt.term, x[4] ? x[4].pct : tt.term_pct) : WORD[x[0]];
      r.push(x[2] ? [label, qc() + ' ' + n2(x[1]), 1, near(x[1])] : [label, n2(x[1])]);
      if (pt && (x[0] === 'monthly' || x[0] === 'first')) {
        var row = [ptWord('ptMonths', pt.months, on), qc() + ' ' + n2(pt.period), 0, near(pt.period)];
        row.period = true;
        r.push(row);
      }
    });
    if (pt && pt.total != null && tt.once) r.all = [ptWord('ptAll', pt.months, on), qc() + ' ' + n2(pt.total), 1, near(pt.total), ptWord('ptNote', pt.months, on)];
    if (adsOf(tt).length) r.push([w.adsT, qc() + ' ' + n2(tt.ads_total), 1, near(tt.ads_total)]);
    return r;
  }
  /* The tick kept with the quotation's own totals; one made before it reads
     its selection (the link's is the first quotation's). */
  function periodOf(tt) { return window.ADspaceMoney.periodTotals(tt, Q && tt === Q.totals && !Q.revised ? Q.selection : null); }
  /* English from ADspaceWords.line, one copy with the PDF; Chinese its own. */
  function ptWord(k, n, on) {
    if (lang === 'zh') return f(t()[k + (on || k === 'ptNote' ? '' : 'None')], { n: n });
    var L = window.ADspaceWords.line;
    return k === 'ptMonths' ? L.periodTotal(n, on) : k === 'ptAll' ? L.periodAll(on) : L.periodNote(n);
  }
  /* Where the prospect stands, one word from the database (2026-10-26):
     quote, ready, billing, billing_sent, letter, signed, welcome, expired.
     A page read from a database before it reads the older fields. */
  function stageOf(q) {
    if (q.stage) return q.stage;
    if (q.status === 'offer') return 'letter';
    if (q.valid_until < q.today) return 'expired';
    return q.proceed_at ? 'ready' : 'quote';
  }
  function paintQuote() {
    var q = Q, tt = q.totals || {}, st = stageOf(q), gone = st === 'expired';
    /* The head's chip keeps the quotation's own state (valid, expired,
       confirmed); the letter and its signing are the stage card's, said
       once (2026-10-27, QTE-3). */
    var over = q.valid_until < q.today;
    var chip = q.seal && q.seal.withdrawn ? ['is-off', t().withdrawn] : st === 'welcome' ? ['is-ok', t().confirmed]
      : st === 'closed' ? ['is-off', q.declined ? t().declined : t().closed]
      : over ? ['is-off', f(t().expired, { d: day(q.valid_until) })] : ['is-ok', f(t().valid, { d: day(q.valid_until, false, true) })];
    var status = '<span class="chip-state ' + chip[0] + '">' + esc(chip[1]) + '</span>';
    /* Several brands on one quotation (2026-11-24): each brand's lines under
       its name, as the PDF prints them. */
    var bn = Array.isArray(tt.brands) && tt.brands.length > 1 ? tt.brands : null, lastB = null;
    var lines = window.ADspaceMoney.planFold(q.lines, (q.totals || {}).currency, t().pack || null).map(function (l) {
      var head = '';
      if (bn && l.brand != null && l.brand !== lastB && bn[l.brand]) {
        lastB = l.brand;
        head = '<div class="qs-row qs-brandrow"><span class="qs-what">' + esc(String(bn[l.brand].name || '')) + '</span></div>';
      }
      /* Every inclusion a point, as the service lists them and the PDF
         prints them (2026-11-04). */
      var d = (l.detail || []).map(function (x) { return String(x == null ? '' : x).replace(/^\s*[-•·]\s*/, '').trim(); }).filter(Boolean);
      return head + '<div class="qs-row"><span class="qs-what">' + esc(l.label).replace(/\b(RM|S\$) (?=\d)/g, '$1\u00a0') + (Number(l.qty) > 1 ? '<span class="qs-calc">' + esc(l.qty + ' × ' + n2(l.rate)) + '</span>' : '') +
        (d.length ? '<ul class="incl">' + d.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul>' : '') + (l.basis === 'once' ? '<small>' + esc(t().onceTag) + '</small>' : '') + '</span>' +
        '<span class="qs-num qs-q">' + esc(l.qty) + '</span><span class="qs-num qs-r">' + esc(n2(l.rate)) + '</span><span class="qs-num">' + esc(n2(l.amount)) + '</span></div>';
    }).join('') + adsOf(tt).map(function (r) {
      var once = r.freq === 'once';
      /* A brand's own budget named after its brand (2026-11-26). */
      var bn = Array.isArray(tt.brands) && tt.brands.length > 1 && r.brand != null && tt.brands[r.brand] ? String(tt.brands[r.brand].name || '').trim() : '';
      return '<div class="qs-row"><span class="qs-what">' + esc((bn ? bn + ' · ' : '') + f(t().adLine, { p: window.ADspaceMoney.adWord(r.platform) })) +
        '<small>' + esc(once ? t().onceTag : f(t().months, { n: r.months })) + '</small></span>' +
        '<span class="qs-num qs-q">' + esc(once ? 1 : r.months) + '</span><span class="qs-num qs-r">' + esc(n2(r.budget)) + '</span><span class="qs-num">' + esc(n2(r.amount)) + '</span></div>';
    }).join('') + (tt.on_request || []).map(function (x) {
      return '<div class="qs-row"><span class="qs-what">' + esc(x === 'budget' ? budgetOnRequest() : x) + '</span>' +
        '<span class="qs-num qs-mute qs-onreq">' + esc(t().onReq) + '</span></div>';
    }).join('');
    var notes = [], managed = managedBudget(q), adAt = -1;
    if (adsOf(tt).length) notes.push(t().adsNote);
    else if (managed || Number(tt.budget) > 0 || (q.lines || []).some(function (l) { return l.kind === 'ads' || l.kind === 'plan'; })) {
      /* Not included, then How ad spend works under it (2026-11-27). */
      if (managed) notes.push(f(t().billManaged, { c: qc(), b: n0(qb(managed)) }));
      adAt = notes.push(adw('adNot')) - 1;
    }
    /* The validity is the status line's on screen; the PDF states it in its
       remarks (2026-10-20, QTE-1). */
    if (tt.layout === 2) {
      var pd = Number(tt.pay_days) || 7;
      notes.push(f(pd >= 30 ? t().payApprove : t().payNote, { d: pd }));
      (Array.isArray(tt.terms) ? tt.terms : []).forEach(function (x) { if (String(x || '').trim()) notes.push(String(x).trim()); });
    }
    if (addonsOf(tt).length) notes.push(aoWord('aoTerm'));
    notes.push(f(t().basis, { v: q.version }));
    var aside = '<aside class="qs-side" id="qsSide">' + sideHtml(q) + '</aside>';
    return '<div class="qs-quote" data-shown><section class="qs-main">' +
      ((st !== 'quote' && st !== 'ready') || q.revised || bn || q.change ? '' : '<button class="btn btn-quiet qs-change" type="button" data-a="change">' + window.ADspaceIcons.glyph('back', '', 'width="15" height="15"') + esc(t().change) + '</button>') +
      '<div class="qs-head"><h1 class="qs-title">' + esc(t().quoteT) + '</h1>' + (tt.title ? '<span class="qs-meta qs-own">' + esc(tt.title) + '</span>' : '') + '<span class="qs-meta">' + esc(q.ref + ' · ' + q.brand) + '</span><span class="qs-status">' + status + '</span>' +
        (q.revised ? '<span class="qs-meta">' + esc(f(t().revised, { d: day(q.issued_at), r: q.first_ref })) + '</span>' : '') + '</div>' +
      '<div class="qs-table"><div class="qs-row qs-headrow"><span>' + esc(t().line) + '</span><span class="qs-num qs-q">' + esc(t().qty) + '</span>' +
      '<span class="qs-num qs-r">' + esc(f(t().rate, { c: qc() })) + '</span><span class="qs-num">' + esc(f(t().sub, { c: qc() })) + '</span></div>' + lines + '</div>' +
      (function (rows) { return totHtml(rows) + (rows.all ? totHtml([rows.all], 'qs-tot-all') : ''); })(totalsRows(tt)) +
      /* Once sealed, the signed copy beside it is the one download. */
      (q.seal && q.seal.sealed ? '' : '<div class="qs-acts"><button class="btn" type="button" data-a="pdf">' + esc(t().download) + '</button></div>') +
      '<div class="qs-notes">' + notes.map(function (n, i) { return '<span>' + noteH(n) + '</span>' + (i === adAt ? adHowBtn() : ''); }).join('') + '</div>' +
      addonsHtml(tt) + '</section>' + aside + '</div>';
  }
  /* Add-on Rates (QUOTATION ADD-ON RATES, 2026-11-25): the rates the team
     ticked, read only, as the PDF prints them; never in a total. */
  function aoWord(k) { var L = window.ADspaceWords.line; return t()[k] || { aoH: L.addonRates, aoLead: L.addonLead, aoTerm: L.addonTerm, aoExtra: L.addonExtra }[k]; }
  function addonsOf(tt) { return Array.isArray(tt.addons) ? tt.addons.filter(function (r) { return r && r.name; }) : []; }
  function addonsHtml(tt) {
    var list = addonsOf(tt), groups = [], at = {};
    if (!list.length) return '';
    list.forEach(function (r) {
      var g = r.kind === 'extra' ? aoWord('aoExtra') : (r.group || window.ADspaceWords.line.addons);
      if (!at[g]) { at[g] = { g: g, rows: [] }; groups.push(at[g]); }
      at[g].rows.push(r);
    });
    return '<section class="qs-addons" id="qsAddons"><h2 class="qs-sec-h">' + esc(aoWord('aoH')) + '</h2><p class="qs-note">' + noteH(aoWord('aoLead')) + '</p>' +
      '<div class="qs-aogrid">' + groups.map(function (g) {
        return '<div class="qs-aogroup"><h3>' + esc(g.g) + '</h3><dl>' + g.rows.map(function (r) {
          return '<div><dt>' + esc(r.name) + '</dt><dd>' + esc(window.ADspaceMoney.addonRate(r, tt.currency, lang === 'zh')) + '</dd></div>';
        }).join('') + '</dl></div>';
      }).join('') + '</div></section>';
  }
  function paintBare() {
    var q = Q;
    return '<div class="qs-quote is-single" data-shown><section class="qs-main">' +
      '<div class="qs-head"><h1 class="qs-title">' + esc(t().quoteT) + '</h1><span class="qs-meta">' + esc(q.ref + ' · ' + q.brand) + '</span></div>' +
      '<div class="qs-review-act" id="qsSide">' + sideHtml(q) + '</div></section></div>';
  }
  /* A website quotation the team has not sent yet (2026-10-29, the user:
     "the price shouldnt send out straight"): the database sends no line or
     figure, so the page says it was received and when it will be sent. A
     full-page state, so it is every page's cover (2026-11-20, after RIMOWA's
     notice): Request received as the title, the day as the statement, then
     the note and the quotation's reference; the way on is Chat on WhatsApp,
     with the colleague who took the lead where one has (QTE-2). */
  /* Request received (the boards QuoteReceivedPhone and QuoteReceivedDesk,
     2026-11-25): the green tick, the title, the day as the statement and
     the reference; where the request stands as a track; what was asked for,
     a glyph each and never a price; who will be in touch. */
  function paintReview() {
    var q = Q, w = t(), I = window.ADspaceIcons, first = q.rep ? String(q.rep.name || '').trim().split(' ')[0] : '';
    var due = q.reply_due ? day(q.reply_due, false, 'ahead') : '';
    var C = window.ADspaceClock, zh = lang === 'zh', sentAt = q.issued_at && C ? C.date(q.issued_at, { zh: zh }) + (zh ? '' : ', ') + C.clock(q.issued_at, { zh: zh }) : '';
    var rows = requestRows(q.selection || {});
    var chat = function (words) {
      return '<a class="btn btn-primary" href="' + esc(repHref(q)) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(words) + '</a>';
    };
    return I.received({
      title: w.reviewT, line: due ? f(w.reviewP, { d: due }) : '', ref: q.ref + ' · ' + q.brand,
      steps: [
        { state: 'done', title: w.rcvSent, sub: esc(sentAt) },
      ].concat(q.details_at ? [{ state: 'done', title: w.ik.rcvDetails, sub: esc(C ? C.date(q.details_at, { zh: zh }) + (zh ? '' : ', ') + C.clock(q.details_at, { zh: zh }) : '') }] : []).concat([
        { state: 'now', glyph: 'search', title: w.rcvReview, now: w.rcvNow },
        { glyph: 'doc', title: w.rcvSend, sub: due ? esc(f(w.rcvBy, { d: due })) : '' },
        { glyph: 'pen', title: w.rcvSign }
      ]),
      cards: [
        rows.length ? I.card(w.rcvYours, '<ul class="qs-asklist">' + rows.map(function (r) {
          return '<li><span class="qs-disc is-sm">' + ic(r[0], 'qs-g') + '</span><span>' + esc(r[1]) + '</span></li>'; }).join('') + '</ul>') : '',
        q.rep ? I.contactCard(w.repT, q.rep.name, q.rep.title, chat(f(w.repChat, { n: first }))) : ''
      ],
      foot: q.rep ? '' : chat(w.chat)
    });
  }
  /* What the prospect asked for, as the selection kept holds it: a row a
     part, its glyph and its words, never a price. */
  function requestRows(sel) {
    var w = t(), out = [], plan = CAT && sel.plan ? CAT.plans.filter(function (p) { return p.slug === sel.plan; })[0] : null;
    if (plan) {
      out.push(['plancontent', w.need.social[0] + ' · ' + f(w.plan, { p: plan.plan })]);
      var m = (plan.mix || [])[Number(sel.mix) || 0];
      out.push(['pieces', f(w.piecesN, { n: plan.contents }) + (m ? (lang === 'zh' ? '：' : '; ') + mixShort(m) : '')]);
    }
    if ((sel.platforms || []).length) out.push(['device', sel.platforms.map(function (k) { return w.plat[k] || k; }).join(lang === 'zh' ? '、' : ', ')]);
    if (sel.budget != null && (!plan || Number(sel.budget) !== 0 || plan.ad_budget)) out.push(['planads', w.need.ads[0]]);
    var named = function (slug) {
      var all = CAT ? [].concat(CAT.contents || [], CAT.files || [], CAT.verify || [], CAT.koc || []) : [];
      var x = all.filter(function (c) { return c.slug === slug; })[0];
      if (!x) return slug === (CAT && CAT.kol) ? w.kol : null;
      return x.kind ? contentName(x) : (lang === 'zh' && FILE_ZH[x.name]) || x.name;
    };
    (sel.once || []).forEach(function (o) {
      var n = named(o.slug); if (!n) return;
      var g = CAT && (CAT.verify || []).some(function (v) { return v.slug === o.slug; }) ? 'verified'
        : CAT && ((CAT.koc || []).some(function (v) { return v.slug === o.slug; }) || o.slug === CAT.kol) ? 'people' : 'picture';
      out.push([g, n + (Number(o.qty) > 1 ? ' × ' + Number(o.qty) : '')]);
    });
    if (Number(sel.term) > 1) out.push(['clock', f(w.months, { n: sel.term })]);
    return out;
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
    var who = cfg.quoteWhatsApp;
    return who + '?text=' + encodeURIComponent(q && q.ref ? 'Hello ' + AGENCY.trading_name + ', I would like to enquire about my quotation ' + q.ref + '.' : 'Hello ' + AGENCY.trading_name + ', I would like to enquire about a quotation.');
  }
  /* Beside the quotation (under it on a phone): the colleague who took the
     lead, once one has, with their own WhatsApp where their namecard shows
     it; before that, Ready to proceed: when the prospect would start and
     whether they decide, recorded on the lead with Proceed with this
     quotation, which opens nothing (2026-10-26). A free proposal is never
     offered. */
  var TICK = '<span class="qs-asked-tick" aria-hidden="true">' + window.ADspaceIcons.glyph('check', '', 'width="13" height="13"') + '</span>';
  function done(title, line) {
    return '<div class="qs-asked">' + TICK + '<span><b>' + esc(title) + '</b>' + (line ? '<span>' + esc(line) + '</span>' : '') + '</span></div>';
  }
  /* The colleague's own WhatsApp where their namecard shows it, else the
     office's. */
  function repHref(q) {
    var whole = q.rep ? String(q.rep.name || '').trim() : '';
    return q.rep && q.rep.whatsapp ? 'https://wa.me/' + encodeURIComponent(q.rep.whatsapp) + '?text=' +
      encodeURIComponent('Hello ' + whole + ', I would like to discuss my quotation ' + q.ref + '.') : waLink(q);
  }
  function repHtml(q) {
    var w = t(), first = String(q.rep.name || '').trim().split(' ')[0];
    var href = repHref(q);
    /* A person card: the name and position on a white card with its way to
       reach them, never an initials disc (no stand-in for a person's
       picture; 2026-11-07). */
    return '<h2>' + esc(w.repT) + '</h2><p>' + esc(f(w.repP, { n: first, b: q.brand })) + '</p>' +
      '<div class="qs-rep"><span class="qs-rep-who"><b>' + esc(q.rep.name) + '</b>' + (q.rep.title ? '<small>' + esc(q.rep.title) + '</small>' : '') + '</span>' +
      '<a class="btn" href="' + esc(href) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(f(w.repChat, { n: first })) + '</a></div>';
  }
  /* What stands beside the quotation (under it on a phone), by stage
     (2026-10-26). Ready to proceed asks when the prospect would start and
     whether they decide, never a free proposal; then billing through the
     client's own details form, the Letter of Offer, its signed copy, and
     Welcome with the client portal's sign-in (never a sign-in itself). The
     colleague who took the lead stands under each step. */
  function sideHtml(q) {
    /* With no colleague named yet, every step still offers a way to reach
       the agency: the office's Chat on WhatsApp (2026-10-27, QTE-2). */
    var w = t(), st = stageOf(q), rep = q.rep ? '<div class="qs-side-rep">' + repHtml(q) + '</div>'
      : '<a class="btn" href="' + esc(waLink(q)) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(w.chat) + '</a>';
    if (st === 'expired' || st === 'closed') {
      /* A request never quoted reads closed, never cancelled (QUOTE DETAILS ASKED). */
      return '<h2>' + esc(st === 'closed' ? (q.declined ? w.declinedT : !q.lines ? w.ik.reqClosedT : w.closedT) : w.goneT) + '</h2><p>' + esc(w.goneP) + '</p>' + (q.proceed_at ? done(w.goneAsked) : '') +
        '<button class="btn btn-primary" type="button" data-a="new">' + esc(w.newQuote) + '</button>' +
        '<a class="btn" href="' + esc(repHref(q)) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(w.chat) + '</a>';
    }
    if (st === 'welcome') {
      return (q.reviewed ? confirmedHtml(q, true) : '') + '<h2>' + esc(w.welcomeT) + '</h2><p>' + esc(w.welcomeP) + '</p>' +
        (q.portal ? '<a class="btn btn-primary" href="/client/">' + esc(w.portalBtn) + '</a>' : '<p>' + esc(w.portalLater) + '</p>') + rep;
    }
    if (st === 'accepted') return acceptedHtml(q) + rep;
    if (st === 'signed') return done(w.signedT, w.signedP) + rep;
    if (st === 'letter') return done(w.offer, w.letterP) + rep;
    if (st === 'billing_sent') return done(w.billSentT, w.billSentP) + rep;
    if (st === 'billing') {
      return '<h2>' + esc(w.billT) + '</h2><p>' + esc(w.billP) + '</p>' +
        '<a class="btn btn-primary" href="/details/?k=' + encodeURIComponent(q.details_key || '') + '">' + esc(w.billBtn) + '</a>' + rep;
    }
    /* A sent, valid quotation not yet signed is accepted here: company
       details, the signature and a code emailed to the billing contact
       (2026-10-31, in place of Ready to proceed). */
    if (SG && SG.step) return signHtml(q);
    /* A change request stands (QUOTATION CHANGES REQUESTED, 2026-11-25): no
       Accept and sign until the team sends the revision. */
    if (q.change) {
      return '<h2>' + esc(w.chgPendT) + '</h2><p>' + esc(f(w.chgPend, { d: day(myDay(q.change.at)), r: day(myDay(q.change.reply_due || q.reply_due || q.change.at), false, 'ahead') })) + '</p>' +
        (PREVIEW ? '' : '<button class="btn btn-quiet" type="button" data-a="chwithdraw">' + esc(w.chgWithdraw) + '</button>') +
        '<p class="msg" id="qsSideMsg" role="status"></p>' + rep;
    }
    return '<h2>' + esc(w.sg.title) + '</h2><p>' + esc(w.sg.line) + '</p>' + signSteps(0) +
      '<button class="btn btn-primary" type="button" data-a="signgo">' + esc(w.sg.go) + '</button>' +
      /* The client may decline instead (QUOTATION WAYS OUT, 2026-11-17). */
      (PREVIEW ? '' : '<button class="btn btn-quiet" type="button" data-a="decline">' + esc(w.decline) + '</button>') +
      '<p class="msg" id="qsSideMsg" role="status"></p>' + rep;
  }

  // ---- Changing a sent quotation (QUOTATION CHANGES REQUESTED, 2026-11-25) -------
  /* "Prices after we send" (the user, 2026-11-25): on the quotation the team
     sent, the prospect may change the plan, content option, platforms,
     additional content, files and commitment and see the price follow
     (`quote_website_preview` by the link's key, on the quotation's own Rate
     Card); every line the team added stays. A changed selection is not
     signed: Request these changes returns it to the team, who send the
     revision the link then shows. */
  var CH = null, CHP = {};
  /* A moment as Malaysia's day (a timestamp's own date is UTC's). */
  function myDay(iso) { var C = window.ADspaceClock; return C && C.day ? C.day(iso) : iso; }
  function chEditable(q) { return Boolean(q && !q.signed && !q.revised && CAT && !(Array.isArray((q.totals || {}).brands) && q.totals.brands.length > 1) && (stageOf(q) === 'quote' || stageOf(q) === 'ready')); }
  function chFileSlugs() { return (CAT && CAT.files || []).map(function (x) { return x.slug; }); }
  function chBase(q) {
    var s0 = q.selection || {}, files = {}, fs = chFileSlugs();
    (s0.once || []).forEach(function (o) { if (fs.indexOf(o.slug) >= 0) files[o.slug] = Number(o.qty) || 0; });
    return { plan: s0.plan || null, mix: Number(s0.mix) || 0, platforms: (s0.platforms || []).slice(), extra: JSON.parse(JSON.stringify(s0.extra || {})),
      files: files, term: Number(s0.term) || 12 };
  }
  function chSel() {
    var c = CH.sel, x = {}, f2 = {};
    Object.keys(c.extra).forEach(function (k) { if (c.extra[k] > 0) x[k] = c.extra[k]; });
    chFileSlugs().forEach(function (k) { f2[k] = c.files[k] || 0; });
    var o = { platforms: CAT.platforms.filter(function (k) { return c.platforms.indexOf(k) >= 0; }), extra: x, files: f2, term: c.term };
    if (c.plan) { o.plan = c.plan; o.mix = String(c.mix); }
    return o;
  }
  function chKey(sel) { return JSON.stringify(sel); }
  function chChanged() { return chKey(chSel()) !== CH.baseKey; }
  function chPlan() { return CAT && CH.sel.plan ? CAT.plans.filter(function (p) { return p.slug === CH.sel.plan; })[0] || null : null; }
  function chMoney(v) { return qc() + ' ' + n0(v); }
  /* The files the changed selection may hold, as quote_change_sel holds
     them: its pieces, the quotation's one-time content among them, and
     never fewer than the quotation already held. */
  function chFileLim(sl) {
    var n = piecesOf(chPlan(), CH.sel.mix, CH.sel.extra, ((Q && Q.selection && Q.selection.once) || []).concat(chPackItems()));
    var x = ((CAT && CAT.files) || []).filter(function (f2) { return f2.slug === sl; })[0];
    return Math.max(x ? fileCap(x, n) : STEP_MAX, (CH.held || {})[sl] || 0);
  }
  function chFilesHtml() {
    var w = t(), card = (CH.P && CH.P.card) || {};
    Object.keys(CH.sel.files).forEach(function (k) { if (CH.sel.files[k] > chFileLim(k)) CH.sel.files[k] = chFileLim(k); });
    var list = (card.files || []).filter(function (x) { return chFileLim(x.slug) > 0; });
    return list.length ? sec(w.files, '<p class="qs-note">' + noteH(w.filesNote) + '</p>' + list.map(function (x) {
      return stepper('chf', x.slug, (lang === 'zh' && FILE_ZH[x.name]) || x.name, CH.sel.files[x.slug] || 0, f(w.each, { a: chMoney(x.rate) }), chFileLim(x.slug));
    }).join(''), null, w.filesOpt) : '';
  }
  function chFilesRepaint() { var b = $('qsChFilesBox'); if (b) b.innerHTML = chFilesHtml(); }
  function chOpen() {
    CH = { sel: chBase(Q), P: null, fail: false };
    CH.held = JSON.parse(JSON.stringify(CH.sel.files));
    var s0 = chSel(); CH.baseKey = chKey(s0);
    CH.withAds = Boolean((chPlan() || {}).ads);
    paint(); window.scrollTo(0, 0); chPrice();
  }
  var chTimer = null;
  /* The first answer brings the card's prices, so the choices are drawn again with them. */
  function chShow(d) { var had = CH.P && CH.P.card; CH.P = d; CH.fail = false; if (had) chDraw(); else chRepaint(); }
  function chPrice() {
    if (!CH) return;
    var sel = chSel(), k = chKey(sel);
    if (CHP[k]) { chShow(CHP[k]); return; }
    clearTimeout(chTimer);
    chTimer = setTimeout(function () {
      var box = $('qsChFig'); if (box) box.setAttribute('aria-busy', 'true');
      db.rpc('quote_website_preview', { p_key: qKey(), p_sel: sel }).then(function (r) {
        var d = r && r.data;
        if (!CH || k !== chKey(chSel())) return;
        if (r.error || !d || d.error) { CH.P = null; CH.fail = true; chDraw(); return; }
        CHP[k] = d; chShow(d);
      }).catch(function () { if (CH && k === chKey(chSel())) { CH.P = null; CH.fail = true; chDraw(); } });
    }, 180);
  }
  /* What each platform adds, as the quotation prices it: the plan's places
     go to the cheapest chosen, a dearer one inside the plan adding the
     difference from Meta's fee; one past the places its own fee. */
  function chPlatNotes() {
    var R = (CH.P && CH.P.card && CH.P.card.platforms) || {}, p = chPlan(), out = {};
    var order = CAT.platforms, fee = function (k) { return Number(R[k] || 0); }, base = fee('meta');
    var picked = CH.sel.platforms.filter(function (k) { return order.indexOf(k) >= 0; })
      .sort(function (a, b) { return fee(a) - fee(b) || order.indexOf(a) - order.indexOf(b); });
    var slots = p ? p.platforms : 0;
    order.forEach(function (k) {
      if (R[k] == null) return;
      if (!p) { out[k] = f(t().perMonth, { a: chMoney(fee(k)) }); return; }
      var i = picked.indexOf(k), inPlan = i >= 0 ? i < slots : picked.length < slots;
      out[k] = inPlan ? (fee(k) > base ? f(t().plusMonth, { a: chMoney(fee(k) - base) }) : t().incl) : f(t().plusMonth, { a: chMoney(fee(k)) });
    });
    return out;
  }
  /* A package the team quoted (QUOTATION PACKAGES, 2026-11-25) is read
     here as the PDF prints it, never changed by the prospect: its contents
     and price are the team's. Its pieces still count towards the files. */
  function chPackItems() {
    return ((Q && Q.selection && Q.selection.packages) || []).reduce(function (a, pk) { return a.concat((pk && pk.items) || []); }, []);
  }
  function chPackHtml() {
    var w = t(), pk = window.ADspaceMoney.planFold(((Q && Q.lines) || []).filter(function (l) { return l.kind === 'package'; }), (Q.totals || {}).currency, w.pack || null);
    if (!pk.length) return '';
    return sec(w.packH, '<div class="qs-table">' + pk.map(function (l) {
      var d = (l.detail || []).map(function (x) { return String(x == null ? '' : x).trim(); }).filter(Boolean);
      return '<div class="qs-row"><span class="qs-what">' + esc(l.label) +
        (d.length ? '<ul class="incl">' + d.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul>' : '') +
        (l.basis === 'once' ? '<small>' + esc(w.onceTag) + '</small>' : '') + '</span>' +
        '<span class="qs-num">' + esc(n2(l.amount)) + '</span></div>';
    }).join('') + '</div>');
  }
  function chEditor() {
    var w = t(), p = chPlan(), P = CH.P || {}, card = P.card || {}, I = window.ADspaceIcons;
    var plans = CAT.plans.filter(function (x) { return Boolean(x.ads) === Boolean(CH.withAds); });
    var notes = chPlatNotes(), xr = P.extra_rates || {};
    var h = chPackHtml() + sec(w.planH, seg('qsChAds', w.need.ads[0], [['no', w.noAds], ['ads', w.withAds]], CH.withAds ? 'ads' : 'no', true) +
      '<div class="qs-plans">' + plans.map(function (x, i) {
        var on = CH.sel.plan === x.slug, feat = plans.length === 3 && i === 1, r = (card.plans || {})[x.slug];
        return '<label class="qs-plan' + (on ? ' is-on' : '') + (feat ? ' is-feat' : '') + '"><input type="radio" name="chplan" value="' + esc(x.slug) + '"' + (on ? ' checked' : '') + '>' +
          (feat ? '<span class="qs-rec">' + esc(w.recommended) + '</span>' : '') + ic(x.ads ? 'planads' : 'plancontent', 'qs-plan-ic') +
          '<b>' + esc(f(w.plan, { p: x.plan })) + '</b>' + (r != null ? '<span class="qs-planprice">' + esc(f(w.perMonth, { a: chMoney(r) })) + '</span>' : '') +
          '<span class="qs-pl">' + ic('pieces') + esc(f(w.piecesN, { n: x.contents })) + '</span>' +
          '<span class="qs-pl">' + ic('device') + esc(x.platforms === 1 ? w.platOne.charAt(0).toUpperCase() + w.platOne.slice(1) : f(w.platsN, { n: x.platforms })) + '</span>' +
          (x.ad_budget ? '<span class="qs-pl">' + ic('bars') + esc(f(w.adUpTo, { b: n0(qb(x.ad_budget)) })) + '</span>' : '') + '</label>';
      }).join('') + '</div>');
    if (p && (p.mix || []).length > 1) {
      h += sec(f(w.piecesPick, { n: p.contents }), '<select class="select" id="qsChMix" data-seg data-seg-value aria-label="' + esc(f(w.piecesHead, { n: p.contents })) + '">' +
        p.mix.map(function (m, i) { return '<option value="' + i + '"' + (i === CH.sel.mix ? ' selected' : '') + '>' + esc(mixShort(m)) + '</option>'; }).join('') + '</select>');
    }
    if (p) {
      h += sec(w.extra, extrasOf(p).map(function (c) {
        return stepper('chx', c.slug, contentName(c), CH.sel.extra[c.slug] || 0, xr[c.slug] != null ? f(w.eachMonth, { a: chMoney(xr[c.slug]) }) : '');
      }).join(''));
    }
    h += sec(w.platsH, '<div class="qs-chips qs-two qs-plats">' + CAT.platforms.map(function (k) {
      var on = CH.sel.platforms.indexOf(k) >= 0;
      return '<label class="qs-chip' + (on ? ' is-on' : '') + '"><input type="checkbox" name="chplat" value="' + esc(k) + '"' + (on ? ' checked' : '') + '><span class="qs-text">' +
        '<span class="qs-lead-mark">' + (I && I.mark ? I.mark(k) : '') + '</span><span class="qs-chip-w">' + esc(w.plat[k] || k) + '</span>' +
        (notes[k] ? '<small class="qs-price" data-chnote="' + esc(k) + '">' + esc(notes[k]) + '</small>' : '') + '</span>' + MARK + '</label>';
    }).join('') + '</div>');
    h += '<div class="qs-xbox" id="qsChFilesBox">' + chFilesHtml() + '</div>';
    var terms = (card.terms || []).map(function (x) { return Number(x.months); });
    if (terms.length) {
      // No discount sentence under the term: the totals carry it (the user, 2026-11-27).
      h += sec(w.term, seg('qsChTerm', w.term, terms.map(function (m) { return [m, f(w.months, { n: m })]; }), CH.sel.term, true));
    }
    return h;
  }
  /* The figures as the quotation would read with the changes. */
  function chFigures() {
    var w = t(), P = CH.P;
    if (CH.fail) return '<p class="msg err">' + esc(w.offP) + '</p>';
    if (!P) return '';
    var tt = P.totals || {};
    var rows = (P.lines || []).map(function (l) {
      return '<div class="qs-row"><span class="qs-what">' + esc(l.label).replace(/\b(RM|S\$) (?=\d)/g, '$1 ') + (l.basis === 'once' ? '<small>' + esc(w.onceTag) + '</small>' : '') + '</span>' +
        '<span class="qs-num qs-q">' + esc(l.qty) + '</span><span class="qs-num qs-r">' + esc(n2(Number(l.qty) ? l.amount / l.qty : l.amount)) + '</span><span class="qs-num">' + esc(n2(l.amount)) + '</span></div>';
    }).join('');
    return '<div class="qs-table"><div class="qs-row qs-headrow"><span>' + esc(w.line) + '</span><span class="qs-num qs-q">' + esc(w.qty) + '</span>' +
      '<span class="qs-num qs-r">' + esc(f(w.rate, { c: qc() })) + '</span><span class="qs-num">' + esc(f(w.sub, { c: qc() })) + '</span></div>' + rows + '</div>' +
      totHtml(chTotals(tt, P.lines));
  }
  /* The shared refused-send line (`js/words.js`), in the page's language. */
  function chNotSent() { var A = window.ADspaceWords; var w = A && A.of ? A.of({ en: {}, zh: {} })[lang === 'zh' ? 'zh' : 'en'] : null; return (w && w.notSentAdspace) || t().err.any; }
  function chTotals(tt, lines) { LINES_AT = lines || []; try { return totalsRows(tt); } finally { LINES_AT = null; } }
  function chSide() {
    var w = t(), changed = chChanged(), tt = CH.P && CH.P.totals;
    /* The totals the changes come to, beside the acts (the page's title is not said again). */
    var tot = tt ? chTotals(tt, CH.P.lines).filter(function (x) { return x[2]; }) : [];
    return totHtml(tot) +
      (changed ? '' : '<p>' + esc(w.chgNone) + '</p>') +
      (CH.pf && CH.pf.length && CH.pfKey === chKey(chSel()) ? '<ul class="qs-pflist">' + CH.pf.map(function (k) { return '<li><span class="qs-pftext">' + esc(w.pf[k]) + '</span></li>'; }).join('') + '</ul>' : '') +
      '<div class="qs-sfoot is-stack"><button class="btn" type="button" data-a="chcancel">' + esc(w.chgCancel) + '</button>' +
      (changed ? '<button class="btn btn-primary" type="button" data-a="chsend">' + esc(w.chgReq) + '</button>' : '') + '</div>' +
      '<p class="msg" id="qsSideMsg" role="status"></p>';
  }
  function paintChange() {
    var q = Q, w = t();
    return '<div class="qs-quote" data-shown><section class="qs-main">' +
      '<div class="qs-head"><h1 class="qs-title">' + esc(w.chgT) + '</h1><span class="qs-meta">' + esc(q.ref + ' · ' + q.brand) + '</span></div>' +
      '<div class="qs-secs"><div class="qs-xbox" id="qsChEdit">' + chEditor() + '</div>' +
      '<section class="qs-sec qs-chfig"><h2 class="qs-sec-h">' + esc(w.chgTotal) + '</h2><div id="qsChFig" aria-live="polite">' + chFigures() + '</div></section></div>' +
      '</section><aside class="qs-side" id="qsSide">' + chSide() + '</aside></div>';
  }
  function chDraw() {
    if (!CH) return;
    var fig = $('qsChFig'); if (fig) { fig.innerHTML = chFigures(); fig.removeAttribute('aria-busy'); }
    var side = $('qsSide'); if (side) side.innerHTML = chSide();
    var notes = chPlatNotes();
    Array.prototype.forEach.call(root().querySelectorAll('[data-chnote]'), function (n) { n.textContent = notes[n.getAttribute('data-chnote')] || ''; });
    var xr = (CH.P && CH.P.extra_rates) || {};
    Array.prototype.forEach.call(root().querySelectorAll('[data-group="chx"][data-step="1"]'), function (b) {
      var row = b.closest('.qs-stepper'), lab = row && row.querySelector('span'), r = xr[b.getAttribute('data-slug')];
      if (!lab || r == null) return;
      var sm = lab.querySelector('small'); if (!sm) { sm = document.createElement('small'); lab.appendChild(sm); }
      sm.textContent = f(t().eachMonth, { a: chMoney(r) });
    });
  }
  function chRepaint() { var e = $('qsChEdit'); if (e) { e.innerHTML = chEditor(); decorate(); } chDraw(); }
  /* Request these changes is checked first against the preview the page
     shows (QUOTATION PREFLIGHT, 2026-11-25): a choice no longer offered, or
     a price that is no longer the one shown, is said in the panel and the
     preview read again; nothing is sent until the check is clean. A
     refusal of the link itself is the request's own to say. */
  function chSend(btn) {
    btn.disabled = true;
    var P = CH && CH.P, tt = (P && P.totals) || {}, sel = chSel();
    var go2 = function () { chRequest(btn, sel); };
    db.rpc('quote_preflight', { p_sel: sel, p_key: qKey(), p_seen: { version: P && P.version,
      month: tt.month ? tt.month.incl : null, once: tt.once ? tt.once.incl : null } }).then(function (r) {
      var d = r && r.data;
      if (r.error || !d || d.error || !Array.isArray(d.changes) || !d.changes.length) { go2(); return; }
      btn.disabled = false;
      CH.pf = d.changes.map(function (c) { return c.kind === 'price' ? 'priceMoved' : 'choiceGone'; })
        .filter(function (k, i, a) { return a.indexOf(k) === i; });
      CH.pfKey = chKey(sel); CHP = {}; CH.P = null; chDraw(); chPrice();
    }).catch(go2);
  }
  function chRequest(btn, sel) {
    db.rpc('quote_change_request', { p_key: qKey(), p_sel: sel }).then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error) { btn.disabled = false; say('qsSideMsg', t().err[d.error] || chNotSent()); return; }
      CH = null; CHP = {};
      read(qKey(), function () { window.ADspaceChrome.underHead($('qsSide')); });
    }).catch(function () { btn.disabled = false; say('qsSideMsg', chNotSent()); });
  }
  function chWithdraw(btn) {
    btn.disabled = true;
    db.rpc('quote_change_request', { p_key: qKey(), p_sel: null }).then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error) { btn.disabled = false; say('qsSideMsg', t().err[d.error] || chNotSent()); return; }
      read(qKey());
    }).catch(function () { btn.disabled = false; say('qsSideMsg', chNotSent()); });
  }
  /* Whether a change request stands, read with the link (the preview
     answers it; nothing is kept). */
  function chState(k) {
    if (!Q || !chEditable(Q)) return;
    db.rpc('quote_website_preview', { p_key: k, p_sel: null }).then(function (r) {
      var d = r && r.data;
      if (r.error || !d || d.error || !Q) return;
      var before = !!Q.change;
      Q.change = d.change || null;
      CHP[chKey(chBaseSel())] = d;
      if (before !== !!Q.change && !CH) paint();
    }).catch(function () {});
  }
  function chBaseSel() { var keep = CH; CH = { sel: chBase(Q) }; var s0 = chSel(); CH = keep; return s0; }

  // ---- Accepting the quotation (2026-10-31) ----------------------------------------
  /* Held in this page alone, never kept in the tab (as the details step is):
     the company, the billing contact, the signer and the signature, while
     the three steps are gone through. */
  var SG = null;
  var SG_SAL = SALUTATIONS;
  function signStart() {
    var p = (Q && Q.prefill) || {}, co = p.company || {}, ct = p.contact || {};
    /* A quotation billed to another of the client's companies (Bill to,
       2026-11-12) opens on that company; its SST no. and TIN are its own,
       never the brand's. */
    var bt = Q && Q.totals && Q.totals.bill_to;
    if (bt && bt.legal_name) co = { legal_name: bt.legal_name, company_no: bt.company_no || '', billing_address: bt.billing_address || '' };
    SG = { step: 1, mode: 'draw', path: '', text: '', agree: false, email: '', sentAt: 0,
      co: { legal_name: String(co.legal_name || '').toUpperCase(), company_no: co.company_no || '', company_no_old: co.company_no_old || '', billing_address: co.billing_address || '',
        sst_no: co.sst_no || '', tin: co.tin || '', finance_email: co.finance_email || '' },
      ct: { salutation: SG_SAL.indexOf(ct.salutation) >= 0 ? ct.salutation : '', name: ct.name || '', phone: ct.phone || '', email: ct.email || '' },
      signer: { name: '', designation: '' } };
  }
  function signSteps(now) {
    var w = t().sg, sub = [SG && SG.co.legal_name, SG && SG.signer.name ? SG.signer.name + (SG.signer.designation ? ', ' + SG.signer.designation : '') : ''];
    return '<ol class="qs-steps qs-ssteps">' + w.steps.map(function (s, i) {
      var n = i + 1, cls = now && n < now ? 'is-done' : n === now ? 'is-now' : '';
      return '<li' + (cls ? ' class="' + cls + '"' : '') + (n === now ? ' aria-current="step"' : '') + '><span>' + esc(s) +
        (cls === 'is-done' && sub[i] ? '<small>' + esc(sub[i]) + '</small>' : '') + '</span></li>';
    }).join('') + '</ol>';
  }
  function sgField(id, label, req, html) {
    return '<div class="field"><label class="field-label" for="' + id + '">' + esc(label) + '</label>' + html + '<span class="msg" id="' + id + 'Msg"></span></div>';
  }
  function sgInput(id, value, attrs, cls) {
    return '<input class="input' + (cls ? ' ' + cls : '') + '" id="' + id + '" value="' + esc(value || '') + '"' + (attrs || '') + '>';
  }
  function signFoot(back, go, label) {
    return '<div class="qs-sfoot"><button class="btn" type="button" data-a="' + back + '">' + esc(t().back) + '</button>' +
      '<button class="btn btn-primary" type="button" data-a="' + go + '">' + esc(label || t().cont) + '</button></div>';
  }
  /* The figures agreed to: every bold total the quotation closes on (the
     monthly, the one-time and the advertising budget), the minimum term
     after the monthly, and on a quotation before sections the whole term,
     as its acceptance page prints them (2026-11-12, review finding 1). */
  function agreedRows(q) {
    var tt = q.totals || {}, w = t(), out = [], first = true;
    var rows = totalsRows(tt);
    rows.forEach(function (x) {
      /* the whole period's figures as the PDF's acceptance page names them */
      if (x.period) { out.push([x[0], x[1], 0, x[3]]); return; }
      if (!x[2]) return;
      out.push([x[0], x[1], 1, x[3]]);
      if (first && tt.month) out.push([w.sg.minTerm, f(w.months, { n: tt.term })]);
      first = false;
      if (rows.all && x[0] === word(tt, 'oneOff')) out.push(rows.all.slice(0, 4));
    });
    if (tt.month && tt.layout !== 2 && tt.commitment != null) out.push([sstOn(tt) ? w.sg.termTotalIncl : w.sg.termTotal, qc() + ' ' + n2(tt.commitment), 0, near(tt.commitment)]);
    return out;
  }
  function signHtml(q) {
    var w = t(), s = w.sg, c = SG.co, k = SG.ct, opt = ' placeholder="' + esc(w.optional) + '"';
    var head = '<h2 tabindex="-1" id="sgHead">' + esc(s.title) + '</h2>' + signSteps(SG.step);
    if (SG.step === 1) {
      return head + '<form class="qs-form qs-signform" id="sgForm" novalidate>' +
        sgField('sgLegal', s.legal, true, sgInput('sgLegal', c.legal_name, ' autocomplete="organization" placeholder="COMPANY NAME SDN BHD" aria-required="true"', 'qs-caps')) +
        sgField('sgReg', s.reg, true, sgInput('sgReg', c.company_no, ' autocomplete="off" aria-required="true"')) +
        sgField('sgRegOld', s.regOld, false, sgInput('sgRegOld', c.company_no_old, ' autocomplete="off"' + opt)) +
        sgField('sgAddr', s.addr, true, '<textarea class="textarea" id="sgAddr" rows="3" autocomplete="street-address" placeholder="' + esc(s.addrPh) + '" aria-required="true">' + esc(c.billing_address) + '</textarea>') +
        '<div class="qs-pair">' + sgField('sgSst', s.sst, false, sgInput('sgSst', c.sst_no, ' autocomplete="off"' + opt)) +
          sgField('sgTin', s.tin, false, sgInput('sgTin', c.tin, ' autocomplete="off"' + opt)) + '</div>' +
        sgField('sgFin', s.fin, false, sgInput('sgFin', c.finance_email, ' type="email" autocomplete="email"' + opt)) +
        '<h3 class="qs-sec-h qs-sform-h">' + esc(s.contactH) + '</h3>' +
        sgField('sgSal', w.salutation, false, '<select class="select" id="sgSal"><option value="">' + esc(w.optional) + '</option>' +
          SG_SAL.map(function (x) { return '<option value="' + esc(x) + '"' + (k.salutation === x ? ' selected' : '') + '>' + esc((lang === 'zh' && SAL_ZH[x]) || x) + '</option>'; }).join('') + '</select>') +
        sgField('sgName', w.name, true, sgInput('sgName', k.name, ' autocomplete="name" placeholder="John Doe" aria-required="true"')) +
        sgField('sgMobile', s.mobile, true, sgInput('sgMobile', k.phone, ' type="tel" inputmode="tel" autocomplete="tel" placeholder="012-345 6789" aria-required="true"')) +
        sgField('sgEmail', s.email, true, sgInput('sgEmail', k.email, ' type="email" autocomplete="email" placeholder="email@' + window.ADSPACE_CONFIG.examples.domain + '" aria-required="true"')) +
        '<p class="msg" id="qsSideMsg" role="status"></p>' + signFoot('signback', 'signnext') + '</form>';
    }
    if (SG.step === 2) {
      var sig = SG.mode === 'type'
        ? sgInput('sgTyped', SG.text, ' autocomplete="off" placeholder="' + esc(s.typedPh) + '" aria-labelledby="sgSigL"', 'qs-typed')
        : '<div class="qs-pad" id="sgPad" role="img" aria-labelledby="sgSigL"><span class="qs-pad-line" aria-hidden="true"></span>' +
          '<span class="qs-pad-hint" aria-hidden="true"' + (SG.path ? ' hidden' : '') + '>' + esc(s.padHint) + '</span>' +
          window.ADspaceIcons.drawing('0 0 300 100', '<path d="' + esc(SG.path) + '"/>', 'preserveAspectRatio="none" aria-hidden="true"') + '</div>';
      return head + '<form class="qs-form qs-signform" id="sgForm" novalidate>' +
        totHtml(agreedRows(q), 'qs-agreed') +
        '<div class="qs-pair">' + sgField('sgSigner', s.signer, true, sgInput('sgSigner', SG.signer.name, ' autocomplete="name" placeholder="John Doe" aria-required="true"')) +
          sgField('sgDesig', s.desig, true, sgInput('sgDesig', SG.signer.designation, ' autocomplete="organization-title" aria-required="true"')) + '</div>' +
        '<div class="field"><div class="qs-sig-head"><span class="field-label is-req" id="sgSigL">' + esc(s.sig) + '</span><span class="qs-sig-acts">' +
          (SG.mode === 'draw' ? '<button class="btn btn-quiet btn-sm" type="button" data-a="signclear"' + (SG.path ? '' : ' hidden') + '>' + esc(s.clear) + '</button>' : '') +
          '<button class="btn btn-quiet btn-sm" type="button" data-a="signmode">' + esc(SG.mode === 'draw' ? s.typeIn : s.drawIn) + '</button></span></div>' +
          sig + '<span class="msg" id="sgPadMsg"></span></div>' +
        '<label class="qs-consent"><input type="checkbox" id="sgAgree"' + (SG.agree ? ' checked' : '') + '>' + MARK +
          '<span class="qs-text">' + esc(f(s.agree, { c: SG.co.legal_name })) + '</span></label><span class="msg" id="sgAgreeMsg"></span>' +
        (cfg.serviceTermsUrl ? '<a class="btn btn-quiet btn-sm qs-terms" href="' + esc(window.ADspaceWords.absUrl(cfg.serviceTermsUrl)) + '" target="_blank" rel="noopener">' + esc(s.terms) + LEAVE + '</a>' : '') +
        '<div class="qs-cf" data-cf></div><p class="msg" id="qsSideMsg" role="status"></p>' + signFoot('signback', 'signcode') + '</form>';
    }
    var boxes = '';
    for (var i = 0; i < 6; i++) {
      boxes += '<input class="input" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="6" data-otp="' + i + '"' +
        (i === 0 ? ' autocomplete="one-time-code"' : ' autocomplete="off"') + ' aria-label="' + esc(f(s.digit, { n: i + 1 })) + '">';
    }
    return head + '<form class="qs-form qs-signform" id="sgForm" novalidate>' +
      '<div class="field"><span class="field-label" id="sgCodeL">' + esc(f(s.codeL, { e: SG.email })) + '</span>' +
        '<div class="qs-otp" role="group" aria-labelledby="sgCodeL">' + boxes + '</div><span class="msg" id="sgCodeMsg" role="status"></span></div>' +
      '<div class="qs-resend"><span>' + esc(s.resendQ) + '</span><button class="btn btn-quiet btn-sm" type="button" data-a="signresend">' + esc(s.resend) + '</button></div>' +
      '<div class="qs-cf" data-cf></div><p class="msg" id="qsSideMsg" role="status"></p>' + signFoot('signback', 'signfinish', s.finish) +
      '<p class="qs-note">' + noteH(s.rec) + '</p></form>';
  }
  var LEAVE = window.ADspaceIcons.glyph('out', '', 'width="15" height="15"');
  /* What the signer typed, read into the page's copy before any redraw. */
  function signRead() {
    if (!SG) return;
    var v = function (id) { return $(id) ? $(id).value : null; };
    if (SG.step === 1 && $('sgLegal')) {
      SG.co = { legal_name: v('sgLegal').replace(/\s+/g, ' ').trim().toUpperCase(), company_no: v('sgReg').trim(), company_no_old: v('sgRegOld').trim(),
        billing_address: v('sgAddr').trim(), sst_no: v('sgSst').trim(), tin: v('sgTin').trim(), finance_email: v('sgFin').trim() };
      SG.ct = { salutation: v('sgSal'), name: v('sgName').replace(/\s+/g, ' ').trim(), phone: v('sgMobile').trim(), email: v('sgEmail').trim() };
    }
    if (SG.step === 2 && $('sgSigner')) {
      SG.signer = { name: v('sgSigner').replace(/\s+/g, ' ').trim(), designation: v('sgDesig').replace(/\s+/g, ' ').trim() };
      if ($('sgTyped')) SG.text = v('sgTyped').replace(/\s+/g, ' ').trim();
      SG.agree = $('sgAgree').checked;
    }
  }
  function sgBad(id, word, first) {
    say(id + 'Msg', word);
    var el = $(id); if (el) el.setAttribute('aria-invalid', 'true');
    return first || el;
  }
  function signCheck() {
    signRead();
    var w = t().sg.say, first = null, up = function (x) { return String(x || '').replace(/\s+/g, '').toUpperCase(); };
    Array.prototype.forEach.call($('qsSide').querySelectorAll('[aria-invalid]'), function (el) { el.removeAttribute('aria-invalid'); say(el.id + 'Msg', ''); });
    if (SG.step === 1) {
      var c = SG.co, k = SG.ct;
      if (c.legal_name.length < 2) first = sgBad('sgLegal', w.legal, first);
      if (!/^[A-Z0-9-]{6,20}$/.test(up(c.company_no))) first = sgBad('sgReg', w.reg, first);
      if (c.company_no_old && !/^[A-Z0-9-]{4,20}$/.test(up(c.company_no_old))) first = sgBad('sgRegOld', w.regOld, first);
      if (c.billing_address.length < 10) first = sgBad('sgAddr', w.addr, first);
      if (c.sst_no && !/^[A-Z0-9-]{6,25}$/.test(up(c.sst_no))) first = sgBad('sgSst', w.sst, first);
      if (c.tin && !/^[A-Z0-9-]{6,20}$/.test(up(c.tin))) first = sgBad('sgTin', w.tin, first);
      if (c.finance_email && !ADspaceWords.emailOk(c.finance_email)) first = sgBad('sgFin', w.email, first);
      if (k.name.length < 2) first = sgBad('sgName', w.name, first);
      var d = k.phone.replace(/[^0-9]/g, '');
      if (d.length < 8 || d.length > 15) first = sgBad('sgMobile', w.mobile, first);
      if (!ADspaceWords.emailOk(k.email)) first = sgBad('sgEmail', w.email, first);
    } else if (SG.step === 2) {
      if (SG.signer.name.length < 2) first = sgBad('sgSigner', w.signer, first);
      if (SG.signer.designation.length < 2) first = sgBad('sgDesig', w.desig, first);
      if (SG.mode === 'type' ? SG.text.length < 2 : !/L/.test(SG.path)) first = sgBad(SG.mode === 'type' ? 'sgTyped' : 'sgPad', w.sig, first) || $('sgPad');
      if (SG.mode === 'draw' && !/L/.test(SG.path)) say('sgPadMsg', w.sig);
      if (!SG.agree) first = sgBad('sgAgree', w.agree, first);
    }
    if (first) { if (first.id === 'sgPad') first.scrollIntoView({ block: 'center' }); else first.focus(); }
    return !first;
  }
  /* Redraw the card on its step, its heading brought into view (under the
     quotation on a phone) and given the focus, never a field. */
  function signShow(step) {
    if (step != null) SG.step = step;
    $('qsSide').innerHTML = sideHtml(Q);
    decorate();
    var h = $('sgHead') || $('qsSide');
    var top = $('qsSide').getBoundingClientRect().top;
    if (top < window.ADspaceChrome.headRoom() || top > window.innerHeight * 0.6) window.ADspaceChrome.underHead($('qsSide'));
    if (h.focus) h.focus({ preventScroll: true });
  }
  var SG_SAY = { 'bad-legal_name': [1, 'sgLegal', 'legal'], 'bad-company_no': [1, 'sgReg', 'reg'], 'bad-company_no_old': [1, 'sgRegOld', 'regOld'],
    'bad-tin': [1, 'sgTin', 'tin'], 'bad-sst_no': [1, 'sgSst', 'sst'], 'bad-billing_address': [1, 'sgAddr', 'addr'], 'bad-finance_email': [1, 'sgFin', 'email'],
    'bad-contact_salutation': [1, 'sgSal', 'sal'], 'bad-contact_name': [1, 'sgName', 'name'], 'bad-contact_phone': [1, 'sgMobile', 'mobile'],
    'bad-contact_email': [1, 'sgEmail', 'email'], 'bad-signer_name': [2, 'sgSigner', 'signer'], 'bad-signer_designation': [2, 'sgDesig', 'desig'],
    'bad-signature': [2, 'sgPad', 'sig'], 'bad-agree': [2, 'sgAgree', 'agree'] };
  var SG_WORD = { 'too-many': 'tooMany', 'no-code': 'noCode', 'code-expired': 'expired', locked: 'locked' };
  function qKey() { return new URLSearchParams(location.search).get('q'); }
  /* A refusal that means the quotation moved on (signed meanwhile, closed,
     expired, not sent): the link is read again and says where it stands. */
  function signGone(code) { return ['not-found', 'closed', 'unsent', 'signed', 'expired'].indexOf(code) >= 0; }
  function signRefused(code, d) {
    var w = t().sg.say;
    if (signGone(code)) { SG = null; read(qKey(), function () { window.ADspaceChrome.underHead($('qsSide')); }); return; }
    var at = SG_SAY[code];
    if (at) {
      if (SG.step !== at[0]) signShow(at[0]);
      var el = sgBad(at[1], w[at[2]]);
      if (at[1] === 'sgPad') say('sgPadMsg', w.sig);
      if (el && el.focus && at[1] !== 'sgPad') el.focus();
      return;
    }
    if (code === 'wrong') { say('sgCodeMsg', d && d.left === 1 ? w.wrong1 : f(w.wrong, { n: d && d.left != null ? d.left : '' })); otpClear(); return; }
    say(SG.step === 3 && $('sgCodeMsg') ? 'sgCodeMsg' : 'qsSideMsg', SG_WORD[code] ? w[SG_WORD[code]] : (t().err[code] || t().err.any));
  }
  function signPayload() {
    var c = SG.co, k = SG.ct;
    return { company: { legal_name: c.legal_name.toUpperCase(), company_no: c.company_no, company_no_old: c.company_no_old || undefined,
      tin: c.tin || undefined, sst_no: c.sst_no || undefined, billing_address: c.billing_address, finance_email: c.finance_email || undefined },
      contact: { salutation: k.salutation || '', name: k.name, phone: k.phone, email: k.email },
      signer: { name: SG.signer.name, designation: SG.signer.designation },
      signature: SG.mode === 'type' ? { type: 'typed', text: SG.text } : { type: 'drawn', path: SG.path }, agree: true,
      /* The device as this browser reports it, kept with the signature
         (SIGNED DOCUMENT SEAL, 2026-11-17). */
      device: window.ADspaceSeal ? window.ADspaceSeal.device() : undefined };
  }
  /* The code goes to the billing contact's email, made by the server; the
     page is told where it went. Send again rests a minute after each. */
  function signCode(btn, again) {
    if (!again && !signCheck()) return;
    var label = btn.textContent;
    btn.disabled = true; if (!again) btn.textContent = t().sg.sending;
    say('qsSideMsg', '');
    var C = window.ADspaceCaptcha, host = $('qsSide').querySelector('[data-cf]');
    var token = C && C.on && host ? C.token(host) : Promise.resolve(null);
    token.then(function (tk) {
      return db.functions.invoke('quote-request', { body: { action: 'sign', key: qKey(), token: tk || '', payload: signPayload() } });
    }).then(function (r) {
      var d = (r && r.data) || {};
      btn.disabled = false; if (!again) btn.textContent = label;
      /* Left by Back while the code was asked for: nothing to show it on. */
      if (!SG) return;
      if (r.error || d.error || !d.ok) { signRefused(d.error || 'any', d); return; }
      SG.email = d.email || SG.ct.email; SG.sentAt = Date.now();
      if (SG.step !== 3) signShow(3);
      else { otpClear(); resendTick(); }
      if (again) say('sgCodeMsg', t().sg.resent, 'ok');
    }).catch(function () { btn.disabled = false; if (!again) btn.textContent = label; say('qsSideMsg', t().err.any); });
  }
  function signFinish(btn) {
    var code = otpValue();
    if (!/^\d{6}$/.test(code)) { say('sgCodeMsg', t().sg.say.code); otpFocus(code.length); return; }
    btn.disabled = true; btn.textContent = t().sg.finishing;
    db.rpc('quote_sign_finish', { p_key: qKey(), p_code: code }).then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error || !d.ok) { btn.disabled = false; btn.textContent = t().sg.finish; signRefused(d.error || 'any', d); return; }
      SG = null;
      read(qKey(), function () { var s = $('qsSide'); if (s) { window.ADspaceChrome.underHead(s); s.setAttribute('tabindex', '-1'); s.focus({ preventScroll: true }); } });
    }).catch(function () { btn.disabled = false; btn.textContent = t().sg.finish; say('qsSideMsg', t().err.any); });
  }
  // The six boxes: one a digit, typing or pasting moving along, Backspace moving back.
  function otpBoxes() { return Array.prototype.slice.call($('qsSide').querySelectorAll('[data-otp]')); }
  function otpValue() { return otpBoxes().map(function (b) { return b.value; }).join('').replace(/\D/g, ''); }
  function otpFocus(i) { var b = otpBoxes(); if (b.length) b[Math.min(Math.max(i, 0), 5)].focus(); }
  function otpClear() { otpBoxes().forEach(function (b) { b.value = ''; }); otpFocus(0); }
  function otpFill(from, digits) {
    var b = otpBoxes();
    for (var i = 0; i < digits.length && from + i < 6; i++) b[from + i].value = digits.charAt(i);
    otpFocus(Math.min(from + digits.length, 5));
  }
  var resendTimer = null;
  function resendTick() {
    clearInterval(resendTimer);
    var tick = function () {
      var b = $('qsSide') && $('qsSide').querySelector('[data-a="signresend"]');
      if (!b || !SG) { clearInterval(resendTimer); return; }
      var left = Math.ceil((SG.sentAt + 60000 - Date.now()) / 1000);
      b.disabled = left > 0;
      b.textContent = left > 0 ? f(t().sg.resendIn, { s: left }) : t().sg.resend;
      if (left <= 0) clearInterval(resendTimer);
    };
    tick(); resendTimer = setInterval(tick, 1000);
  }
  /* The pad: a finger or a mouse draws one path in a 300 by 100 box. */
  function padWire() {
    var pad = $('sgPad');
    if (!pad || pad.getAttribute('data-wired')) return;
    pad.setAttribute('data-wired', '1');
    var path = pad.querySelector('path'), on = false, lx = 0, ly = 0;
    var pt = function (e) {
      var r = pad.getBoundingClientRect();
      return [Math.max(0, Math.min(300, (e.clientX - r.left) / r.width * 300)), Math.max(0, Math.min(100, (e.clientY - r.top) / r.height * 100))];
    };
    var fx = function (n) { return (Math.round(n * 10) / 10).toString(); };
    pad.addEventListener('pointerdown', function (e) {
      if (SG.path.length > 28000) return;
      e.preventDefault(); on = true;
      try { pad.setPointerCapture(e.pointerId); } catch (x) {}
      var p = pt(e); lx = p[0]; ly = p[1];
      SG.path += (SG.path ? ' ' : '') + 'M' + fx(lx) + ' ' + fx(ly);
      path.setAttribute('d', SG.path);
      var hint = pad.querySelector('.qs-pad-hint'); if (hint) hint.hidden = true;
      pad.removeAttribute('aria-invalid'); say('sgPadMsg', '');
    });
    pad.addEventListener('pointermove', function (e) {
      if (!on || SG.path.length > 28000) return;
      var p = pt(e);
      if (Math.abs(p[0] - lx) + Math.abs(p[1] - ly) < 1.2) return;
      lx = p[0]; ly = p[1];
      SG.path += ' L' + fx(lx) + ' ' + fx(ly);
      path.setAttribute('d', SG.path);
    });
    var end = function () {
      if (!on) return; on = false;
      // A dot alone is a stroke too: a point beside itself.
      if (/M[\d.]+ [\d.]+$/.test(SG.path)) { SG.path += ' L' + fx(lx + 0.5) + ' ' + fx(ly + 0.5); path.setAttribute('d', SG.path); }
      var c = $('qsSide').querySelector('[data-a="signclear"]'); if (c) c.hidden = !SG.path;
    };
    pad.addEventListener('pointerup', end); pad.addEventListener('pointercancel', end); pad.addEventListener('lostpointercapture', end);
  }
  function signWire() {
    if (!SG || !$('qsSide')) return;
    padWire();
    if (SG.step === 3 && SG.sentAt) resendTick();
  }
  /* Signed (SIGNED DOCUMENT SEAL, 2026-11-17): Accepted, awaiting
     the agency's confirmation, who signed and when to the second; then
     Confirmed with the Document ID and the sealed copy to download. */
  function acceptedHtml(q) {
    if (q.reviewed) return confirmedHtml(q) + '<p>' + esc(t().sg.doneP) + '</p>';
    var w = t().sg, s = q.signed || {}, who = s.signer || {}, C = window.ADspaceClock;
    var name = who.name ? who.name + (who.designation ? (lang === 'zh' ? '（' + who.designation + '）' : ', ' + who.designation) : '') : '';
    return '<p class="qs-sstate"><span class="chip-state is-warn">' + esc(w.waitT) + '</span></p>' +
      (name && s.at ? '<p class="qs-sline">' + esc(f(w.waitP, { n: name, d: lang === 'zh' ? day(C.day(s.at)) : day(C.day(s.at), true),
        t: C.clock(s.at, { sec: true, zh: lang === 'zh' }) })) + '</p>' : '') + '<p>' + esc(w.doneP) + '</p>';
  }
  /* Welcome's head already reads Confirmed, so its card says it once
     (`quiet`). */
  function confirmedHtml(q, quiet) {
    var w = t().sg, C = window.ADspaceClock, sl = q.seal || {};
    var on = q.reviewed && q.reviewed.at ? (lang === 'zh' ? day(C.day(q.reviewed.at)) : day(C.day(q.reviewed.at), true)) : '';
    var off = sl.withdrawn && sl.withdrawn_on ? (lang === 'zh' ? day(sl.withdrawn_on) : day(sl.withdrawn_on, true)) : '';
    return (quiet ? '' : '<p class="qs-sstate"><span class="chip-state ' + (sl.withdrawn ? 'is-off' : 'is-ok') + '">' + esc(sl.withdrawn ? t().withdrawn : w.confT) + '</span></p>') +
      '<p class="qs-sline">' + esc(on ? f(w.confP, { d: on }) : '') + (sl.id ? ' ' + esc(f(w.docId, { id: sl.id })) : '') + '</p>' +
      (off ? '<p class="qs-sline">' + esc(f(t().withdrawnP, { d: off })) + '</p>' : '') +
      (sl.sealed ? '<button class="btn" type="button" data-a="sealed">' + esc(w.sealDl) + '</button><p class="msg" id="qsSideMsg" role="status"></p>' : '');
  }
  /* The sealed copy, read through sign-download by the link's own key. */
  function sealedPdf(btn) {
    withPdf(btn, sealedNow, function () { say('qsSideMsg', t().err.any); });
  }
  function sealedNow(btn) {
    var tab = window.ADspaceDocs && window.ADspaceDocs.tabFor ? window.ADspaceDocs.tabFor() : null;
    btn.disabled = true;
    db.functions.invoke('sign-download', { body: { quoteKey: qKey() } }).then(function (r) {
      var b = r && r.data;
      if (r.error || !b || typeof b.size !== 'number' || !b.size) throw new Error('unread');
      btn.disabled = false;
      window.ADspaceDocs.save(b.type === 'application/pdf' ? b : new Blob([b], { type: 'application/pdf' }), window.ADspaceQuotePdf.fileName(Q), tab);
    }).catch(function () {
      btn.disabled = false;
      if (tab) try { tab.close(); } catch (e) {}
      say('qsSideMsg', t().err.any);
    });
  }
  function cover(title, text, start, glyph) {
    root().innerHTML = '<section class="cover" data-shown><div class="cover-inner"><div class="cover-panel" data-glyph="' + (glyph || 'alert') + '"><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p>' +
      '<div class="cover-acts"><a class="btn' + (start ? '' : ' btn-primary') + '" href="' + esc(waLink(null)) + '" target="_blank" rel="noopener">' + CHAT_MARK + esc(t().chat) + '</a>' +
      (start ? '<a class="btn btn-primary" href="/quote/">' + esc(t().newQuote) + '</a>' : '') + '</div></div></div></section>';
  }

  function paint() {
    document.documentElement.setAttribute('lang', lang === 'zh' ? 'zh' : 'en');
    if ($('langToggle')) $('langToggle').textContent = t().lang;
    if (paint.lost) { cover(t().lostT, t().lostP, true, 'linkoff'); return; }
    if (!CAT && !Q) { if (paint.off) cover(t().offT, t().offP, false, 'alert'); return; }
    /* A quotation the team never sent holds back its price at every stage
       (audit 2026-10-30): closed, it reads its stage alone. */
    // The budget follows the selection on every paint.
    if (CAT && !adsAsked()) S.budget = null;
    if (Q && CH) { root().innerHTML = paintChange(); decorate(); return; }
    if (Q) { root().innerHTML = stageOf(Q) === 'review' ? paintReview() : stageOf(Q) === 'details' ? paintAsk() : !Q.lines ? paintBare() : paintQuote(); decorate(); return; }
    if (S.step === 'intro') {
      S = blank(); PF = { items: [], key: null };
      try { sessionStorage.removeItem(KEEP); } catch (e) {}
      root().innerHTML = paintIntro(); decorate(); return;
    }
    if (steps().indexOf(S.step) < 0) S.step = 'need';
    root().innerHTML = { need: paintNeed, plan: paintPlan, custom: paintCustom, details: paintDetails }[S.step]();
    decorate();
    if (S.step === 'details' && CAT && PF.key !== pfKey()) pfRun();
  }
  function decorate() {
    if (window.ADspaceForm && window.ADspaceForm.scan) window.ADspaceForm.scan(root());
    var dl = root().querySelectorAll('[data-a="pdf"], [data-a="sealed"]');
    Array.prototype.forEach.call(dl, function (b) { addGlyph(b, 'file'); });
    /* The PDF scripts are fetched where a Download is drawn (js/chrome.js
       need), so they are here by the press: a tab an iPhone opens at the
       press stays the press's. The opening page fetches neither. */
    if (dl.length) window.ADspaceChrome.need(['quotepdf']).catch(function () {});
    if (window.ADspaceGrow && window.ADspaceGrow.fit) Array.prototype.forEach.call(root().querySelectorAll('textarea'), window.ADspaceGrow.fit);
    signWire();
  }
  // The WhatsApp mark, as the front door draws it before the same words.
  var CHAT_MARK = window.ADspaceIcons.glyph('whatsapp', '', 'width="15" height="15"');
  function addGlyph(b, k) {
    if (b.querySelector('svg')) return;
    b.insertAdjacentHTML('afterbegin', window.ADspaceIcons.glyph(k, '', 'width="15" height="15"'));
  }
  function say(id, text, tone) {
    var m = $(id); if (!m) return;
    m.textContent = text || ''; m.className = 'msg' + (text ? ' ' + (tone || 'err') : '');
  }
  function go(step) { pfSeen(step); S.step = step; keep(); paint(); window.scrollTo(0, 0); }

  // ---- What changed before Submit (QUOTATION PREFLIGHT, 2026-11-25) ------------
  /* The user, 2026-11-25, "like a concert ticket checkout": on reaching the
     final step, and again on Submit, what was chosen is checked against the
     live Rate Card (`quote_preflight`, never a price). Each change is one
     line on the final step with the step that resolves it; the catalogue is
     read again so that step offers what stands. A line stays until its step
     is visited (the Rate Card's own until Continue), so nothing chosen
     leaves the selection unseen, and Submit waits until none stands. */
  /* A change's kind and its line's word (keys quoted: the kinds are words of the page's own too). */
  var PF_WORD = { 'off': 'pageOff', 'version': 'cardMoved', 'plan': 'gonePlan', 'mix': 'goneMix', 'platform': 'gonePlatform', 'extra': 'goneExtra',
    'translate': 'goneTranslate', 'term': 'goneTerm', 'once': 'goneOnce', 'cap': 'goneCap' };
  function pfStep(kind) {
    if (['plan', 'mix', 'platform', 'extra'].indexOf(kind) >= 0) return steps().indexOf('plan') >= 0 ? 'plan' : 'need';
    return kind === 'version' || kind === 'off' ? null : 'custom';
  }
  function pfName(x) {
    var c = x.cat || CAT || {}, w = t();
    var find = function (list) { return (list || []).filter(function (o) { return o.slug === x.slug; })[0]; };
    if (x.kind === 'plan' || x.kind === 'mix') { var p = find(c.plans); return p ? f(w.plan, { p: p.plan }) : ''; }
    if (x.kind === 'platform') return w.plat[x.slug] || '';
    if (x.kind === 'term') return x.slug || '';
    var o = find(c.contents) || (x.kind === 'once' || x.kind === 'cap' ? find(c.verify) || find(c.files) || find(c.koc) : null);
    return !o ? '' : o.kind ? contentName(o) : (lang === 'zh' && FILE_ZH[o.name]) || o.name;
  }
  function pfKey() { return CAT ? JSON.stringify(selection()) + '|' + CAT.version : null; }
  function pfPending() { return PF.items.filter(function (x) { return !x.done; }); }
  function pfSeen(step) { PF.items.forEach(function (x) { if (x.step && x.step === step) x.done = true; }); }
  /* The page being switched off is the server's state: it leaves when an answer no longer says it. */
  function pfTake(changes, cat) {
    var off = changes.some(function (c) { return c.kind === 'off'; });
    PF.items = PF.items.filter(function (x) { return x.kind !== 'off' || off; });
    changes.forEach(function (c) {
      var slug = c.slug == null ? null : String(c.slug);
      if (PF.items.some(function (x) { return !x.done && x.kind === c.kind && x.slug === slug; })) return;
      PF.items.push({ kind: c.kind, slug: slug, step: pfStep(c.kind), cat: cat, done: false });
    });
  }
  /* What the catalogue no longer offers leaves what is kept in the tab; the
     line naming it stays until its step is seen. */
  function prune() {
    if (!CAT) return;
    if (S.plan && !planOf()) S.plan = null;
    S.platforms = S.platforms.filter(function (k) { return CAT.platforms.indexOf(k) >= 0; });
    var p = planOf();
    if (p) {
      var ok = extrasOf(p).map(function (c) { return c.slug; });
      Object.keys(S.extra).forEach(function (k) { if (ok.indexOf(k) < 0) delete S.extra[k]; });
      if (S.mix >= (p.mix || []).length) S.mix = 0;
    }
    if (TERMS.indexOf(Number(S.term)) < 0) S.term = TERMS.indexOf(12) >= 0 ? 12 : TERMS[0];
    if (!CAT.translation) S.translate = false;
    if (S.koc && !CAT.koc.some(function (k) { return k.slug === S.koc; })) S.koc = '';
    keep();
  }
  function pfHtml() {
    var w = t().pf, list = pfPending();
    if (!list.length) return '';
    return '<section class="sumcard qs-pf" aria-labelledby="qsPfH"><div class="sumcard-head"><h2 id="qsPfH">' + esc(w.pfHead) + '</h2></div>' +
      '<ul class="qs-pflist">' + list.map(function (x) {
        var line = f(w[PF_WORD[x.kind]] || w.choiceGone, { x: pfName(x) || w.pfThing });
        var act = x.kind === 'version' ? '<button class="btn btn-sm" type="button" data-a="pfok">' + esc(w.pfCont) + '</button>'
          : x.step ? '<button class="btn btn-sm" type="button" data-a="pfgo" data-to="' + x.step + '" aria-label="' + esc(w.pfEdit + ': ' + line) + '">' + esc(w.pfEdit) + '</button>' : '';
        return '<li><span class="qs-pftext">' + esc(line) + '</span>' + act + '</li>';
      }).join('') + '</ul></section>';
  }
  function pfDraw() { var b = $('qsPfBox'); if (b) { b.innerHTML = pfHtml(); b.hidden = !pfPending().length; } }
  function pfRefuse() {
    say('qsMsg', t().pf.pfWait);
    var b = root().querySelector('#qsPfBox .btn'); if (b) b.focus();
  }
  /* Answers clean or not. A database before this release, or a request
     lost, answers clean: Submit's own create checks the same again. */
  function pfRun(then) {
    var key = pfKey(), done = function (clean) { if (then) then(clean); };
    if (!key) { done(true); return; }
    PF.key = key;
    db.rpc('quote_preflight', { p_sel: selection(), p_seen: { version: CAT.version } }).then(function (r) {
      var d = r && r.data;
      if (r.error || !d || d.error || !Array.isArray(d.changes)) { done(!pfPending().length); return; }
      pfFound(d.changes, done);
    }).catch(function () { done(!pfPending().length); });
  }
  function pfFound(changes, then) {
    pfTake(changes, CAT);
    var fin = function () { pfDraw(); then(!pfPending().length); };
    if (!changes.some(function (c) { return c.kind !== 'off'; })) { fin(); return; }
    load(function () { prune(); PF.key = pfKey(); if (S.step === 'details' && !Q) pfDraw(); fin(); });
  }

  // ---- Moving through the steps -------------------------------------------------
  function next() {
    var a = steps(), i = a.indexOf(S.step);
    if (S.step === 'need') {
      if (!Object.keys(S.need).some(function (k) { return S.need[k]; })) { say('qsMsg', t().needNone); return; }
      if (S.need.ads && S.need.social && !S.plan) S.withAds = true;
    }
    if (S.step === 'plan' && (!planOf() || !S.platforms.length)) { say('qsMsg', t().planNone); return; }
    /* Only one-time items asked for (verification alone, say): one of them
       is picked before the details are asked. */
    if (S.step === 'custom') {
      var sel = selection();
      if (!sel.plan && !adsAsked() && !(sel.once || []).length) { say('qsMsg', t().needNone); return; }
      /* A KOL campaign and a custom creator list are quoted on request: one
         of them alone makes no quotation (2026-10-29: one went through with no
         line and no figure). */
      if (!sel.plan && !adsAsked() && (sel.once || []).every(onRequest)) { say('qsMsg', t().reqOnly); return; }
    }
    if (S.step === 'details') { make(); return; }
    go(a[i + 1]);
  }
  function onRequest(o) {
    return o.slug === CAT.kol || CAT.koc.some(function (k) { return k.slug === o.slug && !k.creators; });
  }
  function readDetails() {
    var c = S.contact;
    c.salutation = $('qsSal') ? $('qsSal').value : '';
    c.name = $('qsName').value.replace(/\s+/g, ' ').trim(); c.email = $('qsEmail').value.trim();
    c.whatsapp = $('qsWa').value.trim(); c.brand = $('qsBrand').value.replace(/\s+/g, ' ').trim();
    readFields(c); c.consent = $('qsConsent').checked;
    c.comments = $('qsCm') ? $('qsCm').value.trim() : '';
    keep();
  }
  /* The lead's Urgency to commence, the date's period where a day is chosen:
     on or before the day before the same day three months on, Within 3
     months; six, 3 to 6 months; else More than 6 months. */
  function startPeriod(c) {
    if (c.commence !== 'date') return c.commence;
    var C = window.ADspaceClock, today = todayMY();
    return c.commence_on <= C.periodEnd(today, 3) ? '1_3' : c.commence_on <= C.periodEnd(today, 6) ? '3_6' : '6_plus';
  }
  function checkDetails() {
    readDetails();
    var c = S.contact, first = null, bad = function (id, w) { say(id + 'Msg', w); var el = $(id); if (el) el.setAttribute('aria-invalid', 'true'); first = first || el; };
    ['qsName', 'qsEmail', 'qsWa', 'qsBrand', 'qsConsent', 'qsCm'].concat(FIELD_IDS).forEach(function (id) { say(id + 'Msg', ''); if ($(id)) $(id).removeAttribute('aria-invalid'); });
    if (c.name.length < 2) bad('qsName', t().req.name);
    if (!ADspaceWords.emailOk(c.email)) bad('qsEmail', t().req.email);
    else if (FREE.test(c.email)) say('qsEmailMsg', t().freeMail, 'warn');
    if (!waOk(waDigits(c.whatsapp))) bad('qsWa', t().waBad);
    if (c.brand.length < 2) bad('qsBrand', t().req.brand);
    checkFields(c, GROUPS, bad);
    if (c.comments.length > 1000) bad('qsCm', t().ik.say.comments);
    if (!c.consent) bad('qsConsent', t().req.consent);
    if (first) first.focus();
    return !first;
  }
  function make() {
    if (!checkDetails()) return;
    var btn = root().querySelector('[data-a="next"]');
    /* A line to act on stops Submit here; the page switched off is asked again. */
    if (pfPending().some(function (x) { return x.kind !== 'off'; })) { pfRefuse(); return; }
    /* The button keeps its words and turns while the request is out (js/acts.js). */
    btn.disabled = true;
    pfRun(function (clean) {
      if (!clean) { btn.disabled = false; pfRefuse(); return; }
      send(btn);
    });
  }
  function send(btn) {
    /* One key a selection and email: a press again after a lost reply is
       the same request, but a changed selection is a new one, never answered
       with the quotation made for the old (audit 2026-11-15). */
    var fp = JSON.stringify(selection()) + '|' + String(S.contact.email || '').toLowerCase();
    if (!S.idem || S.idemFor !== fp) { S.idem = key8(); S.idemFor = fp; keep(); }
    /* The Rate Card version the page read rides with the selection: the
       create refuses a card moved on since (`changed`), and keeps nothing of it. */
    var body = { sel: Object.assign(selection(), { seen: CAT.version }), idem: S.idem,
      contact: { salutation: S.contact.salutation || '', name: S.contact.name, email: S.contact.email, whatsapp: waDigits(S.contact.whatsapp), brand: S.contact.brand,
        industry: S.contact.industry || null, commence: startPeriod(S.contact), commence_on: S.contact.commence_on || null, consent: true, lang: lang,
        kind: S.contact.kind, brn: brnDigits(S.contact.brn), legal: S.contact.legal, website: S.contact.no_site ? '' : S.contact.website,
        no_site: !!S.contact.no_site, platform: S.contact.handle ? S.contact.platform : null, handle: S.contact.handle || '',
        comments: S.contact.comments || '' } };
    var C = window.ADspaceCaptcha;
    var token = C && C.on ? C.token(root().querySelector('[data-cf]')) : Promise.resolve(null);
    token.then(function (tk) {
      body.token = tk || '';
      return db.functions.invoke('quote-request', { body: body });
    }).then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error || !d.key) {
        btn.disabled = false;
        if (d.error === 'changed' && Array.isArray(d.changes)) { pfFound(d.changes, function () { pfRefuse(); }); return; }
        /* An industry renamed or removed while the form was open: the list
           is read again and the choice cleared (audit 2026-11-04, 5). */
        if (d.error === 'bad-industry') {
          S.contact.industry = ''; keep();
          db.rpc('industries_list').then(function (r2) { if (r2 && !r2.error && Array.isArray(r2.data)) INDUSTRIES = r2.data; })
            .catch(function () {}).then(function () { paint(); say('qsMsg', t().err['bad-industry']); });
          return;
        }
        if (fieldRefused(d)) return;
        say('qsMsg', t().err[d.error] || t().err.any);
        return;
      }
      // Made: nothing chosen or typed stays in the tab (a refresh reads the quotation by its key).
      madeBy = S.contact;
      S = blank(); PF = { items: [], key: null };
      try { sessionStorage.removeItem(KEEP); } catch (e) {}
      history.replaceState(null, '', '/quote/?q=' + encodeURIComponent(d.key));
      read(d.key);
    }).catch(function () { btn.disabled = false; say('qsMsg', t().err.any); });
  }
  function read(k, then) {
    db.rpc('quote_website_read', { p_key: k }).then(function (r) {
      var d = r && r.data;
      if (r.error || !d) { paint.off = true; Q = null; CAT = null; paint(); return; }
      if (d.error) { paint.lost = true; paint(); return; }
      Q = d; paint();
      if (then) then(); else window.scrollTo(0, 0);
      sealRead(k);
      chState(k);
    }).catch(function () { paint.off = true; paint(); });
  }
  /* The link read, kept as a step of the signed document's record (never a
     colleague's preview); once the agency has confirmed it, its Document ID and
     whether the sealed copy is kept (SIGNED DOCUMENT SEAL, 2026-11-17). */
  function sealRead(k) {
    if (!Q || PREVIEW) return;
    if (Q.stage !== 'review' && !sealRead.told) {
      sealRead.told = true;
      db.rpc('quote_opened', { p_key: k, p_device: window.ADspaceSeal ? window.ADspaceSeal.device() : null }).then(function () {}, function () {});
    }
    /* A closed quotation asks whether the client declined it; a confirmed
       one its seal and whether it was withdrawn (QUOTATION WAYS OUT). */
    var closed = stageOf(Q) === 'closed';
    if ((!Q.reviewed && !closed) || Q.seal || Q.declined) return;
    db.rpc('quote_seal_state', { p_key: k }).then(function (r) {
      var d = r && r.data;
      if (r.error || !d || !Q) return;
      if (!d.confirmed) { if (d.declined) { Q.declined = true; paint(); } return; }
      Q.seal = { id: d.id, sealed: !!d.sealed, withdrawn: !!d.withdrawn, withdrawn_on: d.withdrawn_on || null };
      paint();
    }).catch(function () {});
  }
  /* Decline (QUOTATION WAYS OUT, 2026-11-17): a reason if they wish, then
     the quotation reads Declined to them and Cancelled to the team, who
     are told. */
  function declineHtml() {
    var w = t();
    return '<h2>' + esc(w.declineT) + '</h2>' +
      sgField('qsDeclineWhy', w.declineWhy, false, '<textarea class="input" rows="1" id="qsDeclineWhy" maxlength="300" data-oneline placeholder="' + esc(w.declineHint) + '"></textarea>') +
      '<div class="qs-sfoot"><button class="btn" type="button" data-a="declineback">' + esc(w.back) + '</button>' +
      '<button class="btn" type="button" data-a="declinego">' + esc(w.decline) + '</button></div>' +
      '<p class="msg" id="qsSideMsg" role="status"></p>';
  }
  function declineSend(btn) {
    var why = ($('qsDeclineWhy') || {}).value || '';
    btn.disabled = true;
    db.rpc('quote_decline', { p_key: qKey(), p_reason: why.trim() || null }).then(function (r) {
      var d = (r && r.data) || {};
      if (r.error || d.error) { btn.disabled = false; say('qsSideMsg', t().err[{ closed: 'not-proceeding', unsent: 'not-sent' }[d.error] || d.error] || t().err.any); return; }
      Q.status = 'not_proceeding'; Q.stage = 'closed'; Q.declined = true;
      paint();
    }).catch(function () { btn.disabled = false; say('qsSideMsg', chNotSent()); });
  }
  /* At the press, once the PDF scripts are here (fetched where the button
     was drawn; at the press if that fetch failed). */
  function withPdf(btn, fn, fail) {
    btn.disabled = true;
    window.ADspaceChrome.needThen(['quotepdf'], false, function () { btn.disabled = false; fn(btn); })
      .catch(function () { btn.disabled = false; fail(); });
  }
  function pdf(btn) {
    withPdf(btn, pdfNow, function () { pdfSay(btn); });
  }
  function pdfSay(btn) {
    var said = $('qsPdfMsg'); if (said) said.remove();
    var acts = btn.closest('.qs-acts'), m = document.createElement('p');
    m.className = 'msg err'; m.id = 'qsPdfMsg'; m.setAttribute('role', 'status'); m.textContent = t().pdfFail;
    if (acts) acts.insertAdjacentElement('afterend', m);
  }
  function pdfNow(btn) {
    var said = $('qsPdfMsg'); if (said) said.remove();
    var tab = window.ADspaceDocs && window.ADspaceDocs.tabFor ? window.ADspaceDocs.tabFor() : null;
    btn.disabled = true;
    /* Who prepared and reviewed it, and once accepted who signed for the
       company with the signing record (2026-10-31). */
    var sg = Q.signed, C = window.ADspaceClock;
    /* No rate in the read (a page before its migration): the figures read
       first, so the PDF's S$ is the setting on its day of issue. */
    (Q.fx_sgd != null || !MON.load ? Promise.resolve() : MON.load()).then(function () {
    return window.ADspaceQuotePdf.draw(Q, { attention: Q.attention || '', client: qCli(), fx: Q.fx_sgd, key: qKey(),
      preparedBy: Q.prepared ? { name: Q.prepared.name, designation: Q.prepared.title || '' } : null,
      reviewedBy: Q.reviewed ? { name: Q.reviewed.name, designation: Q.reviewed.title || '', day: C.day(Q.reviewed.at) } : null,
      signed: sg ? { name: sg.signer.name, designation: sg.signer.designation, day: C.day(sg.at), signature: sg.signature, record: sg.record,
        via: sg.via, company: sg.company } : null,
      to: sg ? { name: (sg.company || {}).legal_name, address: (sg.company || {}).billing_address } : null });
    }).then(function (blob) {
      btn.disabled = false;
      window.ADspaceDocs.save(blob, window.ADspaceQuotePdf.fileName(Q), tab);
    }).catch(function () { btn.disabled = false; if (tab) try { tab.close(); } catch (e) {}
      /* Said under its button, drawn only when there is something to say. */
      pdfSay(btn);
    });
  }

  /* A colleague's preview (2026-10-30): the console's Preview opens the
     prospect's own link with preview=1. The page reads as the prospect's
     does, under a bar saying so, and takes no act on their behalf: Proceed,
     a new quotation and the billing form refuse in place. Reading the link
     writes nothing; the bar is the team's, so in English alone. */
  var PREVIEW = (function () { var u = new URLSearchParams(location.search); return u.get('preview') === '1' && !!u.get('q'); })();
  function previewBar() {
    if (!PREVIEW || $('qsPreviewBar')) return;
    var top = document.querySelector('.topbar');
    if (!top) return;
    var b = document.createElement('div');
    b.className = 'annbar previewbar'; b.id = 'qsPreviewBar';
    /* Its × hides it, so the page reads exactly as the prospect's; a
       refused press brings it back to say so (the user, 2026-10-30, A). */
    b.innerHTML = '<p class="annbar-text">Preview: the page as the prospect sees it. Nothing can be sent from it.</p>' +
      '<span class="msg" id="qsPreviewMsg" role="status"></span><span class="annbar-acts">' +
      '<button class="iconbtn annbar-x" id="qsPreviewHide" type="button" aria-label="Hide">' +
      window.ADspaceIcons.glyph('x') + '</button></span>';
    top.parentNode.insertBefore(b, top.nextSibling);
    $('qsPreviewHide').addEventListener('click', function () { b.hidden = true; });
  }
  function previewRefuse(e) {
    e.preventDefault(); e.stopPropagation();
    if ($('qsPreviewBar')) $('qsPreviewBar').hidden = false;
    say('qsPreviewMsg', 'Not available in preview.');
    /* Said in place too, where the press was (the signing card). */
    if (e.target.closest && e.target.closest('#qsSide')) say('qsSideMsg', 'Not available in preview.', 'warn');
  }
  if (PREVIEW) {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', previewBar); else previewBar();
    setTimeout(previewBar, 600);
    document.addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('#qsRoot [data-a="new"], #qsRoot [data-a="chsend"], #qsRoot [data-a="chwithdraw"], #qsRoot a[href^="/details/"], #qsRoot a[href="/quote/"], ' +
        '#qsRoot [data-a="signcode"], #qsRoot [data-a="signresend"], #qsRoot [data-a="signfinish"]');
      if (b) previewRefuse(e);
    }, true);
  }

  // ---- Presses ------------------------------------------------------------------
  document.addEventListener('click', function (e) {
    var b = e.target.closest('#qsRoot [data-a], #qsRoot [data-step]');
    if (!b) return;
    var a = b.getAttribute('data-a');
    if (b.hasAttribute('data-step')) {
      var g = b.getAttribute('data-group'), slug = b.getAttribute('data-slug');
      /* The change editor's steppers keep their counts on the change, the steps' in the tab. */
      var bag = g === 'chx' && CH ? CH.sel.extra : g === 'chf' && CH ? CH.sel.files : S[g];
      var row = b.closest('.qs-stepper'), up = row.querySelector('[data-step="1"]');
      var top = up && up.hasAttribute('data-max') ? Number(up.getAttribute('data-max')) : STEP_MAX;
      var n = (bag[slug] || 0) + Number(b.getAttribute('data-step'));
      bag[slug] = Math.max(0, Math.min(top, n));
      row.querySelector('b').textContent = bag[slug];
      row.querySelector('[data-step="-1"]').disabled = !bag[slug];
      /* At its cap + rests and the press moves to − on the same row. */
      if (up) { up.disabled = bag[slug] >= top; if (up.disabled && document.activeElement === up) row.querySelector('[data-step="-1"]').focus(); }
      /* A content piece added or taken away moves what the files may count. */
      if (g === 'once') filesRepaint();
      if (g === 'chx' && CH) chFilesRepaint();
      if (g !== 'chx' && g !== 'chf') keep();
      if (CH && (g === 'chx' || g === 'chf')) chPrice();
      return;
    }
    if (a === 'adhow') { adSheet(b); return; }
    if (a === 'askSend') { askSend(b); return; }
    if (a === 'svc') {
      var k = b.getAttribute('data-k'), on = !S.need[k];
      S.need[k] = on; b.classList.toggle('is-on', on); b.setAttribute('aria-pressed', String(on)); keep();
      var a = steps(), sp = root().querySelector('.qs-progress span'), bar = root().querySelector('.qs-track i');
      if (sp) sp.textContent = f(t().step, { n: 1, m: a.length + 1 });
      if (bar) bar.style.width = Math.round(1 / (a.length + 1) * 100) + '%';
      return;
    }
    if (a === 'next') next();
    else if (a === 'pfgo') { if (S.step === 'details' && $('qsName')) readDetails(); go(b.getAttribute('data-to')); }
    else if (a === 'pfok') {
      PF.items.forEach(function (x) { if (x.kind === 'version') x.done = true; });
      pfDraw(); say('qsMsg', '');
      var nb = root().querySelector('#qsPfBox .btn') || root().querySelector('[data-a="next"]'); if (nb) nb.focus();
    }
    else if (a === 'start') go('need');
    else if (a === 'back') { var s = steps(); go(S.step === 'need' ? 'intro' : s[Math.max(0, s.indexOf(S.step) - 1)]); }
    else if (a === 'decline') { $('qsSide').innerHTML = declineHtml(); decorate(); var dw = $('qsDeclineWhy'); if (dw) dw.focus(); }
    else if (a === 'declineback') { $('qsSide').innerHTML = sideHtml(Q); decorate(); var dg = $('qsSide').querySelector('[data-a="decline"]'); if (dg) dg.focus(); }
    else if (a === 'declinego') declineSend(b);
    else if (a === 'signgo') { signStart(); signShow(); }
    else if (a === 'signback') { signRead(); if (SG.step === 1) { SG = null; clearInterval(resendTimer); $('qsSide').innerHTML = sideHtml(Q); decorate(); var g = $('qsSide').querySelector('[data-a="signgo"]'); if (g) g.focus(); } else signShow(SG.step - 1); }
    else if (a === 'signnext') { if (signCheck()) signShow(2); }
    else if (a === 'signcode') signCode(b, false);
    else if (a === 'signresend') signCode(b, true);
    else if (a === 'signfinish') signFinish(b);
    else if (a === 'signclear') { SG.path = ''; signRead(); signShow(); var pd = $('sgPad'); if (pd) pd.scrollIntoView({ block: 'center' }); }
    else if (a === 'signmode') { signRead(); SG.mode = SG.mode === 'draw' ? 'type' : 'draw'; signShow(); var m = $('qsSide').querySelector('[data-a="signmode"]'); if (m) m.focus(); }
    else if (a === 'pdf') pdf(b);
    else if (a === 'sealed') sealedPdf(b);
    else if (a === 'change' && Q && chEditable(Q)) { if (!Q.change) chOpen(); }
    else if (a === 'chcancel') { CH = null; paint(); window.scrollTo(0, 0); }
    else if (a === 'chsend') chSend(b);
    else if (a === 'chwithdraw') chWithdraw(b);
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
    if (CH && (nm === 'chplan' || nm === 'chplat' || id === 'qsChMix' || id === 'qsChTerm' || id === 'qsChAds')) {
      if (nm === 'chplan') {
        CH.sel.plan = el.value; CH.sel.mix = 0; CH.sel.extra = {};
        chRepaint(); chPrice(); return;
      }
      if (nm === 'chplat') {
        CH.sel.platforms = CH.sel.platforms.filter(function (x) { return x !== el.value; });
        if (el.checked) CH.sel.platforms.push(el.value);
        if (!CH.sel.platforms.length) { CH.sel.platforms = [el.value]; el.checked = true; }
        var lb = el.closest('.qs-chip'); if (lb) lb.classList.toggle('is-on', el.checked);
      }
      if (id === 'qsChMix') { CH.sel.mix = Number(el.value) || 0; chFilesRepaint(); }
      if (id === 'qsChTerm') CH.sel.term = Number(el.value);
      if (id === 'qsChAds') {
        CH.withAds = el.value === 'ads';
        var cur = chPlan();
        if (cur && Boolean(cur.ads) !== CH.withAds) {
          var same = CAT.plans.filter(function (x) { return Boolean(x.ads) === CH.withAds && x.platforms === cur.platforms; })[0];
          if (same) { CH.sel.plan = same.slug; CH.sel.mix = 0; CH.sel.extra = {}; }
        }
        chRepaint();
      }
      chPrice(); chDraw(); return;
    }
    if (nm === 'plat') {
      S.platforms = S.platforms.filter(function (p) { return p !== el.value; });
      if (el.checked) S.platforms.push(el.value);
    }
    else if (nm === 'plan') {
      S.plan = el.value; S.mix = 0;
      // Extras the new plan does not offer leave with the old one.
      var ok = extrasOf(planOf()).map(function (c) { return c.slug; });
      Object.keys(S.extra).forEach(function (k) { if (ok.indexOf(k) < 0) delete S.extra[k]; });
      keep(); paint();
      var pc = root().querySelector('input[name=plan][value="' + el.value + '"]'); if (pc) pc.focus({ preventScroll: true });
      return;
    }
    else if (nm === 'lang') {
      S.langs = S.langs.filter(function (l) { return l !== el.value; });
      if (el.checked) S.langs.push(el.value);
      if (!S.langs.length) { S.langs = [el.value]; el.checked = true; }
      if (S.langs.length < 2) S.translate = false;
      keep(); paint(); return;
    }
    else if (nm === 'translate') { S.translate = el.checked; }
    else if (id === 'qsMix') { S.mix = Number(el.value) || 0; }
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
    else if (id === 'sgAgree') { if (SG) SG.agree = el.checked; el.removeAttribute('aria-invalid'); say('sgAgreeMsg', ''); return; }
    else if (id === 'qsStart') {
      var dayBox = $('qsStartOnBox');
      if (dayBox) dayBox.hidden = el.value !== 'date';
      el.removeAttribute('aria-invalid'); say('qsStartMsg', ''); return;
    }
    else if (id === 'qsConsent') { el.removeAttribute('aria-invalid'); say('qsConsentMsg', ''); }
    /* No website hides the address; Registering as clears the number's refusal. */
    else if (id === 'qsNoSite') {
      var siteBox = $('qsSiteBox');
      if (siteBox) siteBox.hidden = el.checked;
      ['qsSite', 'qsHandle'].forEach(function (x) { say(x + 'Msg', ''); if ($(x)) $(x).removeAttribute('aria-invalid'); });
      if (!Q) { S.contact.no_site = el.checked; keep(); }
      return;
    }
    else if (id === 'qsKind') { say('qsBrnMsg', ''); if ($('qsBrn')) $('qsBrn').removeAttribute('aria-invalid'); if (!Q) { S.contact.kind = el.value; keep(); } return; }
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
    if (e.target.id === 'qsAsk') { e.preventDefault(); var send2 = root().querySelector('[data-a="askSend"]'); if (send2 && !send2.disabled) askSend(send2); }
    /* Enter in a field of the signing card presses its forward step. */
    if (e.target.id === 'sgForm') { e.preventDefault(); var go = e.target.querySelector('.qs-sfoot .btn-primary'); if (go && !go.disabled) go.click(); }
  });
  // The code's six boxes: a digit each, typing, pasting and the iPhone's code moving along.
  document.addEventListener('input', function (e) {
    var el = e.target, i = el.getAttribute && el.getAttribute('data-otp');
    if (i == null) return;
    var d = el.value.replace(/\D/g, '');
    el.value = '';
    if (d) otpFill(Number(i), d.slice(0, 6 - Number(i)));
    say('sgCodeMsg', '');
  });
  document.addEventListener('focusin', function (e) {
    if (e.target.getAttribute && e.target.getAttribute('data-otp') != null && e.target.select) e.target.select();
  });
  document.addEventListener('keydown', function (e) {
    var el = e.target, i = el.getAttribute && el.getAttribute('data-otp');
    if (i == null) return;
    i = Number(i);
    if (e.key === 'Backspace' && !el.value && i > 0) { e.preventDefault(); var b = otpBoxes(); b[i - 1].value = ''; b[i - 1].focus(); }
    else if (e.key === 'ArrowLeft' && i > 0) { e.preventDefault(); otpFocus(i - 1); }
    else if (e.key === 'ArrowRight' && i < 5) { e.preventDefault(); otpFocus(i + 1); }
  });
  document.addEventListener('paste', function (e) {
    var el = e.target, i = el.getAttribute && el.getAttribute('data-otp');
    if (i == null) return;
    var d = ((e.clipboardData && e.clipboardData.getData('text')) || '').replace(/\D/g, '');
    if (!d) return;
    e.preventDefault();
    otpFill(d.length >= 6 ? 0 : Number(i), d.slice(0, 6));
  });
  document.addEventListener('input', function (e) {
    // A refusal leaves its field once the field is changed; the next press checks it again.
    var id = e.target.id;
    if (id && e.target.getAttribute('aria-invalid') === 'true') { e.target.removeAttribute('aria-invalid'); if (id !== 'qsEmail') say(id + 'Msg', ''); }
    if (id === 'qsEmail') {
      var v = e.target.value.trim();
      say('qsEmailMsg', ADspaceWords.emailOk(v) && FREE.test(v) ? t().freeMail : '', 'warn');
    }
    if (e.target.closest && e.target.closest('#qsDetails')) readDetails();
  });

  /* A quotation's own selection, to change and make again. */
  function adopt(sel) {
    // A plan with ads carries its own budget: not Advertising asked.
    var sp = CAT && sel.plan ? CAT.plans.filter(function (x) { return x.slug === sel.plan; })[0] : null;
    S.need = { social: Boolean(sel.plan), ads: sel.budget != null && !(sp && sp.ads), content: false, koc: false, verify: false };
    S.plan = sel.plan || null; S.mix = Number(sel.mix) || 0; S.platforms = (sel.platforms || ['meta']).slice(); S.extra = sel.extra || {};
    S.langs = (sel.langs || ['en']).slice(); S.translate = Boolean(sel.translate) && S.langs.length > 1; S.budget = sel.budget == null ? null : Number(sel.budget);
    S.term = TERMS.indexOf(Number(sel.term)) >= 0 ? Number(sel.term) : 12; S.once = {}; S.files = {}; S.koc = ''; S.kol = false; S.verify = [];
    (sel.once || []).forEach(function (o) {
      var c = CAT && CAT.contents.some(function (x) { return x.slug === o.slug; });
      if (c) { S.need.content = true; S.once[o.slug] = o.qty; }
      else if (CAT && (CAT.files || []).some(function (x) { return x.slug === o.slug; })) { S.files[o.slug] = o.qty; if (!S.need.social) S.need.content = true; }
      else if (CAT && CAT.koc.some(function (x) { return x.slug === o.slug; })) { S.need.koc = true; S.koc = o.slug; }
      else if (CAT && o.slug === CAT.kol) { S.need.koc = true; S.kol = true; }
      else { S.need.verify = true; S.verify.push(o.slug); }
    });
    var p = planOf(); if (p) S.withAds = Boolean(p.ads);
    keep();
  }

  function load(done) {
    if (!db) { paint.off = true; paint(); return; }
    db.rpc('industries_list').then(function (r) {
      INDUSTRIES = (r && !r.error && Array.isArray(r.data)) ? r.data : [];
      if (S.contact.industry && !INDUSTRIES.some(function (i) { return i.name === S.contact.industry; })) S.contact.industry = '';
      if (S.step === 'details' && !Q && $('qsInd')) paint();
    }).catch(function () {});
    db.rpc('quote_catalogue').then(function (r) {
      var d = r && r.data;
      if (r.error || !d || d.error) { paint.off = true; CAT = null; paint(); return; }
      CAT = d;
      if (Array.isArray(d.terms) && d.terms.length) TERMS = d.terms.map(Number).filter(function (n) { return n > 0; });
      if (S.plan && !planOf()) S.plan = null;
      if (done) done(); else paint();
    }).catch(function () { paint.off = true; paint(); });
  }

  if ($('langToggle')) $('langToggle').addEventListener('click', function () {
    lang = lang === 'en' ? 'zh' : 'en';
    try { localStorage.setItem(LANG_KEY, lang); } catch (e) {}
    if (S.step === 'details' && !Q && $('qsName')) readDetails();
    signRead();
    paint();
  });

  var given = new URLSearchParams(location.search).get('q');
  if (given) { load(function () { read(given); }); }
  else load();
})();
