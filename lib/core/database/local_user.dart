/// The single on-device user id used by every `user_id`-keyed table
/// (`bookmarks`, `notes`, `reading_state` — spec §15). The app has no
/// accounts/authentication (Prompt 14, spec's User Layer) — the schema
/// keys these tables on `user_id` for future multi-user support, but today
/// there is exactly one user per install. One shared constant so the value
/// can't drift between the bookmark/note/reading-state repositories.
const String localUserId = 'local_user';
