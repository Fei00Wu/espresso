CREATE TABLE IF NOT EXISTS UTTERANCES(
    utt_id TEXT, 
    wav TEXT NOT NULL,
    script TEXT NOT NULL,
    spk_id TEXT NOT NULL,
    feats TEXT,
    hires_feat TEXT,
    corpus TEXT,
    duration, TEXT,
    split_by_utt TEXT,
    PRIMARY KEY (utt_id)
);

CREATE TABLE IF NOT EXISTS SPEAKERS (
    spk_id TEXT,
    gender TEXT NOT NULL,
    cmvn TEXT,
    hires_cmvn TEXT,
    split_by_spk TEXT,
    PRIMARY KEY (spk_id)
);

