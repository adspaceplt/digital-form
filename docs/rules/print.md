<!-- triggers: js/documents.js js/letters.js js/quotepdf.js js/ratecardpdf.js js/smreport.js js/scriptpdf.js js/seal.js js/hrdocs.js js/perf.js docs/templates/ -->
# Print: every PDF (the templates, the head and the foot, a sealed copy's Record page, a quotation, letter tables)

Moved whole from `DESIGN.md` §2 Typography, which keeps a one-line pointer here; read whole before drawing or changing any PDF.

- Print: the company's Word templates (`docs/templates/`; the user,
  2026-11-20: "please take note of the header and footer. it should remain
  in place", "yes align all to the templates"), drawn by the one pen
  (`ADspaceDocs.pen`, its figures `ADspaceDocs.PAGE`, measured from the
  templates rendered in their own fonts), the head and the foot at the same
  place on every page whatever the page holds:
  - the page: A4, margins 72pt top and bottom, 54pt each side; the head
    28.8pt under the top edge, the foot 28.8pt over the bottom edge;
  - inks, the user's palette (2026-11-20: "white with #515151, #f5f5f5
    with #1a1a1a"; then the wordmark and the foot): the body and the
    ADspace wordmark `#515151` on the white page; a title, the headings,
    PRIVATE & CONFIDENTIAL in the body and ADSPACE PLT `#1a1a1a`; the
    head's and the foot's marks (the page count, FOR INTERNAL USE, the
    foot's PRIVATE & CONFIDENTIAL, the verify line, Co. Reg., the page's
    reference) `#a1a1a1`, never the body; hairlines `#cfd0d4`; a shaded
    box `#f5f5f5` with `#1a1a1a` words (`pen().ink`, `strong`, `faint`,
    `line`, `shade`; `pdfreal` reads each run's fill);
  - the faces are the templates' four alone: Optima (the wordmark), Slate
    Medium, Slate Regular and Slate Book; Slate Light, the ACL page count's
    face in the template, is not held, so it is Slate Book;
  - an uppercase mark (PRIVATE & CONFIDENTIAL, FOR INTERNAL USE) carries
    no letter spacing: the user's 1.08pt, set as character spacing, read
    letter by letter to pdf.js (F O R I N T E R N A L), so it was dropped
    (2026-11-20);
  - a letter's title is the body's size in Slate Medium; a title on any
    other document is the body times φ (17.8pt on 11pt, 16.18pt on 10pt;
    `ADspaceDocs.TITLE`);
  - the Date beside Our Ref is the portal's date (`20 Nov 2026`,
    `ADspaceDocs.refDate`), never the template's superscript ordinal;
  - AL (the letterhead): the wordmark in Optima 16pt top left (baseline
    60.2pt from the top); Page n of N in Slate Book 8pt from 493.75pt
    (baseline 47pt from the bottom);
  - ALP (internal): AL's head with FOR INTERNAL USE in Slate Medium 8pt
    centred on the page (58.9pt); the foot PRIVATE & CONFIDENTIAL in Slate
    Medium 8pt at the left (48.9pt from the bottom) and AL's page count; a
    form's title opens its first page in Slate Medium 15pt over a hairline;
  - ACL_SIGN and ACL_NOSIGN (a lettered document to a party): page one the
    full letterhead (the wordmark Optima 14pt, Co. Reg. 9pt, the address
    11pt on 12.5pt lines at the left; the phone, email and website at the
    right edge; the monogram 20.3pt square top right), later pages the
    wordmark and the monogram; the foot the verify line centred in Slate
    Book 6pt (This is a computer-generated document. [No signature
    required. ]Verify document authenticity: go.adspace.me/verify) and Page
    n of N in 7.5pt at the right margin; the body PRIVATE & CONFIDENTIAL (Slate
    Medium) at 155.1pt, Our Ref and Date a blank line under it, the
    recipient's name (Slate Regular) over its lines, the title (Slate
    Medium), the salutation and the message a blank line apart, single
    lines of 12.5pt at 11pt, then Yours sincerely, and ADSPACE PLT in Slate
    Medium;
  - which template (`ADspaceDocs.TEMPLATE`, `templateOf(kind, signed)`; a
    new PDF joins it): ACL_SIGN for a document carrying a signature block
    or signing page (the Letter of Offer, a signed client, HR or supplier
    letter, the Supplier Service Agreement, the Employment Contract, and a
    sealed copy's Record page), ACL_NOSIGN for one that does not (an
    unsigned letter, the Employment Offer); ALP for an admin's working form
    (Employee Record Form, Interview Sheet, Onboarding Checklist, Welcome
    Kit, a client's checklist, the Analytics Analysis) and the Rate Card;
    AL for the rest (the Monthly Performance Record, the quotation, the
    Social Media Report, the video scripts), whose bodies keep their own
    layout between the template's margins; a white-label report puts its
    partner's logo in the wordmark's place;
  - a sealed copy's Record page (`js/seal.js`, the user, 2026-11-21: "Sorry
    what i mean is to use this", Apple's print design the model) is a dated
    timeline in about a quarter of the page: Record of this Document 13pt
    Slate Medium after the padlock, the Document ID at its right on its
    baseline (Document ID 7pt, the code 9pt Slate Medium); the sentence
    8pt; a hairline; at the left the steps under their Malaysian day
    (`12 Jan 1988 · GMT+8`, 7pt Slate Medium, no weekday), each a line of
    8pt on 10pt: the time to the second in a 54pt column, the step's word
    in Slate Medium, the rest a sentence, and its device on one 6.3pt line;
    a 4pt dot a step on a 0.6pt hairline, filled for Signed and Confirmed;
    at the right, at least 96pt, the QR code 32pt, Scan to check this copy
    over the verify address, then SHA-256, pages 1 to n over the hash on
    two lines of 32 characters, all 6pt; inks as above (the words
    `#515151`, a step's word, the title and the code `#1a1a1a`, never
    `#a1a1a1`); a long record runs on under the same head;
  - a lettered foot is one row on one baseline (794.5pt; the user,
    2026-11-24: "the serial id or document id and the computer generated
    document and the page x of x should be same in line same row"): the
    reference, then the verify line with its Document ID, from the left
    margin, and Page n of N at the right margin (the reference gives way
    first where the row would reach the page count); Client initials is a
    box (112 by 36pt) at the right over the row, and the body stops 14pt
    above it;
  - an AL document a client receives (a quotation, a report as published, a
    video script as shared, the Monthly Performance Record) is one row on
    the page count's baseline (794.9pt; the user, 2026-11-24: "Document ID
    | Verify document | Page x of x"): `Document ID XXXX-XXXX · Verify document
    authenticity: go.adspace.me/verify` in Slate Book 6.5pt from the left margin, Page n
    of N 8pt at the right margin; an ALP form keeps PRIVATE & CONFIDENTIAL
    and the template's page count, and a draft and a white-label report the
    page count alone;
  - a quotation's section heads carry an outline glyph alone (0.75pt in
    `#515151`, about 10pt, never filled) in an 18pt `#f5f5f5` disc on the
    heading's capitals, never a number; its billing note in the mute ink at
    the label size on the heading's baseline at the right margin; PROPOSED
    FEES alone on its row (2026-11-25);
  - a quotation's Add-on Rates are a block anchored above the foot of its
    fees page, as a sealed copy's Record is, two columns with dotted
    leaders and the unit mute, never in a total; where it does not fit it
    takes the next page under the same head (2026-11-25);
  - a summary of totals never stands on a page alone: the last line carries
    the summary's height, and moves over with it where both do not fit
    (letters and quotations alike, 2026-11-24);
  - nothing else in the head or the foot; a mark a document needs on every
    page (the Letter of Offer's Client initials, the performance record's
    reference line, the Rate Card's version) stands in the bottom margin
    clear of the foot.
  - Config holds file paths, never font names.
- Letter tables: Description, Rate, Amount only. Quantity rides in the rate
  cell. The term sits mute under the Amount. Inclusions go under the name, then
  one mute line of basis, period and note. TERMS holds the term, then the letter's own points as typed, the first its validity.
