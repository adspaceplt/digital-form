-- ===========================================================================
-- QUOTATION COVER WORDS (2026-11-26)
-- ===========================================================================
-- WHY: the unslop pass (2026-11-26, PDF item 4): the Quotation Cover is page 1
-- of the quotation's own PDF, so "set out in the attached quotation" misread,
-- and its closing paragraph was boilerplate.
--
-- WHAT IT CHANGES
--   * `doc_types` `quote_cover`: `body_en` (and its 中文 and Malay, in
--     Simplified Chinese as every other 中文 line) reads "…set out in the following
--     pages." and drops its last paragraph, only where it still holds the
--     seeded words (a type the team edited is kept).
--
-- ORDER: the page first (its stand-in words change with it), then this file.
-- Safe to run twice. Holds no drop or delete.
-- ROLLBACK: set `body_en`, `body_zh` and `body_ms` back to the seeded words
-- in DOCUMENT TYPES.
-- ===========================================================================

-- QUOTATION COVER WORDS -------------------------------------------------------

-- The seeded words, as they stood, take the page's: the details are on the
-- following pages of the same PDF, and the closing paragraph goes. A type the
-- team has edited is left as it is.
update public.doc_types
   set body_en = E'We are pleased to submit our quotation for your consideration. It has been prepared based on the scope and requirements discussed, with full details set out in the following pages.\n\nShould you need any clarification or additional information, please do not hesitate to contact us. We would be pleased to provide further materials to support your evaluation.'
 where id = 'quote_cover'
   and body_en = E'We are pleased to submit our quotation for your consideration. It has been prepared based on the scope and requirements discussed, with full details set out in the attached quotation.\n\nShould you need any clarification or additional information, please do not hesitate to reach out. We are happy to provide further materials to support your evaluation.\n\nThank you for the opportunity. We look forward to working with you and your team.';

update public.doc_types
   set body_zh = E'我们很荣幸为贵司提呈本报价。本报价根据双方所讨论的范围与需求拟定，详情载于随后各页。\n\n如需任何说明或补充资料，敬请与我们联系。我们乐意提供更多资料，以供贵司评估。'
 where id = 'quote_cover'
   and body_zh = E'我們很榮幸能為貴司提呈本次報價。此報價乃根據貴司需求擬定，詳細內容請見附件報價單。\n\n若在審閱過程中有任何疑問或需要補充資料，歡迎隨時與我們聯繫。\n\n感謝貴司給予此次機會，期待有幸與貴司團隊展開合作。';
update public.doc_types
   set body_ms = E'Dengan sukacitanya kami mengemukakan sebut harga ini untuk pertimbangan pihak tuan/puan. Sebut harga ini telah disediakan berdasarkan skop dan keperluan yang telah dibincangkan, dengan butiran lengkap dinyatakan dalam halaman berikutnya.\n\nSekiranya pihak tuan/puan memerlukan sebarang penjelasan atau maklumat lanjut, sila hubungi kami. Kami dengan senang hati akan menyediakan maklumat tambahan yang diperlukan untuk penilaian pihak tuan/puan.'
 where id = 'quote_cover'
   and body_ms = E'Dengan sukacitanya kami mengemukakan sebut harga ini untuk pertimbangan pihak tuan/puan. Sebut harga ini telah disediakan berdasarkan skop dan keperluan yang telah dibincangkan, dengan butiran lengkap disertakan dalam dokumen yang dilampirkan.\n\nSekiranya pihak tuan/puan memerlukan sebarang penjelasan atau maklumat lanjut, sila hubungi kami. Kami dengan senang hati akan membantu dan menyediakan maklumat tambahan yang diperlukan untuk penilaian pihak tuan/puan.\n\nTerima kasih atas peluang yang diberikan. Kami menantikan peluang untuk bekerjasama dengan pihak tuan/puan dan pasukan anda.';

-- END OF QUOTATION COVER WORDS ------------------------------------------------
