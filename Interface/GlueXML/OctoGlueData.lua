-- Fallback challenge-mask table. Since v25 the character-select icons read
-- CustomData\octoglue-challenges live (written in-world by the OctoChallenges
-- addon, or mirrored from SavedVariables by the realm-status scheduled task);
-- this table is consulted only when that file is absent. Kept EMPTY in the
-- repo so a prebuilt patch-9.mpq is user-agnostic and safe to share.
-- Format: ["Realm/Name"] = mask,
OCTO_BAKED_CHALLENGES = {
}
