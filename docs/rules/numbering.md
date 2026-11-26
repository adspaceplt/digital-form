<!-- triggers: supabase/ js/settings.js -->
# Numbering (DESIGN.md §7)

Moved whole from `DESIGN.md` §7 Architecture, which keeps a one-line pointer here; read whole before adding or changing a number or reference (Settings numbering, `id_formats`).

- Numbering:
  - Letter of Offer `AQL/{client_code}/{YYMM}{NN}` (ADspace Quotation Letter): no longer issued since 2026-11-12, the quotation being the one contract; letters issued before keep their numbers;
  - campaign invoice `AINV` plus six digits, typed;
  - tasks `#WT00001`;
  - task codes `YYMMW{week}{NN}`;
  - HR `ADHR/…`;
  - client letters `ACL/{client code}/{YYMMDD}{NN}` (ADspace Client Letter);
  - Creator ID `ADC0001` (ADspace creator), Campaign ID `CC001` (creator campaign), a booking's Job reference
    `ADC0001/CC001`, a creator's payment details `ADC0001/R001`, each
    prefix, width, next number and the references' shape a setting
    (`id_formats`);
  - a website quotation request `ADP/REQ{YYMM}-{AAA}`, three random
    letters, never a running count, so nobody can read how many requests
    came in; a team's quotation reads `ADP/QT{YYMM}-DRAFT` until
    confirmed; a revision after Sent is numbered under its family's first
    quotation, `ADP/QT2611-C02-R1`, `-R2`, never a new serial (the `request`
    and `revision` rows of `id_formats`).
  - A new reference follows the house scheme (the user, 2026-11-26):
    the shortest prefix is the top of the structure and the longer ones
    hang under it. `ADP` names what the ADspace Digital Portal issued;
    `AD` a team member, `AC` a client, `AS` a supplier, each with an
    `NNN` serial; `ADHR` HR use (employment, `EMP`, files under HR);
    `ACL` a letter to a client. Every other reference is
    built from the record it belongs to, as a booking's
    `ADC0001/CC001` is: references link into one loop, never stand
    alone. References already issued keep their form.
