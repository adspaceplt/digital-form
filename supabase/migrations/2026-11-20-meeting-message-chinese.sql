-- ===========================================================================
-- MEETING MESSAGE IN CHINESE (2026-11-20)
-- ===========================================================================
-- WHY (the user, 2026-11-20: "fix the meeting message in both places", after
-- tone sweep 2): the message sent to a client for a month's meeting read
-- Meeting Agenda 摘要 (a summary, not an agenda), and its Content Discussion
-- and Link lines had no Chinese, where every other label does.
--
-- WHAT IT CHANGES
--   * `meeting_message_template`'s body, only where it still holds the seed
--     word for word: 摘要 becomes 议程, Content Discussion 内容讨论, Link
--     链接. A message the team edited in Settings is left as it is.
--
-- ORDER: the pages (js/ops.js carries the same words where the read fails),
-- then this file (the API). A tab open before either fills the old words.
-- Safe to run twice.
--
-- ROLLBACK: the seed written back where the body holds this file's words.
-- ===========================================================================

update public.meeting_message_template x set body =
  E'Meeting Schedule {meeting}\n\nDate 日期: {date}\nTime 时间: {time}\n\nMeeting Agenda 议程:\n•  {month} Content Discussion 内容讨论\n\nChannel 渠道:\n{channel}\nLink 链接: {link}',
  updated_at = now()
 where x.id = 1 and x.body =
  E'Meeting Schedule {meeting}\n\nDate 日期: {date}\nTime 时间: {time}\n\nMeeting Agenda 摘要:\n•  {month} Content Discussion\n\nChannel 渠道:\n{channel}\nLink: {link}';

-- END OF MEETING MESSAGE IN CHINESE ------------------------------------------
